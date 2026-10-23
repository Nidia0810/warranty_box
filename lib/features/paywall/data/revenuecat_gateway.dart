import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../domain/billing_gateway.dart';

class RevenueCatGateway implements BillingGateway {
  static const _appleKey = String.fromEnvironment('REVENUECAT_IOS_API_KEY');
  static const _googleKey = String.fromEnvironment('REVENUECAT_ANDROID_API_KEY');
  static const _entitlement = String.fromEnvironment('REVENUECAT_ENTITLEMENT', defaultValue: 'lifetime');
  static const _productId = String.fromEnvironment('REVENUECAT_LIFETIME_PRODUCT', defaultValue: 'warrantybox_lifetime');
  final _changes = StreamController<bool>.broadcast();
  Package? _package;
  bool _configured = false;

  @override
  Stream<bool> get accessChanges => _changes.stream;

  @override
  Future<void> configure() async {
    if (_configured) return;
    if (!Platform.isIOS && !Platform.isAndroid) {
      throw const BillingFailure('As compras estão disponíveis em iOS e Android.');
    }
    final key = Platform.isIOS ? _appleKey : _googleKey;
    if (key.isEmpty || (kReleaseMode && key.startsWith('test_'))) {
      throw const BillingFailure('As compras não estão configuradas nesta versão da aplicação.');
    }
    await _guard(() async {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.error);
      // Sem appUserID próprio: identidade anónima gerida pelo SDK. Sem dados OCR.
      await Purchases.configure(PurchasesConfiguration(key));
      _configured = true;
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
    });
  }

  bool _unlocked(CustomerInfo info) {
    final entitlement = info.entitlements.active[_entitlement];
    return entitlement != null && entitlement.isActive &&
        entitlement.productIdentifier == _productId && entitlement.expirationDate == null;
  }

  void _onCustomerInfo(CustomerInfo info) {
    if (!_changes.isClosed) _changes.add(_unlocked(info));
  }

  void _requireConfigured() {
    if (!_configured) throw const BillingFailure('As compras estão temporariamente indisponíveis.');
  }

  @override
  Future<bool> hasLifetime() => _guard(() async {
        _requireConfigured();
        return _unlocked(await Purchases.getCustomerInfo());
      });

  @override
  Future<LifetimeOffer?> loadOffer() => _guard(() async {
        _requireConfigured();
        final offerings = await Purchases.getOfferings();
        _package = offerings.current?.availablePackages.where((package) =>
          package.packageType == PackageType.lifetime &&
          package.storeProduct.identifier == _productId &&
          package.storeProduct.productCategory == ProductCategory.nonSubscription,
        ).firstOrNull;
        final package = _package;
        return package == null ? null : LifetimeOffer(
          productId: package.storeProduct.identifier,
          priceLabel: package.storeProduct.priceString,
        );
      });

  @override
  Future<bool> purchaseLifetime() => _guard(() async {
        _requireConfigured();
        final package = _package;
        if (package == null) throw const BillingFailure('O produto ainda não está disponível. Atualiza e tenta novamente.');
        final result = await Purchases.purchase(PurchaseParams.package(package));
        return _unlocked(result.customerInfo);
      });

  @override
  Future<bool> restore() => _guard(() async {
        _requireConfigured();
        return _unlocked(await Purchases.restorePurchases());
      });

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (error) {
      final code = PurchasesErrorHelper.getErrorCode(error);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        throw const BillingFailure('Compra cancelada. Não foi ativado novo acesso.', cancelled: true);
      }
      if (code == PurchasesErrorCode.paymentPendingError) {
        throw const BillingFailure('Pagamento pendente de aprovação. O acesso será ativado após confirmação.', pending: true);
      }
      if (code == PurchasesErrorCode.networkError) {
        throw const BillingFailure('Sem ligação à loja. Verifica a Internet e tenta novamente.');
      }
      if (code == PurchasesErrorCode.productAlreadyPurchasedError) {
        throw const BillingFailure('Este produto já foi comprado. Usa Restaurar compras.');
      }
      throw const BillingFailure('Não foi possível concluir a operação na loja. Tenta novamente ou restaura as compras.');
    } on MissingPluginException {
      throw const BillingFailure('As compras não estão disponíveis nesta instalação.');
    }
  }

  @override
  void dispose() {
    if (_configured) Purchases.removeCustomerInfoUpdateListener(_onCustomerInfo);
    unawaited(_changes.close());
  }
}
