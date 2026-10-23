import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/pdf_service.dart';
import 'warranty_details_sheet.dart';

import '../../invoices/data/receipt_image_service.dart';
import '../screens/add_warranty_screen.dart';
import '../../paywall/application/billing_controller.dart';

import '../application/dashboard_controller.dart';
import '../domain/entities/warranty.dart';
import '../domain/repositories/warranty_repository.dart';

const _lime = Color(0xFFD1F267);
const _ink = Color(0xFF20221D);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({required this.repository, required this.billing,
    required this.notifications, required this.pdfService, this.recovery, super.key});
  final WarrantyRepository repository;
  final BillingController billing;
  final NotificationService notifications;
  final PdfService pdfService;
  final CaptureRecovery? recovery;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  late final DashboardController _controller;
  final _searchController = TextEditingController();
  bool _deleting = false;
  bool _openingInvoice = false;

  @override
  void initState() {
    super.initState();
    _controller = DashboardController(repository: widget.repository);
    _refreshDashboard();
    WidgetsBinding.instance.addObserver(this);
    if (widget.recovery?.hasData == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openInvoice(recovery: widget.recovery);
      });
    }
  }

  Future<void> _openInvoice({CaptureRecovery? recovery}) async {
    if (_openingInvoice) return;
    _openingInvoice = true;
    try {
      await widget.billing.refreshTrial();
      if (!mounted) return;
      if (recovery == null && !widget.billing.canCreate) {
        await Navigator.pushNamed<bool>(context, '/paywall');
        if (!mounted || !widget.billing.canCreate) return;
      }
      final Warranty? warranty = recovery == null
          ? await Navigator.pushNamed<Warranty>(context, '/invoice')
          : await Navigator.push<Warranty>(context, MaterialPageRoute<Warranty>(
              builder: (_) => AddWarrantyScreen(repository: widget.repository,
                  billing: widget.billing, notifications: widget.notifications, recovery: recovery),
            ));
      if (!mounted || warranty == null) return;
      _searchController.clear();
      _controller.clearFilters();
      await _controller.load();
    } finally {
      _openingInvoice = false;
    }
  }

  Future<void> _refreshDashboard() async {
    await _controller.load();
    if (!mounted || _controller.error != null || _controller.loading) return;
    try {
      await widget.notifications.syncWarrantyAlerts(_controller.warranties);
    } catch (_) {
      // A leitura do catálogo permanece disponível se os alertas falharem.
      // Definições permite pedir permissão e tentar novamente explicitamente.
    }
  }

  Future<bool> _deleteWarranty(Warranty warranty) async {
    if (_deleting) return false;
    _deleting = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Eliminar fatura?'),
          content: Text('Eliminar “${warranty.titulo}” e a fotografia local associada?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
          ],
        ),
      );
      if (confirmed != true) return false;
      await widget.repository.delete(warranty.id);
      var alertsCancelled = true;
      try {
        await widget.notifications.cancelWarrantyAlerts(warranty.id);
      } catch (_) {
        alertsCancelled = false;
      }
      var imageRemoved = true;
      if (warranty.fotoPath != null) {
        try {
          await ReceiptImageService().removeOwned(warranty.fotoPath!);
        } catch (_) {
          // O registo já foi apagado. Nunca tentar repô-lo com uma foto incerta.
          imageRemoved = false;
        }
      }
      if (!mounted) return true;
      await _refreshDashboard();
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          !alertsCancelled ? 'Registo eliminado. Não foi possível cancelar os alertas; '
              'tente atualizar as notificações em Definições.'
          : imageRemoved ? 'Fatura eliminada do dispositivo.'
          : 'Registo eliminado. Não foi possível remover a fotografia local.')));
      return true;
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Não foi possível eliminar a fatura. Tenta novamente.'),
      ));
      return false;
    } finally {
      _deleting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshDashboard();
      widget.billing.refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF131510) : const Color(0xFFF3F4F1),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final items = _controller.visibleWarranties;
                return CustomScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('WarrantyBox', style: TextStyle(
                                        fontSize: 23, fontWeight: FontWeight.w800,
                                        letterSpacing: -0.8,
                                      )),
                                      SizedBox(height: 4),
                                      Text('Um lugar para todas as tuas faturas.'),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                IconButton.filledTonal(
                                  tooltip: 'Ver garantias a expirar',
                                  onPressed: () => _controller.selectFilter(
                                    DashboardFilter.aExpirar,
                                  ),
                                  icon: Badge(
                                    isLabelVisible: _controller.count(
                                      WarrantyStatus.aExpirar,
                                    ) > 0,
                                    child: const Icon(Icons.notifications_none_rounded),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _Overview(controller: _controller),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Icon(Icons.lock_outline_rounded, size: 14,
                                    color: colors.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Expanded(child: Text(
                                  'Faturas guardadas neste dispositivo · sem servidores',
                                  style: TextStyle(fontSize: 11,
                                      color: colors.onSurfaceVariant),
                                )),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Row(
                              children: [
                                const Expanded(child: Text('As tuas faturas',
                                    style: TextStyle(fontSize: 21,
                                        fontWeight: FontWeight.w700))),
                                Text('${items.length} resultados', style: TextStyle(
                                    fontSize: 12, color: colors.onSurfaceVariant)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _searchController,
                              onChanged: _controller.search,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: 'Pesquisar produto ou loja',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: IconButton(
                                  tooltip: 'Limpar pesquisa',
                                  onPressed: () {
                                    _searchController.clear();
                                    _controller.search('');
                                  },
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                ),
                                filled: true,
                                fillColor: colors.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: [
                                for (final entry in const {
                                  DashboardFilter.todas: 'Todas',
                                  DashboardFilter.ativas: 'Ativas',
                                  DashboardFilter.aExpirar: 'A expirar',
                                  DashboardFilter.expiradas: 'Expiradas',
                                }.entries)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(entry.value),
                                      selected: _controller.filter == entry.key,
                                      selectedColor: _lime,
                                      labelStyle: TextStyle(
                                        color: _controller.filter == entry.key
                                            ? _ink : colors.onSurface,
                                      ),
                                      showCheckmark: false,
                                      onSelected: (_) => _controller.selectFilter(entry.key),
                                    ),
                                  ),
                              ]),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              key: ValueKey(_controller.category),
                              initialValue: _controller.category ?? 'all',
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Categoria',
                                prefixIcon: Icon(Icons.tune_rounded, size: 20),
                                border: UnderlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(value: 'all',
                                    child: Text('Todas as categorias')),
                                for (final entry in warrantyCategories.entries)
                                  DropdownMenuItem(value: entry.key,
                                      child: Text(entry.value)),
                              ],
                              onChanged: (value) => _controller.selectCategory(
                                value == 'all' ? null : value,
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                    if (_controller.loading)
                      const SliverToBoxAdapter(child: Padding(
                        padding: EdgeInsets.all(24), child: LinearProgressIndicator(),
                      )),
                    if (_controller.error != null)
                      SliverToBoxAdapter(child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(children: [
                          Text(_controller.error!, textAlign: TextAlign.center),
                          TextButton(onPressed: _refreshDashboard,
                              child: const Text('Tentar novamente')),
                        ]),
                      )),
                    if (items.isEmpty && !_controller.loading && _controller.error == null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(children: [
                            Icon(Icons.search_off_rounded, size: 40,
                                color: colors.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text(_controller.total == 0 ? 'Ainda não tens faturas guardadas.' : 'Nenhuma fatura encontrada.',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text(_controller.total == 0 ? 'Toca em Nova fatura para guardar a primeira.' : 'Experimenta outra pesquisa ou altera os filtros.',
                                textAlign: TextAlign.center),
                            TextButton(
                              onPressed: () {
                                _searchController.clear();
                                _controller.clearFilters();
                              },
                              child: const Text('Limpar filtros'),
                            ),
                          ]),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        sliver: SliverList.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _WarrantyCard(
                              warranty: items[index], now: _controller.now,
                              onDelete: _deleteWarranty,
                              pdfService: widget.pdfService,
                            ),
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _lime,
        foregroundColor: _ink,
        onPressed: () => _openInvoice(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nova fatura'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        indicatorColor: _lime,
        onDestinationSelected: (index) {
          if (index == 1) Navigator.pushNamed(context, '/settings');
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded, color: _ink), label: 'Garantias',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined), label: 'Definições',
          ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.controller});
  final DashboardController controller;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: _lime,
            borderRadius: BorderRadius.circular(28)),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: _ink),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.verified_user_outlined, color: _ink, size: 18),
              SizedBox(width: 8),
              Text('TUDO SOB CONTROLO', style: TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            ]),
            const SizedBox(height: 20),
            const Text('Compras de hoje.\nProteção para amanhã.', style: TextStyle(
                fontSize: 29, fontWeight: FontWeight.w800, letterSpacing: -1,
                height: 1.15)),
            const SizedBox(height: 12),
            Text('${controller.total} faturas, organizadas num só lugar.'),
            const Padding(padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: Color(0x4420221D))),
            Wrap(spacing: 28, runSpacing: 16, children: [
              for (final entry in const {
                WarrantyStatus.ativa: 'Ativas',
                WarrantyStatus.aExpirar: 'A expirar',
                WarrantyStatus.expirada: 'Expiradas',
              }.entries)
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${controller.count(entry.key)}', style: const TextStyle(
                      fontSize: 27, fontWeight: FontWeight.w800)),
                  Text(entry.value, style: const TextStyle(fontSize: 12)),
                ]),
            ]),
          ]),
        ),
      );
}

