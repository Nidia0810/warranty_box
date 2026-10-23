import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../core/services/notification_service.dart';

import '../application/dashboard_controller.dart';
import '../domain/entities/warranty.dart';
import '../domain/repositories/warranty_repository.dart';
import '../../paywall/application/billing_controller.dart';
import '../../invoices/data/receipt_image_service.dart';
import '../../invoices/data/receipt_ocr_service.dart';
import '../../invoices/data/receipt_parser.dart';

class AddWarrantyScreen extends StatefulWidget {
  const AddWarrantyScreen({required this.repository, required this.billing,
    required this.notifications, this.recovery, this.imageService,
    this.ocrService, super.key});
  final WarrantyRepository repository;
  final BillingController billing;
  final NotificationService notifications;
  final CaptureRecovery? recovery;
  final ReceiptImageService? imageService;
  final ReceiptOcrService? ocrService;

  @override
  State<AddWarrantyScreen> createState() => _AddWarrantyScreenState();
}

class _AddWarrantyScreenState extends State<AddWarrantyScreen> {
  late final _images = widget.imageService ?? ReceiptImageService();
  late final _ocr = widget.ocrService ?? ReceiptOcrService();
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _store = TextEditingController();
  final _price = TextEditingController();
  final _months = TextEditingController(text: '36');
  final _notes = TextEditingController();
  DateTime? _date;
  String _category = 'eletronica';
  String? _imagePath;
  String? _error;
  String _text = '';
  String _phase = '';
  bool _busy = false;
  bool _analyzing = false;
  Duration? _analysisTime;

