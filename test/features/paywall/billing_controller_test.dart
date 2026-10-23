import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_box/features/paywall/application/billing_controller.dart';
import 'package:warranty_box/features/paywall/domain/billing_gateway.dart';
import 'package:warranty_box/features/paywall/domain/trial_record.dart';

void main() {
  late DateTime now;
  late _Gateway gateway;
  late _TrialStore storage;
  late BillingController billing;

  setUp(() async {
    now = DateTime.utc(2026, 10, 22, 12);
    gateway = _Gateway();
    storage = _TrialStore();
    billing = BillingController(gateway: gateway, trialStore: storage, clock: () => now);
    await billing.initialize();
  });
  tearDown(() => billing.dispose());

  test('Não inicia o teste ao abrir; ativação explícita dura exatamente 7 dias', () async {
    expect(billing.canCreate, isFalse);
    expect(storage.record, isNull);
    expect(await billing.startTrial(), isTrue);
    expect(storage.record!.startedAt, now);
    now = now.add(const Duration(days: 7)).subtract(const Duration(microseconds: 1));
    expect(billing.trialActive, isTrue);
    expect(billing.trialDaysRemaining, 1);
    now = now.add(const Duration(microseconds: 1));
    expect(billing.canCreate, isFalse);
    expect(await billing.startTrial(), isFalse);
  });

  test('Uma nova instância reutiliza o início persistido e não reinicia o teste', () async {
    await billing.startTrial();
    final initial = storage.record!.startedAt;
    now = now.add(const Duration(days: 4));
    final other = BillingController(gateway: _Gateway(), trialStore: storage, clock: () => now);
    await other.initialize();
    expect(other.trialDaysRemaining, 3);
    expect(await other.startTrial(), isFalse);
    expect(storage.record!.startedAt, initial);
    other.dispose();
  });

  test('Falha ao persistir o início não concede teste grátis', () async {
    storage.failWrite = true;
    expect(await billing.startTrial(), isFalse);
    expect(billing.canCreate, isFalse);
    expect(billing.trialError, isNotNull);
  });

  test('Um checkpoint impede recuar para antes do último instante observado', () async {
    await billing.startTrial();
    now = now.add(const Duration(days: 8));
    await billing.refreshTrial();
    now = now.subtract(const Duration(days: 4));
    expect(billing.canCreate, isFalse);
  });

  test('Compra confirmada ativa o acesso sem depender do trial', () async {
    expect(await billing.purchase(), isTrue);
    expect(billing.lifetime, isTrue);
    expect(billing.canPurchase, isFalse);
    expect(billing.trialStarted, isFalse);
  });

  test('Toques repetidos não iniciam duas compras concorrentes', () async {
    final first = billing.purchase();
    expect(await billing.purchase(), isFalse);
    expect(await first, isTrue);
    expect(gateway.purchaseCalls, 1);
  });

  test('Cancelamento e pagamento pendente não concedem novo acesso', () async {
    gateway.purchaseError = const BillingFailure('Cancelado', cancelled: true);
    expect(await billing.purchase(), isFalse);
    expect(billing.canCreate, isFalse);
    gateway.purchaseError = const BillingFailure('Pendente', pending: true);
    expect(await billing.purchase(), isFalse);
    expect(billing.canCreate, isFalse);
    gateway.events.add(true);
    await Future<void>.delayed(Duration.zero);
    expect(billing.canCreate, isTrue);
  });

  test('Restauro vazio não desbloqueia e restauro válido desbloqueia', () async {
    expect(await billing.restore(), isFalse);
    gateway.paid = true;
    expect(await billing.restore(), isTrue);
    expect(billing.lifetime, isTrue);
  });

  test('Erro de rede mantém acesso conhecido; revogação confirmada remove-o', () async {
    await billing.purchase();
    gateway.infoError = const BillingFailure('Sem rede');
    await billing.refreshStore();
    expect(billing.lifetime, isTrue);
    gateway.infoError = null;
    gateway.paid = false;
    await billing.refreshStore();
    expect(billing.lifetime, isFalse);
  });

  test('Trial local funciona sem configuração da loja', () async {
    final offline = BillingController(gateway: _Gateway()..configError = true,
        trialStore: _TrialStore(), clock: () => now);
    await offline.initialize();
    expect(offline.canPurchase, isFalse);
    expect(offline.storeError, isNotNull);
    expect(await offline.startTrial(), isTrue);
    offline.dispose();
  });
}

class _TrialStore implements TrialStore {
  TrialRecord? record;
  bool failWrite = false;
  @override
  Future<TrialRecord?> read() async => record;
  @override
  Future<void> write(TrialRecord value) async {
    if (failWrite) throw StateError('Armazenamento indisponível');
    record = value;
  }
}

class _Gateway implements BillingGateway {
  final events = StreamController<bool>.broadcast();
  bool paid = false;
  bool configError = false;
  int purchaseCalls = 0;
  BillingFailure? purchaseError;
  BillingFailure? infoError;
  @override
  Stream<bool> get accessChanges => events.stream;
  @override
  Future<void> configure() async {
    if (configError) throw const BillingFailure('Sem configuração');
  }
  @override
  Future<bool> hasLifetime() async {
    if (infoError != null) throw infoError!;
    return paid;
  }
  @override
  Future<LifetimeOffer?> loadOffer() async => const LifetimeOffer(
      productId: 'warrantybox_lifetime', priceLabel: '4,99 €');
  @override
  Future<bool> purchaseLifetime() async {
    purchaseCalls++;
    if (purchaseError != null) throw purchaseError!;
    paid = true;
    return paid;
  }
  @override
  Future<bool> restore() async => paid;
  @override
  void dispose() { unawaited(events.close()); }
}