class _WarrantyCard extends StatelessWidget {
  const _WarrantyCard({required this.warranty, required this.now,
    required this.onDelete, required this.pdfService});
  final Warranty warranty;
  final DateTime now;
  final Future<bool> Function(Warranty) onDelete;
  final PdfService pdfService;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = warranty.statusEm(now);
    final days = warranty.diasRestantesEm(now);
    final (Color badgeColor, Color textColor, String label) = switch (status) {
      WarrantyStatus.ativa => (_lime, _ink, '$days dias restantes'),
      WarrantyStatus.aExpirar => (const Color(0xFFFFE6AD), const Color(0xFF654300),
          days == 0 ? 'Termina hoje' : days == 1 ? 'Termina amanhã' : '$days dias restantes'),
      WarrantyStatus.expirada => (const Color(0xFFFFDEDA), const Color(0xFF892D24),
          days == -1 ? 'Expirou há 1 dia' : 'Expirou há ${days.abs()} dias'),
    };
    final icon = switch (warranty.categoria) {
      'eletronica' => Icons.devices_other_rounded,
      'eletrodomesticos' => Icons.kitchen_outlined,
      'vestuario' => Icons.checkroom_rounded,
      _ => Icons.home_outlined,
    };
    return Card(
      color: colors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(15)),
                child: Icon(icon, size: 25),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(warranty.titulo, style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${warranty.loja} · ${_date(warranty.dataCompra)}',
                    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
              ])),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
                children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: badgeColor,
                    borderRadius: BorderRadius.circular(9)),
                child: Text(label, style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700, color: textColor)),
              ),
              Text(_price(warranty), style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _remainingFraction(),
                minHeight: 4,
                color: status == WarrantyStatus.expirada
                    ? colors.outline : status == WarrantyStatus.aExpirar
                        ? const Color(0xFFD19A25) : const Color(0xFF7B9E27),
                backgroundColor: colors.surfaceContainerHighest,
                semanticsLabel: 'Proporção do período de garantia restante',
              ),
            ),
            const SizedBox(height: 8),
            Text('Válida até ${_date(warranty.dataExpiracao)}',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }

  double _remainingFraction() {
    final purchase = warranty.dataCompra;
    final expiry = warranty.dataExpiracao;
    final total = DateTime.utc(expiry.year, expiry.month, expiry.day)
        .difference(DateTime.utc(purchase.year, purchase.month, purchase.day)).inDays;
    return total <= 0 ? 0 : (warranty.diasRestantesEm(now) / total).clamp(0.0, 1.0).toDouble();
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => WarrantyDetailsSheet(
        warranty: warranty,
        pdfService: pdfService,
        onDelete: onDelete,
      ),
    );
  }
  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  static String _price(Warranty warranty) => NumberFormat.currency(
      locale: 'pt_PT', name: warranty.moeda,
      symbol: warranty.moeda == 'EUR' ? '€' : warranty.moeda,
  ).format(warranty.preco / 100);
}


