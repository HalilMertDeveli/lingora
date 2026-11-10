import 'package:in_app_purchase/in_app_purchase.dart';

import 'billing_service.dart';

/// Google Play Billing (and later the App Store) through `in_app_purchase`.
class IapBillingService implements BillingService {
  IapBillingService([InAppPurchase? iap]) : _iap = iap ?? InAppPurchase.instance;
  final InAppPurchase _iap;
  final Map<String, ProductDetails> _details = {};

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<List<StoreProduct>> loadProducts(Set<String> ids) async {
    final res = await _iap.queryProductDetails(ids);
    if (res.error != null) throw BillingException('Ürünler yüklenemedi: ${res.error!.message}');
    final out = <StoreProduct>[];
    // Google Play returns one entry per base plan/offer; the first one per
    // id is the base plan, which is what Lingora sells.
    for (final d in res.productDetails) {
      if (_details.containsKey(d.id)) continue;
      _details[d.id] = d;
      out.add(StoreProduct(id: d.id, title: d.title, price: d.price, rawPrice: d.rawPrice));
    }
    return out;
  }

  @override
  Future<void> buy(String productId) async {
    final d = _details[productId];
    if (d == null) throw const BillingException('Ürün bulunamadı. Biraz sonra tekrar dene.');
    // Subscriptions are bought as non-consumables.
    final started = await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: d));
    if (!started) throw const BillingException('Satın alma başlatılamadı.');
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Stream<List<StorePurchase>> get purchases =>
      _iap.purchaseStream.map((list) => [for (final p in list) _map(p)]);

  @override
  Future<void> complete(StorePurchase purchase) async {
    if (purchase.raw case final PurchaseDetails p when p.pendingCompletePurchase) {
      await _iap.completePurchase(p);
    }
  }

  static StorePurchase _map(PurchaseDetails p) => StorePurchase(
    productId: p.productID,
    status: switch (p.status) {
      PurchaseStatus.pending => StorePurchaseStatus.pending,
      PurchaseStatus.purchased => StorePurchaseStatus.purchased,
      PurchaseStatus.restored => StorePurchaseStatus.restored,
      PurchaseStatus.canceled => StorePurchaseStatus.canceled,
      PurchaseStatus.error => StorePurchaseStatus.error,
    },
    token: p.verificationData.serverVerificationData,
    errorMessage: p.error?.message,
    needsCompletion: p.pendingCompletePurchase,
    raw: p,
  );
}