  @override
  void initState() {
    super.initState();
    _error = widget.recovery?.error;
    if (widget.recovery?.path != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scan(path: widget.recovery!.path);
      });
    }
  }

  @override
  void dispose() {
    // Serviços injetados pertencem ao chamador; o motor próprio pertence ao ecrã.
    if (widget.ocrService == null) unawaited(_closeOcr());
    for (final field in [_title, _store, _price, _months, _notes]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _closeOcr() async {
    try {
      await _ocr.close();
    } catch (_) {
      // A saída do ecrã não depende do sucesso da limpeza nativa.
    }
  }

  Future<void> _scan({ImageSource? source, String? path}) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _phase = source == null ? 'A analisar o talão com IA...' : 'A abrir a imagem…';
    });
    try {
      final selected = path ?? await _images.pick(source!);
      if (!mounted || selected == null) return;
      setState(() {
        if (selected != _imagePath) {
          // Uma fotografia diferente corresponde a outro talão.
          _store.clear();
          _price.clear();
          _date = null;
        }
        _imagePath = selected;
        _text = '';
        _analyzing = true;
        _analysisTime = null;
        _phase = 'A analisar o talão com IA...';
      });
      // Pintar o indicador antes de iniciar a chamada ao motor nativo.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final timer = Stopwatch()..start();
      final reading = await _ocr.recognize(selected);
      timer.stop();
      if (!mounted) return;
      setState(() {
        _analysisTime = timer.elapsed;
        _text = reading.text;
        // Falhas e campos não reconhecidos não apagam correções manuais.
        if (reading.store != null) _store.text = reading.store!;
        final cents = reading.totalCents;
        if (cents != null) {
          _price.text = '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';
        }
        if (reading.date != null) _date = reading.date;
        if (_text.trim().isEmpty) {
          _error = 'Não foi encontrado texto. Fotografa o talão completo, com boa luz e sem reflexos, ou preenche os campos manualmente.';
        }
      });
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = _platformMessage(error.code));
    } on FileSystemException {
      if (mounted) setState(() => _error = 'Não foi possível abrir a imagem. Seleciona-a novamente.');
    } on UnsupportedError {
      if (mounted) setState(() => _error = 'A câmara e o OCR requerem um dispositivo Android ou iOS.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível ler este talão. Tenta outra fotografia ou preenche os campos manualmente.');
    } finally {
      if (mounted) setState(() { _busy = false; _analyzing = false; });
    }
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final last = DateTime(now.year, now.month, now.day);
    final initial = _date == null || _date!.isAfter(last) ? last : _date!;
    final date = await showDatePicker(
      context: context, initialDate: initial, firstDate: DateTime(1900), lastDate: last,
      helpText: 'Data de compra', cancelText: 'Cancelar', confirmText: 'Confirmar',
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  Future<void> _confirm() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_date == null) {
      setState(() => _error = 'Seleciona a data de compra.');
      return;
    }
    final now = DateTime.now();
    if (_date!.isAfter(DateTime(now.year, now.month, now.day))) {
      setState(() => _error = 'Confirma a data: a compra não pode ser futura.');
      return;
    }
    // O teste pode terminar com o formulário aberto. Validar antes da cópia.
    setState(() { _busy = true; _phase = 'A verificar o acesso…'; _error = null; });
    await widget.billing.refreshTrial();
    if (!mounted) return;
    if (!widget.billing.canCreate) {
      setState(() => _busy = false);
      await Navigator.pushNamed<bool>(context, '/paywall');
      if (!mounted || !widget.billing.canCreate) return;
    }
    setState(() { _busy = true; _phase = 'A guardar a fatura no dispositivo…'; });
    String? copiedImage;
    late final Warranty warranty;
    try {
      copiedImage = _imagePath == null ? null : await _images.keep(_imagePath!);
      warranty = Warranty(
        id: const Uuid().v4(), titulo: _title.text, loja: _store.text,
        preco: ReceiptParser.parseMoney(_price.text)!, dataCompra: _date!,
        duracaoMeses: int.parse(_months.text), categoria: _category,
        fotoPath: copiedImage, notas: _notes.text.trim(),
      );
      await widget.repository.save(warranty);
    } catch (_) {
      // O sistema de ficheiros e SQLite não partilham uma transação: compensar
      // a cópia quando o registo não foi confirmado, sem apagar dados existentes.
      if (copiedImage != null) {
        try {
          await _images.removeOwned(copiedImage);
        } catch (_) {
          // Pode sobrar um ficheiro órfão; nunca mascarar o erro de gravação.
        }
      }
      if (mounted) setState(() {
        _busy = false;
        _error = 'Não foi possível guardar a fatura. Os campos foram mantidos. '
            'Verifica o espaço disponível e tenta novamente.';
      });
      return;
    }
    // A gravação SQLite está concluída. Tratar notificações fora do bloco de
    // persistência impede apresentar uma falha de agendamento como falha de disco.
    if (!mounted) return;
    setState(() => _phase = 'A configurar os alertas de garantia…');
    final notificationNotice = await _scheduleSavedWarrantyAlerts();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = false);
    Navigator.pop(context, warranty);
    messenger.showSnackBar(SnackBar(content: Text(notificationNotice)));
  }

  Future<String> _scheduleSavedWarrantyAlerts() async {
    try {
      // Sempre o catálogo completo: a janela móvel conserva os próximos avisos
      // sem ultrapassar o limite de notificações pendentes do iOS.
      final warranties = await widget.repository.findAll();
      final result = await widget.notifications.syncWarrantyAlerts(
        warranties, daysBefore: const [30, 7], requestPermission: true,
      );
      if (!result.permissionGranted) {
        return 'Fatura guardada. Para receber alertas, autorize as notificações '
            'nas definições do telemóvel.';
      }
      if (result.deferredCount > 0) {
        return 'Fatura guardada. Os próximos alertas estão configurados; '
            'os restantes serão atualizados quando voltar a abrir a aplicação.';
      }
      if (result.scheduledIds.isEmpty) {
        return 'Fatura guardada. Não existem avisos futuros a agendar.';
      }
      return 'Fatura guardada. Alertas futuros de 30 e 7 dias configurados.';
    } catch (_) {
      return 'Fatura guardada. Não foi possível agendar os alertas. '
          'Pode tentar novamente em Definições > Notificações locais.';
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('Nova fatura')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _form,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Do talão para a tua WarrantyBox',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      const Text('Fotografa numa superfície plana e com boa luz. O texto é reconhecido no próprio telemóvel.'),
                      const SizedBox(height: 20),
                      Wrap(spacing: 12, runSpacing: 8, children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _scan(source: ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Tirar fotografia'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _scan(source: ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Galeria'),
                        ),
                      ]),
                      if (_busy) ...[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(children: [
                                const SizedBox(width: 24, height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2.5)),
                                const SizedBox(width: 16),
                                Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_phase),
                                    if (_analyzing) const Text(
                                      'A procurar a loja, o total e a data no dispositivo.',
                                    ),
                                  ],
                                )),
                              ]),
                            ),
                          ),
                        ),
                      ],
                      if (!_busy && _analysisTime != null) ...[
                        const SizedBox(height: 12),
                        Semantics(liveRegion: true, child: Text(
                          'Análise concluída em ${(_analysisTime!.inMilliseconds / 1000).toStringAsFixed(1)} s. '
                          'Confirma os campos sugeridos antes de guardar.',
                        )),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Semantics(liveRegion: true, child: Text(_error!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error))),
                      ],
                      if (_imagePath != null) ...[
                        const SizedBox(height: 20),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.file(File(_imagePath!), height: 240,
                            fit: BoxFit.contain, cacheWidth: 1000,
                            semanticLabel: 'Fotografia do talão selecionado',
                            errorBuilder: (_, _, _) => const SizedBox(height: 80,
                                child: Center(child: Text('Pré-visualização indisponível.'))),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _busy ? null : () => _scan(path: _imagePath),
                          icon: const Icon(Icons.refresh), label: const Text('Repetir leitura OCR'),
                        ),
                      ],
                      const SizedBox(height: 24),
                      const Text('Revê os dados antes de confirmar. A loja, o valor e a data são sugestões e podem conter erros.'),
                      const SizedBox(height: 16),
                      _field(_title, 'Nome do produto', validator: _required),
                      _field(_store, 'Loja (sugestão OCR)', validator: _required),
                      _field(_price, 'Valor em euros',
                          keyboard: const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) => ReceiptParser.parseMoney(value ?? '') == null
                              ? 'Indica um valor com duas casas decimais, por exemplo 24,99.' : null),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _chooseDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(_date == null ? 'Selecionar data de compra' : 'Compra: ${_formatDate(_date!)}'),
                      ),
                      const SizedBox(height: 16),
                      _field(_months, 'Garantia em meses', keyboard: TextInputType.number,
                          validator: (value) {
                            final months = int.tryParse(value ?? '');
                            return months == null || months < 1 || months > 1200
                                ? 'Indica uma duração entre 1 e 1200 meses.' : null;
                          }),
                      Wrap(spacing: 8, children: [
                        for (final months in [24, 36])
                          ActionChip(
                            label: Text('$months meses'),
                            onPressed: _busy ? null : () => _months.text = '$months',
                          ),
                      ]),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _category, isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder()),
                        items: warrantyCategories.entries.map((entry) => DropdownMenuItem(
                          value: entry.key, child: Text(entry.value),
                        )).toList(),
                        onChanged: _busy ? null : (value) => setState(() => _category = value!),
                      ),
                      const SizedBox(height: 16),
                      _field(_notes, 'Notas (opcional)', lines: 3),
                      if (_text.isNotEmpty)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Texto reconhecido'),
                          children: [
                            Align(alignment: Alignment.centerLeft,
                                child: SelectableText(_text)),
                            Align(alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: _text));
                                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Texto copiado para a área de transferência.')),
                                  );
                                },
                                icon: const Icon(Icons.copy_outlined), label: const Text('Copiar texto'),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 20),
                      const Text('A fatura e a fotografia ficam guardadas neste dispositivo. '
                          'Ao guardar, são configurados alertas a 30 e 7 dias da expiração. '
                          'Se necessário, o telemóvel pedirá autorização para notificações.'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _busy ? null : _confirm,
                        icon: const Icon(Icons.save_outlined), label: const Text('Guardar fatura'),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _field(TextEditingController controller, String label,
      {String? Function(String?)? validator, TextInputType? keyboard, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: controller, enabled: !_busy, validator: validator,
          keyboardType: keyboard, maxLines: lines,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  static String? _required(String? value) => value == null || value.trim().isEmpty ? 'Campo obrigatório.' : null;
  static String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';
  static String _platformMessage(String code) => switch (code) {
        'camera_access_denied' || 'camera_access_denied_without_prompt' || 'camera_access_restricted' =>
          'Sem acesso à câmara. Autoriza o acesso nas definições do dispositivo ou escolhe uma imagem da galeria.',
        'photo_access_denied' || 'photo_access_denied_without_prompt' || 'photo_access_restricted' =>
          'Sem acesso às fotografias. Revê a permissão nas definições do dispositivo.',
        'no_available_camera' => 'Não foi encontrada uma câmara. Escolhe uma imagem da galeria.',
        _ => 'Não foi possível abrir ou ler a imagem. Tenta novamente ou preenche os campos manualmente.',
      };
}

