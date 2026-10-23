import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../features/warranties/domain/entities/warranty.dart';

class PdfExportException implements Exception {
  const PdfExportException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PdfService {
  PdfService({
    Future<Directory> Function()? documentsDirectory,
    pw.Font? regularFont,
    pw.Font? boldFont,
    DateTime Function()? clock,
  })  : _documentsDirectory = documentsDirectory ?? getApplicationDocumentsDirectory,
        _regularFont = regularFont ?? pw.Font.helvetica(),
        _boldFont = boldFont ?? pw.Font.helveticaBold(),
        _clock = clock ?? DateTime.now;

  final Future<Directory> Function() _documentsDirectory;
  final pw.Font _regularFont;
  final pw.Font _boldFont;
  final DateTime Function() _clock;

  /// Geração totalmente local. A imagem ocupa uma página de anexo, sem recorte.
  /// Se uma fotografia associada estiver inacessível, não exporta silenciosamente
  /// um relatório incompleto: lança PdfExportException.
  Future<Uint8List> generateWarrantyPdf(
    Warranty warranty, {
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    if (!pageFormat.width.isFinite || !pageFormat.height.isFinite ||
        pageFormat.width < 200 || pageFormat.height < 200) {
      throw ArgumentError('É necessário um formato de página finito, como A4.');
    }
    final photo = warranty.fotoPath == null
        ? null
        : await _loadPhoto(warranty.fotoPath!);
    final generatedAt = _clock();
    final remaining = warranty.diasRestantesEm(generatedAt);
    final statusColor = remaining < 0
        ? PdfColor.fromHex('#B3261E')
        : remaining <= 30
            ? PdfColor.fromHex('#9A5700')
            : PdfColor.fromHex('#237A3B');
    final status = remaining < 0
        ? 'Garantia expirada'
        : remaining == 0
            ? 'Termina hoje'
            : '$remaining dias restantes';

    final document = pw.Document(
      title: 'Garantia - ${warranty.titulo}',
      author: 'WarrantyBox',
      creator: 'WarrantyBox',
      theme: pw.ThemeData.withFont(base: _regularFont, bold: _boldFont),
    );

    document.addPage(pw.MultiPage(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(36),
      footer: _footer,
      build: (_) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(22),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#D1F267'),
            borderRadius: pw.BorderRadius.circular(16),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('WARRANTYBOX', style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.Text('Relatório de garantia', style: pw.TextStyle(
                  fontSize: 25, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Text('Gerado em ${_date(generatedAt)}'),
            ],
          ),
        ),
        pw.SizedBox(height: 24),
        pw.Text(warranty.titulo, style: pw.TextStyle(
            fontSize: 21, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Text(status, style: pw.TextStyle(
            color: statusColor, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 20),
        _detail('Loja', warranty.loja),
        _detail('Valor', _money(warranty)),
        _detail('Data de compra', _date(warranty.dataCompra)),
        _detail('Período de garantia', '${warranty.duracaoMeses} meses'),
        _detail('Data de expiração', _date(warranty.dataExpiracao)),
        _detail('Categoria', _category(warranty.categoria)),
        if (warranty.notas?.trim().isNotEmpty == true) ...[
          pw.SizedBox(height: 18),
          pw.Text('Notas', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(warranty.notas!),
        ],
        pw.SizedBox(height: 20),
        pw.Text(photo == null ? 'Sem imagem de fatura associada.'
            : 'Fotografia da fatura incluída na página de anexo.'),
        pw.SizedBox(height: 8),
        pw.Text('Resumo dos dados registados pelo utilizador. '
            'Este relatório não substitui a fatura original.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ],
    ));

    if (photo != null) {
      document.addPage(pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Anexo - Fotografia da fatura', style: pw.TextStyle(
                fontSize: 19, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text(warranty.titulo),
            pw.SizedBox(height: 16),
            pw.Expanded(child: pw.Center(child: pw.Image(
              photo, fit: pw.BoxFit.contain,
            ))),
            pw.SizedBox(height: 12),
            _footer(context),
          ],
        ),
      ));
    }
    return document.save();
  }

  Future<void> preview(BuildContext context, Warranty warranty) async {
    final bytes = await generateWarrantyPdf(warranty);
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Relatório de garantia')),
        body: PdfPreview(
          build: (_) async => bytes,
          initialPageFormat: PdfPageFormat.a4,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          pdfFileName: fileName(warranty),
          allowPrinting: true,
          allowSharing: true,
        ),
      ),
    ));
  }

  Future<bool> printWarranty(Warranty warranty) => Printing.layoutPdf(
        name: fileName(warranty),
        onLayout: (format) => generateWarrantyPdf(warranty, pageFormat: format),
      );

  /// Passar os bounds do botão no iPad para posicionar corretamente o popover.
  Future<bool> shareWarranty(Warranty warranty, {Rect? bounds}) async {
    final bytes = await generateWarrantyPdf(warranty);
    return Printing.sharePdf(
      bytes: bytes, filename: fileName(warranty), bounds: bounds,
      subject: 'Relatório de garantia - ${warranty.titulo}',
    );
  }

  static String fileName(Warranty warranty) {
    final id = warranty.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'WarrantyBox_${id.isEmpty ? 'garantia' : id.substring(0, math.min(id.length, 80))}.pdf';
  }

  Future<pw.MemoryImage> _loadPhoto(String relativePath) async {
    if (relativePath.contains('\\') || !relativePath.startsWith('invoices/') ||
        relativePath.split('/').contains('..') || p.posix.isAbsolute(relativePath)) {
      throw const PdfExportException('O caminho da fotografia não é válido.');
    }
    final root = await _documentsDirectory();
    final file = File(p.joinAll([root.path, ...relativePath.split('/')]));
    if (!await file.exists()) {
      throw const PdfExportException('A fotografia associada não foi encontrada.');
    }
    final canonicalRoot = await root.resolveSymbolicLinks();
    final canonicalFile = await file.resolveSymbolicLinks();
    if (!p.isWithin(canonicalRoot, canonicalFile)) {
      throw const PdfExportException('A fotografia está fora da pasta privada.');
    }
    if (await file.length() > 40 * 1024 * 1024) {
      throw const PdfExportException('A fotografia excede o limite de 40 MB.');
    }

    // Normalizar para PNG localmente: o pacote PDF não descodifica HEIC.
    // O suporte do codec de origem depende do Android/iOS onde a app corre.
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes());
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale = math.min(1.0, 4096 / math.max(descriptor.width, descriptor.height));
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Imagem sem dados.');
      return pw.MemoryImage(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } catch (_) {
      throw const PdfExportException('Não foi possível converter a fotografia para PDF. '
          'Tenta uma imagem JPEG ou PNG.');
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static pw.Widget _detail(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 3),
          pw.Text(value, style: const pw.TextStyle(fontSize: 12)),
        ]),
      );

  static pw.Widget _footer(pw.Context context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('WarrantyBox - Página ${context.pageNumber}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      );

  static String _date(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
  static String _money(Warranty warranty) => '${warranty.preco ~/ 100},'
      '${(warranty.preco % 100).toString().padLeft(2, '0')} '
      '${warranty.moeda == 'EUR' ? '€' : warranty.moeda}';
  static String _category(String id) => const {
        'eletronica': 'Eletrónica', 'eletrodomesticos': 'Eletrodomésticos',
        'casa': 'Casa', 'vestuario': 'Vestuário', 'outros': 'Outros',
      }[id] ?? id;
}
