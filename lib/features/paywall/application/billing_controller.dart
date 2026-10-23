import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/billing_gateway.dart';
import '../domain/trial_record.dart';

class BillingController extends ChangeNotifier {
  BillingController({required BillingGateway gateway, required TrialStore trialStore,
      DateTime Function()? clock})
      : _gateway = gateway, _trialStore = trialStore, _clock = clock ?? DateTime.now;

  final BillingGateway _gateway;
  final TrialStore _trialStore;
  final DateTime Function() _clock;
  TrialRecord? _trial;
  Future<void>? _initialization;
  Future<void> _localQueue = Future.value();
  StreamSubscription<bool>? _subscription;
  Timer? _timer;
  bool _disposed = false;
  bool trialReady = false;
  bool storeReady = false;
  bool loadingStore = false;
  bool busy = false;
  bool lifetime = false;
  String? trialError;
  String? storeError;
  String? message;
  LifetimeOffer? offer;

  bool get trialStarted => _trial?.startedAt != null;
  bool get trialActive => trialReady && (_trial?.isActive(_clock()) ?? false);
  int get trialDaysRemaining => trialReady ? (_trial?.daysRemaining(_clock()) ?? 0) : 0;
  DateTime? get trialExpiresAt => _trial?.expiresAt;
  bool get canCreate => lifetime || trialActive;
  bool get canStartTrial => trialReady && !trialStarted && !lifetime && !busy;
  bool get canPurchase => storeReady && offer != null && !lifetime && !busy;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    _subscription = _gateway.accessChanges.listen((value) {
      if (value) message = 'Acesso vitalício ativo.';
      if (!value && lifetime) message = 'O acesso vitalício já não está ativo. Podes verificar com Restaurar compras.';
      lifetime = value;
      _emit();
    }, onError: (Object _) {
      storeError = 'Não foi possível atualizar o estado da compra.';
      _emit();
    });
    await refreshTrial();
    if (_disposed) return;
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(refreshTrial()));
    await refreshStore();
  }

  /// Serializa leituras/checkpoints e início de trial para evitar sobrescritas.
  Future<void> _withLocalLock(Future<void> Function() operation) {
    final next = _localQueue.then((_) => operation());
    _localQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> refreshTrial() => _withLocalLock(() async {
        try {
          final record = await _trialStore.read();
          if (record != null) {
            final updated = TrialRecord(startedAt: record.startedAt,
                lastSeenAt: record.effectiveNow(_clock()));
            await _trialStore.write(updated);
            _trial = updated;
          } else {
            _trial = null;
          }
          trialReady = true;
          trialError = null;
        } catch (_) {
          trialReady = false;
          trialError = 'Não foi possível ler o teste grátis neste dispositivo. Tenta novamente.';
        }
        _emit();
      });

  Future<void> refreshStore() async {
    if (loadingStore || busy || _disposed) return;
    loadingStore = true;
    storeError = null;
    _emit();
    try {
      await _gateway.configure();
      storeReady = true;
      try {
        // O SDK gere a cache de CustomerInfo. Não guardar um bool vitalício próprio.
        final active = await _gateway.hasLifetime();
        if (!active && lifetime) {
          message = 'O acesso vitalício já não está ativo. Podes verificar com Restaurar compras.';
        }
        lifetime = active;
      } catch (error) {
        storeError = _messageFor(error);
        // Uma falha de rede não revoga acesso já conhecido nesta sessão.
      }
      try {
        offer = await _gateway.loadOffer();
        if (offer == null && !lifetime) {
          storeError ??= 'A compra vitalícia ainda não está disponível nesta loja.';
        }
      } catch (error) {
        storeError ??= _messageFor(error);
      }
    } catch (error) {
      storeError = _messageFor(error);
    } finally {
      loadingStore = false;
      _emit();
    }
  }

  Future<void> refresh() async {
    await refreshTrial();
    await refreshStore();
  }

  Future<bool> startTrial() async {
    if (!canStartTrial) return false;
    busy = true;
    message = null;
    _emit();
    try {
      await _withLocalLock(() async {
        final existing = await _trialStore.read();
        if (existing?.startedAt != null) {
          _trial = existing;
          return;
        }
        final now = existing?.effectiveNow(_clock()) ?? _clock().toUtc();
        final record = TrialRecord(startedAt: now, lastSeenAt: now);
        // Conceder acesso só depois de o início ficar persistido.
        await _trialStore.write(record);
        _trial = record;
        trialReady = true;
        trialError = null;
      });
      message = trialActive ? 'Teste de 7 dias ativo. Sem cobrança automática.' : 'O teste deste dispositivo já terminou.';
      return trialActive;
    } catch (_) {
      trialReady = false;
      trialError = 'Não foi possível guardar o início do teste. Não foi iniciado um novo período.';
      return false;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<bool> purchase() async {
    if (!canPurchase) return false;
    return _storeOperation(_gateway.purchaseLifetime, restoring: false);
  }

  Future<bool> restore() async {
    if (!storeReady || busy) return false;
    return _storeOperation(_gateway.restore, restoring: true);
  }

  Future<bool> _storeOperation(Future<bool> Function() action, {required bool restoring}) async {
    busy = true;
    message = null;
    _emit();
    try {
      lifetime = await action();
      message = lifetime ? 'Acesso vitalício ativo.' : restoring
          ? 'Não foi encontrada uma compra vitalícia nesta conta da loja.'
          : 'A compra ainda não confirmou o acesso. Atualiza o estado ou restaura as compras.';
      return lifetime;
    } catch (error) {
      // Cancelamento ou pagamento pendente nunca concedem acesso novo.
      message = _messageFor(error);
      return false;
    } finally {
      busy = false;
      _emit();
    }
  }

  static String _messageFor(Object error) => error is BillingFailure
      ? error.message : 'A loja está temporariamente indisponível. Tenta novamente.';

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    _gateway.dispose();
    super.dispose();
  }
}
