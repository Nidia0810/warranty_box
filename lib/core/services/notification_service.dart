import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../features/warranties/domain/entities/warranty.dart';

class WarrantyAlert {
  const WarrantyAlert({required this.warranty, required this.daysBefore, required this.at});
  final Warranty warranty;
  final int daysBefore;
  final tz.TZDateTime at;
}

class AlertScheduleResult {
  const AlertScheduleResult({required this.permissionGranted,
    this.scheduledIds = const [], this.deferredCount = 0});
  final bool permissionGranted;
  final List<int> scheduledIds;

  /// Alertas adiados pelo limite da janela móvel. Não inclui datas já passadas.
  final int deferredCount;
}

/// Manter uma única instância partilhada pela aplicação.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin, DateTime Function()? clock})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _clock = clock ?? DateTime.now;

  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _clock;
  Future<void>? _initialization;
  Future<void> _queue = Future.value();
  tz.Location? _location;
  void Function(String warrantyId)? _onTap;
  String? initialWarrantyId;

  static const _namespace = 'warrantybox.expiry.v1';
  static const _channel = AndroidNotificationChannel(
    'warranty_expiry_v1', 'Validade das garantias',
    description: 'Lembretes antes do fim das garantias guardadas.',
    importance: Importance.defaultImportance,
  );

  /// Inicializa sem abrir uma caixa de permissões. Usar requestPermissions
  /// em resposta à ação do utilizador que ativa os alertas.
  Future<void> initialize({void Function(String warrantyId)? onTap}) async {
    if (onTap != null) _onTap = onTap;
    final opening = _initialization ??= _initialize();
    try {
      await opening;
    } catch (_) {
      if (identical(_initialization, opening)) _initialization = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('Este serviço de alertas requer Android ou iOS.');
    }
    tz_data.initializeTimeZones();
    await _updateTimeZone();
    await _plugin.initialize(
      settings: const InitializationSettings(
        // Criar este drawable no projeto Android; ver docs/PDF_NOTIFICATIONS.md.
        android: AndroidInitializationSettings('ic_stat_warranty'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final id = _payload(response.payload)?['warrantyId'];
        if (id is String) _onTap?.call(id);
      },
    );
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final id = _payload(launch?.notificationResponse?.payload)?['warrantyId'];
      if (id is String) initialWarrantyId = id;
    }
  }

  Future<void> _updateTimeZone() async {
    final zone = await FlutterTimezone.getLocalTimezone();
    // Não assumir Lisboa ou UTC se não for possível determinar o fuso real.
    _location = tz.getLocation(zone.identifier);
    tz.setLocalLocation(_location!);
  }

  Future<bool> requestPermissions() async {
    await initialize();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: false, sound: true) ?? false;
  }

  Future<bool> permissionsGranted() async {
    await initialize();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final options = await ios?.checkPermissions();
    return options?.isEnabled ?? false;
  }

  /// Reagenda só esta garantia. Cancelar primeiro os agendamentos antigos evita
  /// manter um alerta de 30 dias quando a preferência passa a ser 15 dias.
  Future<AlertScheduleResult> scheduleWarrantyAlerts(
    Warranty warranty, {
    List<int> daysBefore = const [30, 7],
    int hour = 9,
    int minute = 0,
    bool requestPermission = false,
    bool showProductName = false,
  }) => _serialized(() async {
        await initialize();
        final granted = requestPermission
            ? await requestPermissions() : await permissionsGranted();
        if (!granted) return const AlertScheduleResult(permissionGranted: false);
        await _updateTimeZone();
        final plans = buildAlertPlan(warranty, location: _location!, now: _clock(),
            daysBefore: daysBefore, hour: hour, minute: minute);
        final pending = await _plugin.pendingNotificationRequests();
        final replace = pending.where((item) =>
            _payload(item.payload)?['warrantyId'] == warranty.id).toList();
        final preserved = pending.where((item) => !replace.contains(item)).toList();
        if (Platform.isIOS && preserved.length + plans.length > 64) {
          throw StateError('Limite iOS de alertas pendentes atingido. '
              'Usa syncWarrantyAlerts com todas as garantias para uma janela móvel.');
        }
        return _replace(plans, replace, preserved, showProductName: showProductName);
      });

  /// Recomendado para um catálogo completo: mantém os próximos 60 alertas,
  /// preserva notificações de outros módulos e comunica os restantes como adiados.
  /// Voltar a sincronizar no arranque/foreground e após guardar, editar ou apagar.
  Future<AlertScheduleResult> syncWarrantyAlerts(
    List<Warranty> warranties, {
    List<int> daysBefore = const [30, 7],
    int hour = 9,
    int minute = 0,
    bool requestPermission = false,
    bool showProductName = false,
  }) => _serialized(() async {
        await initialize();
        final granted = requestPermission
            ? await requestPermissions() : await permissionsGranted();
        if (!granted) return const AlertScheduleResult(permissionGranted: false);
        await _updateTimeZone();
        final now = _clock();
        final unique = {for (final warranty in warranties) warranty.id: warranty};
        final plans = unique.values.expand((warranty) => buildAlertPlan(warranty,
            location: _location!, now: now, daysBefore: daysBefore,
            hour: hour, minute: minute)).toList()
          ..sort((a, b) {
            final order = a.at.compareTo(b.at);
            if (order != 0) return order;
            return '${a.warranty.id}:${a.daysBefore}'.compareTo('${b.warranty.id}:${b.daysBefore}');
          });
        final pending = await _plugin.pendingNotificationRequests();
        final replace = pending.where((item) => _payload(item.payload) != null).toList();
        final preserved = pending.where((item) => _payload(item.payload) == null).toList();
        final available = Platform.isIOS ? (64 - preserved.length).clamp(0, 60).toInt() : 60;
        final selected = plans.take(available).toList();
        return _replace(selected, replace, preserved,
            deferredCount: plans.length - selected.length, showProductName: showProductName);
      });

  Future<AlertScheduleResult> _replace(List<WarrantyAlert> plans,
      List<PendingNotificationRequest> replace, List<PendingNotificationRequest> preserved,
      {int deferredCount = 0, required bool showProductName}) async {
    final occupied = preserved.map((item) => item.id).toSet();
    final ids = <int>[];
    for (final item in replace) {
      await _plugin.cancel(id: item.id);
    }
    try {
      for (final plan in plans) {
        var id = notificationIdFor(plan.warranty.id, plan.daysBefore);
        // Não sobrescrever outra garantia/módulo em caso de colisão do hash.
        while (occupied.contains(id)) {
          id = id == 0x7fffffff ? 1 : id + 1;
        }
        occupied.add(id);
        final subject = showProductName ? 'A garantia de ${plan.warranty.titulo}' : 'Uma das suas garantias';
        final body = plan.daysBefore == 0 ? '$subject termina hoje.'
            : '$subject termina dentro de ${plan.daysBefore} dias.';
        await _plugin.zonedSchedule(
          id: id,
          title: 'WarrantyBox - lembrete de garantia',
          body: body,
          scheduledDate: plan.at,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'warranty_expiry_v1', 'Validade das garantias',
              channelDescription: 'Lembretes antes do fim das garantias guardadas.',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              visibility: NotificationVisibility.private,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true, presentBadge: false, presentSound: true,
            ),
          ),
          // Um lembrete de garantia não exige alarmes exatos ou permissões especiais.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: jsonEncode({'namespace': _namespace,
            'warrantyId': plan.warranty.id, 'daysBefore': plan.daysBefore}),
        );
        ids.add(id);
      }
    } catch (_) {
      for (final id in ids) {
        try { await _plugin.cancel(id: id); } catch (_) { /* Tentar na próxima sincronização. */ }
      }
      rethrow;
    }
    return AlertScheduleResult(permissionGranted: true,
        scheduledIds: List.unmodifiable(ids), deferredCount: deferredCount);
  }

  Future<void> cancelWarrantyAlerts(String warrantyId) => _serialized(() async {
        await initialize();
        for (final item in await _plugin.pendingNotificationRequests()) {
          if (_payload(item.payload)?['warrantyId'] == warrantyId) {
            await _plugin.cancel(id: item.id);
          }
        }
      });

  Future<void> cancelAllWarrantyAlerts() => _serialized(() async {
        await initialize();
        for (final item in await _plugin.pendingNotificationRequests()) {
          if (_payload(item.payload) != null) await _plugin.cancel(id: item.id);
        }
      });

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final next = _queue.then((_) => operation());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  /// Função pura testável: subtrai dias civis antes de aplicar o fuso e a hora.
  static List<WarrantyAlert> buildAlertPlan(Warranty warranty, {
    required tz.Location location,
    required DateTime now,
    List<int> daysBefore = const [30, 7],
    int hour = 9,
    int minute = 0,
  }) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59 ||
        daysBefore.any((days) => days < 0 || days > 36500)) {
      throw ArgumentError('Hora, minuto ou antecedência inválidos.');
    }
    final expiry = warranty.dataExpiracao;
    final plans = <WarrantyAlert>[];
    for (final days in daysBefore.toSet()) {
      final civil = DateTime.utc(expiry.year, expiry.month, expiry.day - days);
      final at = tz.TZDateTime(location, civil.year, civil.month, civil.day, hour, minute);
      if (at.isAfter(now)) plans.add(WarrantyAlert(warranty: warranty, daysBefore: days, at: at));
    }
    return plans..sort((a, b) => a.at.compareTo(b.at));
  }

  /// Hash determinístico entre arranques, ao contrário de String.hashCode.
  static int notificationIdFor(String warrantyId, int daysBefore) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode('$_namespace:$warrantyId:$daysBefore')) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    final id = hash & 0x7fffffff;
    return id == 0 ? 1 : id;
  }

  static Map<String, dynamic>? _payload(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final data = jsonDecode(value);
      if (data is Map<String, dynamic> && data['namespace'] == _namespace &&
          data['warrantyId'] is String) return data;
    } catch (_) { /* Ignorar payloads que pertencem a outros módulos. */ }
    return null;
  }
}
