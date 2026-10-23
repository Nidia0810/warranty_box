import 'dart:async';

import 'package:flutter/material.dart';

import '../../paywall/application/billing_controller.dart';

/// O controller é partilhado pela aplicação e não é eliminado ao fechar a página.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({required this.billing, super.key});

  final BillingController billing;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.billing.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.billing.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _unlock(Future<bool> Function() operation) async {
    if (widget.billing.busy) return;
    final unlocked = await operation();
    if (!mounted || !unlocked) return;
    if (Navigator.canPop(context)) Navigator.pop(context, true);
  }

  void _continue() {
    if (widget.billing.canCreate && Navigator.canPop(context)) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.billing,
      builder: (context, _) {
        final billing = widget.billing;
        final colors = Theme.of(context).colorScheme;
        final price = billing.offer?.priceLabel;

        return PopScope(
          canPop: !billing.busy,
          child: Scaffold(
            appBar: AppBar(title: const Text('WarrantyBox')),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Header(),
                        const SizedBox(height: 24),
                        Card(
                          elevation: 0,
                          color: colors.surfaceContainerLow,
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(20),
                            child: Column(
                              children: [
                                _Benefit(
                                  icon: Icons.receipt_long_outlined,
                                  title: 'Faturas ilimitadas',
                                  description: 'Organize as suas compras num só lugar.',
                                ),
                                Divider(height: 24),
                                _Benefit(
                                  icon: Icons.event_available_outlined,
                                  title: 'Alertas de garantia',
                                  description: 'Avisos antes do fim da garantia.',
                                ),
                                Divider(height: 24),
                                _Benefit(
                                  icon: Icons.cloud_done_outlined,
                                  title: 'Backup privado',
                                  description: 'Cópias na sua nuvem pessoal.',
                                  comingSoon: true,
                                ),
                                Divider(height: 24),
                                _Benefit(
                                  icon: Icons.picture_as_pdf_outlined,
                                  title: 'Exportação em PDF',
                                  description: 'Relatórios das suas faturas.',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (billing.lifetime) ...[
                          const _AccessNotice(
                            icon: Icons.verified_outlined,
                            title: 'O seu acesso vitalício está ativo.',
                            description: 'Sem mensalidades ou renovações.',
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: billing.busy ? null : _continue,
                            child: const Text('Continuar'),
                          ),
                        ] else ...[
                          Text(
                            price == null ? '4,99 €' : price,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            price == null
                                ? 'Preço de referência em euros · pagamento único'
                                : 'Pagamento único · sem subscrições',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            price == null
                                ? 'Após o teste, pode optar pela compra vitalícia. '
                                    'O valor final será apresentado pela loja.'
                                : 'Após o teste, pode continuar por apenas $price, '
                                    'uma única vez.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          if (!billing.trialStarted)
                            FilledButton.icon(
                              onPressed: billing.canStartTrial
                                  ? () => _unlock(billing.startTrial)
                                  : null,
                              icon: const Icon(Icons.auto_awesome_outlined),
                              label: const Text('Teste Grátis de 7 Dias'),
                            ),
                          if (billing.trialActive) ...[
                            _AccessNotice(
                              icon: Icons.schedule_outlined,
                              title: 'Teste grátis ativo',
                              description: billing.trialDaysRemaining == 1
                                  ? 'Resta 1 dia de acesso.'
                                  : 'Restam ${billing.trialDaysRemaining} dias de acesso.',
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: billing.busy ? null : _continue,
                              child: const Text('Continuar a experimentar'),
                            ),
                          ],
                          if (billing.trialReady && billing.trialStarted &&
                              !billing.trialActive)
                            const _AccessNotice(
                              icon: Icons.history_outlined,
                              title: 'O seu teste terminou.',
                              description: 'As faturas guardadas continuam disponíveis. '
                                  'A compra vitalícia permite adicionar novas faturas.',
                            ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: billing.canPurchase
                                ? () => _unlock(billing.purchase)
                                : null,
                            icon: const Icon(Icons.shopping_bag_outlined),
                            label: Text(price == null
                                ? 'A carregar preço da loja'
                                : 'Comprar acesso vitalício · $price'),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'O teste é gratuito e não origina cobrança automática. '
                            'Só paga se decidir comprar o acesso vitalício.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: billing.storeReady && !billing.busy
                              ? () => _unlock(billing.restore)
                              : null,
                          child: const Text('Restaurar compras'),
                        ),
                        if (billing.loadingStore || billing.busy) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 8),
                          Text(
                            billing.busy
                                ? 'A concluir a operação…'
                                : 'A consultar a loja…',
                            textAlign: TextAlign.center,
                          ),
                        ],
                        for (final notice in [
                          billing.trialError,
                          billing.storeError,
                          billing.message,
                        ])
                          if (notice != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(notice, textAlign: TextAlign.center),
                              ),
                            ),
                        TextButton.icon(
                          onPressed: billing.busy || billing.loadingStore
                              ? null
                              : billing.refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Atualizar estado'),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Os talões e as fotografias ficam no dispositivo. '
                          'Compras e restauros necessitam de Internet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFFD1F267),
        borderRadius: BorderRadius.circular(28),
      ),
      child: const DefaultTextStyle(
        style: TextStyle(color: Color(0xFF20221D)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF20221D), size: 40),
            SizedBox(height: 20),
            Text(
              'Guarde todas as suas faturas. Para sempre.',
              style: TextStyle(fontSize: 34, height: 1.1,
                  fontWeight: FontWeight.w800, letterSpacing: -1),
            ),
            SizedBox(height: 14),
            Text('Mais organização. Menos preocupações.',
                style: TextStyle(fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.title,
      required this.description, this.comingSoon = false});

  final IconData icon;
  final String title;
  final String description;
  final bool comingSoon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(description),
              if (comingSoon) ...[
                const SizedBox(height: 4),
                Text('Em breve', style: TextStyle(fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AccessNotice extends StatelessWidget {
  const _AccessNotice({required this.icon, required this.title,
      required this.description});

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(description),
              ],
            )),
          ],
        ),
      ),
    );
  }
}
