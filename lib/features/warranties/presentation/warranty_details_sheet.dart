import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/pdf_service.dart';
import '../application/dashboard_controller.dart';
import '../domain/entities/warranty.dart';

class WarrantyDetailsSheet extends StatefulWidget {
  const WarrantyDetailsSheet({required this.warranty, required this.pdfService,
    required this.onDelete, super.key});

  final Warranty warranty;
  final PdfService pdfService;
  final Future<bool> Function(Warranty) onDelete;

  @override
  State<WarrantyDetailsSheet> createState() => _WarrantyDetailsSheetState();
}

class _WarrantyDetailsSheetState extends State<WarrantyDetailsSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _export(BuildContext anchor, {required bool share}) async {
    if (_busy) return;
    // Capturar o retângulo antes de qualquer await: o popover iPad precisa dele.
    final render = anchor.findRenderObject();
    final bounds = render is RenderBox && render.hasSize
        ? render.localToGlobal(Offset.zero) & render.size : null;
    setState(() { _busy = true; _error = null; });
    try {
      if (share) {
        await widget.pdfService.shareWarranty(widget.warranty, bounds: bounds);
      } else {
        await widget.pdfService.preview(context, widget.warranty);
      }
    } on PdfExportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível exportar o PDF. Tente novamente.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final deleted = await widget.onDelete(widget.warranty);
      if (deleted && mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível eliminar a fatura.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final warranty = widget.warranty;
    final price = NumberFormat.currency(locale: 'pt_PT', name: warranty.moeda,
        symbol: warranty.moeda == 'EUR' ? '€' : warranty.moeda).format(warranty.preco / 100);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(warranty.titulo, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('${warranty.fotoPath == null ? 'Registo manual' : 'Fatura local'} · ${warranty.loja}'),
          const SizedBox(height: 20),
          for (final entry in {
            'Valor': price,
            'Compra': _date(warranty.dataCompra),
            'Garantia': '${warranty.duracaoMeses} meses',
            'Validade': _date(warranty.dataExpiracao),
            'Categoria': warrantyCategories[warranty.categoria] ?? warranty.categoria,
            'Notas': warranty.notas?.trim().isNotEmpty == true ? warranty.notas! : 'Sem notas',
          }.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entry.key, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 3), Text(entry.value),
              ]),
            ),
          if (warranty.fotoPath == null)
            const Text('Este registo não tem uma imagem de fatura associada.')
          else
            _LocalReceiptImage(relativePath: warranty.fotoPath!),
          const SizedBox(height: 20),
          Wrap(spacing: 12, runSpacing: 8, children: [
            Builder(builder: (anchor) => FilledButton.icon(
              onPressed: _busy ? null : () => _export(anchor, share: false),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Ver / imprimir PDF'),
            )),
            Builder(builder: (anchor) => OutlinedButton.icon(
              onPressed: _busy ? null : () => _export(anchor, share: true),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Partilhar PDF'),
            )),
          ]),
          if (_busy) ...[
            const SizedBox(height: 12), const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ],
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Fechar'),
          )),
          Center(child: TextButton.icon(
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline), label: const Text('Eliminar fatura'),
          )),
        ],
      ),
    );
  }

  static String _date(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _LocalReceiptImage extends StatefulWidget {
  const _LocalReceiptImage({required this.relativePath});
  final String relativePath;

  @override
  State<_LocalReceiptImage> createState() => _LocalReceiptImageState();
}

class _LocalReceiptImageState extends State<_LocalReceiptImage> {
  late final Future<File> _file = _load();

  Future<File> _load() async {
    final root = await getApplicationDocumentsDirectory();
    return File('${root.path}/${widget.relativePath}');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File>(
        future: _file,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Text('Imagem indisponível.');
          if (!snapshot.hasData) return const LinearProgressIndicator();
          return Image.file(snapshot.data!, height: 280, fit: BoxFit.contain,
            cacheWidth: 1000, semanticLabel: 'Fotografia do talão guardado',
            errorBuilder: (_, _, _) => const Text('Não foi possível abrir a imagem.'),
          );
        },
      );
}
