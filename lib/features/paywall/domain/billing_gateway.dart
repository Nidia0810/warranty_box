class LifetimeOffer {
  const LifetimeOffer({required this.productId, required this.priceLabel});
  final String productId;
  final String priceLabel;
}

class BillingFailure implements Exception {
  const BillingFailure(this.message, {this.cancelled = false, this.pending = false});
  final String message;
  final bool cancelled;
  final bool pending;
}

abstract interface class BillingGateway {
  Stream<bool> get accessChanges;
  Future<void> configure();
  Future<bool> hasLifetime();
  Future<LifetimeOffer?> loadOffer();
  Future<bool> purchaseLifetime();
  Future<bool> restore();
  void dispose();
}
