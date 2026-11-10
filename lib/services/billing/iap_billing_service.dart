import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

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
    // Google Play returns one entry per base plan/offer. Lingora shows the
    // base plan's price and, when Play offers this user a free-trial offer
    // (only eligible users get one), buys through that offer.
    final byId = <String, List<ProductDetails>>{};
    for (final d in res.productDetails) {
      (byId[d.id] ??= []).add(d);
    }
    final out = <StoreProduct>[];
    for (final entry in byId.entries) {
      final offers = entry.value;
      final base = offers.firstWhere((d) => _offer(d)?.offerId == null, orElse: () => offers.first);
      final trial = offers.where((d) => trialDaysOf(d) > 0).firstOrNull;
      _details[entry.key] = trial ?? base;
      // The last pricing phase is the recurring price.
      final phase = _offer(base)?.pricingPhases.lastOrNull;
      out.add(
        StoreProduct(
          id: base.id,
          title: base.title,
          price: phase?.formattedPrice ?? base.price,
          rawPrice: phase == null ? base.rawPrice : phase.priceAmountMicros / 1e6,
          freeTrialDays: trial == null ? 0 : trialDaysOf(trial),
        ),
      );
    }
    return out;
  }

  static SubscriptionOfferDetailsWrapper? _offer(ProductDetails d) {
    if (d is! GooglePlayProductDetails) return null;
    final i = d.subscriptionIndex;
    final offers = d.productDetails.subscriptionOfferDetails;
    return i == null || offers == null || i >= offers.length ? null : offers[i];
  }

  /// Length of a free first phase (price 0), e.g. `P7D` → 7, `P1W` → 7.
  static int trialDaysOf(ProductDetails d) {
    final first = _offer(d)?.pricingPhases.firstOrNull;
    if (first == null || first.priceAmountMicros != 0) return 0;
    return isoPeriodDays(first.billingPeriod) * (first.billingCycleCount < 1 ? 1 : first.billingCycleCount);
  }

  /// Days in an ISO 8601 period such as `P7D`, `P2W`, `P1M` (months as 30).
  static int isoPeriodDays(String period) {
    final m = RegExp(r'^P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)W)?(?:(\d+)D)?$').firstMatch(period);
    if (m == null) return 0;
    int n(int g) => int.tryParse(m.group(g) ?? '') ?? 0;
    return n(1) * 365 + n(2) * 30 + n(3) * 7 + n(4);
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
