import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_box/core/services/pdf_service.dart';
import 'package:warranty_box/features/warranties/domain/entities/warranty.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Warranty sample({String? photo, String id = 'local-1'}) => Warranty(
    id: id, titulo: 'Máquina de café', loja: "Loja d'Exemplo", preco: 14999,
    dataCompra: DateTime(2026, 1, 31), duracaoMeses: 24, categoria: 'casa',
    fotoPath: photo, notas: 'Conservar o comprovativo original.',
  );

  test('Gera bytes PDF locais com caracteres portugueses e sem fotografia', () async {
    final service = PdfService(clock: () => DateTime(2026, 10, 22));
    final bytes = await service.generateWarrantyPdf(sample());
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('Não exporta silenciosamente se a fotografia associada desapareceu', () async {
    final directory = await Directory.systemTemp.createTemp('warranty_pdf_test_');
    try {
      final service = PdfService(documentsDirectory: () async => directory);
      await expectLater(service.generateWarrantyPdf(sample(photo: 'invoices/missing.jpg')),
          throwsA(isA<PdfExportException>()));
    } finally {
      await directory.delete(); // Pasta vazia criada pelo teste, sem recursão.
    }
  });

  test('Rejeita referências que escapam à pasta privada de faturas', () async {
    await expectLater(PdfService().generateWarrantyPdf(sample(photo: 'invoices/../secret.jpg')),
        throwsA(isA<PdfExportException>()));
  });

  test('O nome do ficheiro não admite separadores de caminhos', () {
    final name = PdfService.fileName(sample(id: '../invalid/id'));
    expect(name, isNot(contains('/')));
    expect(name, isNot(contains('\\')));
    expect(name, endsWith('.pdf'));
  });
}
