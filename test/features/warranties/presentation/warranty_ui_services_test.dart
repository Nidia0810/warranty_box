import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:warranty_box/core/services/notification_service.dart';
import 'package:warranty_box/core/services/pdf_service.dart';
import 'package:warranty_box/features/invoices/data/receipt_image_service.dart';
import 'package:warranty_box/features/invoices/data/receipt_ocr_service.dart';
import 'package:warranty_box/features/invoices/data/receipt_parser.dart';
import 'package:warranty_box/features/invoices/domain/receipt_reading.dart';
import 'package:warranty_box/features/paywall/application/billing_controller.dart';
import 'package:warranty_box/features/paywall/domain/billing_gateway.dart';
import 'package:warranty_box/features/paywall/domain/trial_record.dart';
import 'package:warranty_box/features/warranties/domain/entities/warranty.dart';
import 'package:warranty_box/features/warranties/domain/repositories/warranty_repository.dart';
import 'package:warranty_box/features/warranties/presentation/warranty_details_sheet.dart';
import 'package:warranty_box/features/warranties/screens/add_warranty_screen.dart';

void main() {
  Warranty sample() => Warranty(id: 'local-1', titulo: 'Portátil', loja: 'Loja',
      preco: 49999, dataCompra: DateTime(2026, 1, 1), duracaoMeses: 36,
      categoria: 'eletronica');

  testWidgets('OCR mostra progresso, preenche campos e permite corrigir e repetir', (tester) async {
    final billing = BillingController(gateway: _Gateway(), trialStore: _Trial());
    final ocr = _Ocr();
    addTearDown(billing.dispose);
    await tester.pumpWidget(MaterialApp(home: AddWarrantyScreen(
      repository: _Repository(), billing: billing, notifications: _Notifications('ok'),
      imageService: _Images(), ocrService: ocr,
    )));
    await tester.tap(find.text('Tirar fotografia'));
    await tester.pump();
    await tester.pump();
    expect(find.text('A analisar o talão com IA...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(ocr.calls, 1);
    expect(tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Tirar fotografia'),
    ).onPressed, isNull);
    ocr.result.complete(const ReceiptParser().parse(
      'LOJA CENTRAL\nData de compra: 20/10/2025\nTOTAL 24,99 €',
    ));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    expect(tester.widget<TextFormField>(fields.at(1)).controller!.text, 'LOJA CENTRAL');
    expect(tester.widget<TextFormField>(fields.at(2)).controller!.text, '24,99');
    expect(find.text('Compra: 20/10/2025'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Análise concluída em'), findsOneWidget);
    await tester.ensureVisible(fields.at(2));
    await tester.enterText(fields.at(2), '29,99');
    expect(tester.widget<TextFormField>(fields.at(2)).controller!.text, '29,99');

    // Uma repetição sem texto não destrói a correção manual.
    ocr.result = Completer<ReceiptReading>();
    final repeat = find.text('Repetir leitura OCR');
    await tester.ensureVisible(repeat);
    await tester.tap(repeat);
    await tester.pump();
    await tester.pump();
    ocr.result.complete(const ReceiptReading(text: ''));
    await tester.pumpAndSettle();
    expect(ocr.calls, 2);
    expect(tester.widget<TextFormField>(fields.at(2)).controller!.text, '29,99');
    expect(find.textContaining('Não foi encontrado texto.'), findsOneWidget);
  });

  testWidgets('Cancelar a câmara preserva os campos e não inicia OCR', (tester) async {
    final billing = BillingController(gateway: _Gateway(), trialStore: _Trial());
    final ocr = _Ocr();
    addTearDown(billing.dispose);
    await tester.pumpWidget(MaterialApp(home: AddWarrantyScreen(
      repository: _Repository(), billing: billing, notifications: _Notifications('ok'),
      imageService: _Images()..selected = null, ocrService: ocr,
    )));
    final store = find.byType(TextFormField).at(1);
    await tester.ensureVisible(store);
    await tester.enterText(store, 'Loja manual');
    final camera = find.text('Tirar fotografia');
    await tester.ensureVisible(camera);
    await tester.tap(camera);
    await tester.pumpAndSettle();
    expect(ocr.calls, 0);
    expect(tester.widget<TextFormField>(store).controller!.text, 'Loja manual');
  });

  testWidgets('Os botões de detalhes invocam preview e partilha do serviço PDF', (tester) async {
    final pdf = _Pdf();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WarrantyDetailsSheet(
      warranty: sample(), pdfService: pdf, onDelete: (_) async => false,
    ))));
    final preview = find.text('Ver / imprimir PDF');
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    final share = find.text('Partilhar PDF');
    await tester.ensureVisible(share);
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(pdf.previews, 1);
    expect(pdf.shares, 1);
    expect(pdf.shareBounds, isNotNull);
  });

  testWidgets('Erro de PDF fica visível e permite tentar outra vez', (tester) async {
    final pdf = _Pdf()..fail = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WarrantyDetailsSheet(
      warranty: sample(), pdfService: pdf, onDelete: (_) async => false,
    ))));
    final share = find.text('Partilhar PDF');
    await tester.ensureVisible(share);
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(find.text('Fotografia indisponível para exportar.'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Partilhar PDF'),
    ).onPressed, isNotNull);
  });

  for (final mode in ['ok', 'denied', 'failure', 'databaseFailure']) {
    testWidgets('Guardar fatura e configurar alertas: $mode', (tester) async {
      final repo = _Repository()..failSave = mode == 'databaseFailure';
      final alerts = _Notifications(mode);
      final billing = BillingController(gateway: _Gateway(), trialStore: _Trial());
      await billing.initialize();
      addTearDown(billing.dispose);
      Warranty? returned;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            returned = await Navigator.push<Warranty>(context, MaterialPageRoute(
              builder: (_) => AddWarrantyScreen(repository: repo,
                  billing: billing, notifications: alerts),
            ));
          },
          child: const Text('Abrir formulário'),
        ),
      ))));
      await tester.tap(find.text('Abrir formulário'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Máquina de café');
      await tester.enterText(fields.at(1), 'Loja');
      await tester.enterText(fields.at(2), '149,99');
      final date = find.text('Selecionar data de compra');
      await tester.ensureVisible(date);
      await tester.tap(date);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      final save = find.text('Guardar fatura');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      if (mode == 'databaseFailure') {
        expect(repo.items, isEmpty);
        expect(alerts.calls, 0);
        expect(returned, isNull);
        expect(find.textContaining('Não foi possível guardar a fatura.'), findsOneWidget);
      } else {
        expect(repo.items.single.titulo, 'Máquina de café');
        expect(returned?.id, repo.items.single.id);
        expect(alerts.calls, 1);
        expect(alerts.lastDays, [30, 7]);
        expect(alerts.requestedPermission, isTrue);
        if (mode == 'failure') {
          expect(find.textContaining('Não foi possível agendar os alertas.'), findsOneWidget);
        } else if (mode == 'denied') {
          expect(find.textContaining('autorize as notificações'), findsOneWidget);
        }
      }
    });
  }
}

