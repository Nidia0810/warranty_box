import 'package:flutter/material.dart';

import '../../../core/services/notification_service.dart';
import '../../paywall/application/billing_controller.dart';
import '../../warranties/domain/repositories/warranty_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.billing, required this.notifications,
    required this.repository, super.key});
  final BillingController billing;
  final NotificationService notifications;
  final WarrantyRepository repository;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _scheduling = false;
  String? _notice;

  Future<void> _configureAlerts() async {
    if (_scheduling) return;
    setState(() { _scheduling = true; _notice = null; });
    try {
      final all = await widget.repository.findAll();
      final result = await widget.notifications.syncWarrantyAlerts(
        all, daysBefore: const [30, 7], requestPermission: true,
      );
      if (!mounted) return;
      setState(() => _notice = !result.permissionGranted
          ? 'Autorize as notificações nas definições do telemóvel para receber alertas.'
          : result.deferredCount > 0
              ? 'Próximos alertas atualizados. Os restantes serão repostos ao voltar a abrir a aplicação.'
              : 'Alertas futuros de 30 e 7 dias atualizados.');
    } catch (_) {
      if (mounted) setState(() => _notice = 'Não foi possível configurar os alertas. Tente novamente.');
    } finally {
      if (mounted) setState(() => _scheduling = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Definições e exportação')),
        body: ListenableBuilder(
          listenable: widget.billing,
          builder: (context, _) {
            final billing = widget.billing;
            return ListView(children: [
              const ListTile(
                leading: Icon(Icons.picture_as_pdf_outlined),
                title: Text('Exportação em PDF'),
                subtitle: Text('Abra uma garantia no Dashboard para ver, imprimir ou partilhar o PDF.'),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notificações locais'),
                subtitle: const Text('Autorizar e atualizar avisos a 30 e 7 dias da expiração.'),
                enabled: !_scheduling,
                onTap: _configureAlerts,
              ),
              if (_scheduling) const LinearProgressIndicator(),
              if (_notice != null)
                Padding(padding: const EdgeInsets.all(16),
                    child: Semantics(liveRegion: true, child: Text(_notice!))),
              const ListTile(title: Text('Backup privado: próxima fase.')),
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: const Text('Acesso vitalício'),
                subtitle: Text(billing.lifetime ? 'Ativo' : billing.trialActive
                    ? 'Teste ativo · ${billing.trialDaysRemaining} dias restantes'
                    : !billing.trialReady ? 'Não foi possível confirmar o teste local'
                    : billing.trialStarted ? 'Teste terminado' : 'Teste de 7 dias disponível'),
                onTap: () => Navigator.pushNamed(context, '/paywall'),
              ),
              ListTile(
                leading: const Icon(Icons.restore), title: const Text('Restaurar compras'),
                enabled: billing.storeReady && !billing.busy,
                onTap: () async { await billing.restore(); },
              ),
              if (billing.busy) const LinearProgressIndicator(),
              if (billing.message != null)
                Padding(padding: const EdgeInsets.all(16), child: Text(billing.message!)),
              const Padding(padding: EdgeInsets.all(16), child: Text(
                'Os registos guardados continuam disponíveis após terminar o teste.',
              )),
            ]);
          },
        ),
      );
}
