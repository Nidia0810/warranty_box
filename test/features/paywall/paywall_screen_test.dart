import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_box/features/paywall/application/billing_controller.dart';
import 'package:warranty_box/features/paywall/domain/billing_gateway.dart';
import 'package:warranty_box/features/paywall/domain/trial_record.dart';
import 'package:warranty_box/features/warranties/screens/paywall_screen.dart';

void main() {
  late BillingController billing;

  tearDown(() => billing.dispose());

  Future<void> showPaywall(WidgetTester tester, _Gateway gateway) async {
    billing = BillingController(
      gateway: gateway,
      trialStore: _MemoryTrialStore(),
      clock: () => DateTime.utc(2026, 10, 22, 12),
    );
    await billing.initialize();
    await tester.pumpWidget(MaterialApp(home: PaywallScreen(billing: billing)));
    await tester.pumpAndSettle();
  }

  testWidgets('Mostra benefícios e usa o preço localizado da loja', (tester) async {
    await showPaywall(tester, _Gateway());
    expect(find.text('Guarde todas as suas faturas. Para sempre.'), findsOneWidget);
    for (final text in [
      'Faturas ilimitadas', 'Alertas de garantia',
      'Backup privado', 'Exportação em PDF',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('Em breve'), findsOneWidget);
    expect(find.text(r'US$ 6.49'), findsOneWidget);
    expect(find.text('4,99 €'), findsNothing);
    expect(find.textContaining('cobrança automática'), findsOneWidget);
  });

  testWidgets('Ativar o teste não inicia uma compra', (tester) async {
    final gateway = _Gateway();
    await showPaywall(tester, gateway);
    final trialButton = find.text('Teste Grátis de 7 Dias');
    await tester.ensureVisible(trialButton);
    await tester.tap(trialButton);
    await tester.pumpAndSettle();
    expect(billing.trialActive, isTrue);
    expect(gateway.purchaseCalls, 0);
    expect(find.text('Continuar a experimentar'), findsOneWidget);
  });

  testWidgets('Sem produto, indica referência e impede comprar', (tester) async {
    await showPaywall(tester, _Gateway(offer: null));
    expect(find.text('4,99 €'), findsOneWidget);
    expect(find.text('Preço de referência em euros · pagamento único'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'A carregar preço da loja'),
    );
    expect(button.onPressed, isNull);
  });
}

class _MemoryTrialStore implements TrialStore {
  TrialRecord? record;

  @override
  Future<TrialRecord?> read() async => record;

  @override
  Future<void> write(TrialRecord value) async { record = value; }
}

class _Gateway implements BillingGateway {
  _Gateway({this.offer = const LifetimeOffer(
    productId: 'warrantybox_lifetime', priceLabel: r'US$ 6.49',
  )});

  final LifetimeOffer? offer;
  int purchaseCalls = 0;

  @override
  Stream<bool> get accessChanges => const Stream<bool>.empty();

  @override
  Future<void> configure() async {}

  @override
  Future<bool> hasLifetime() async => false;

  @override
  Future<LifetimeOffer?> loadOffer() async => offer;

  @override
  Future<bool> purchaseLifetime() async { purchaseCalls++; return true; }

  @override
  Future<bool> restore() async => false;

  @override
  void dispose() {}
}