class _Pdf extends PdfService {
  int previews = 0;
  int shares = 0;
  bool fail = false;
  Rect? shareBounds;
  @override
  Future<void> preview(BuildContext context, Warranty warranty) async { previews++; }
  @override
  Future<bool> shareWarranty(Warranty warranty, {Rect? bounds}) async {
    shares++;
    shareBounds = bounds;
    if (fail) throw const PdfExportException('Fotografia indisponível para exportar.');
    return true;
  }
}

class _Images extends ReceiptImageService {
  String? selected = '/fake/receipt.jpg';
  @override
  Future<String?> pick(ImageSource source) async => selected;
}

class _Ocr extends ReceiptOcrService {
  int calls = 0;
  Completer<ReceiptReading> result = Completer<ReceiptReading>();
  @override
  Future<ReceiptReading> recognize(String imagePath) {
    calls++;
    return result.future;
  }
}

class _Notifications extends NotificationService {
  _Notifications(this.mode);
  final String mode;
  int calls = 0;
  List<int>? lastDays;
  bool requestedPermission = false;
  @override
  Future<AlertScheduleResult> syncWarrantyAlerts(List<Warranty> warranties, {
    List<int> daysBefore = const [30, 7], int hour = 9, int minute = 0,
    bool requestPermission = false, bool showProductName = false,
  }) async {
    calls++;
    lastDays = List.of(daysBefore);
    requestedPermission = requestPermission;
    if (mode == 'failure') throw StateError('Falha nativa simulada');
    return AlertScheduleResult(permissionGranted: mode != 'denied', scheduledIds: [1, 2]);
  }
}

class _Repository implements WarrantyRepository {
  final items = <Warranty>[];
  bool failSave = false;
  @override
  Future<List<Warranty>> findAll() async => List.of(items);
  @override
  Future<Warranty?> findById(String id) async => items.where((item) => item.id == id).firstOrNull;
  @override
  Future<void> save(Warranty warranty) async {
    if (failSave) throw StateError('Falha de disco simulada');
    items.add(warranty);
  }
  @override
  Future<void> delete(String id) async { items.removeWhere((item) => item.id == id); }
}

class _Trial implements TrialStore {
  final now = DateTime.now().toUtc();
  @override
  Future<TrialRecord?> read() async => TrialRecord(startedAt: now, lastSeenAt: now);
  @override
  Future<void> write(TrialRecord record) async {}
}

class _Gateway implements BillingGateway {
  @override
  Stream<bool> get accessChanges => const Stream<bool>.empty();
  @override
  Future<void> configure() async {}
  @override
  Future<bool> hasLifetime() async => false;
  @override
  Future<LifetimeOffer?> loadOffer() async => null;
  @override
  Future<bool> purchaseLifetime() async => false;
  @override
  Future<bool> restore() async => false;
  @override
  void dispose() {}
}
