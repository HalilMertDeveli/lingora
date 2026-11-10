import 'dart:async';

/// A subscription as offered by the store, in the store's own currency.
class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.title,
    required this.price,
    required this.rawPrice,
    this.freeTrialDays = 0,
  });

  final String id;
  final String title;

  /// Free trial the store offers this user before the first payment (0 = none).
  /// Google Play only returns trial offers to users who are eligible.
  final int freeTrialDays;

  /// Formatted, localised price from the store, e.g. "₺129,99".
  final String price;
  final double rawPrice;
}

enum StorePurchaseStatus { pending, purchased, restored, canceled, error }

/// One update about a purchase, delivered by [BillingService.purchases].
class StorePurchase {
  const StorePurchase({
    required this.productId,
    required this.status,
    this.token,
    this.errorMessage,
    this.needsCompletion = false,
    this.raw,
  });

  final String productId;
  final StorePurchaseStatus status;

  /// Google Play purchase token (sent to the server for verification).
  final String? token;
  final String? errorMessage;

  /// The purchase must be acknowledged with [BillingService.complete], or
  /// Google Play refunds it after three days.
  final bool needsCompletion;

  /// The platform object, needed to complete the purchase.
  final Object? raw;
}

/// Thin seam over the store so the app and tests never touch the plugin.
abstract class BillingService {
  /// The store can be reached and purchases are possible on this device.
  Future<bool> isAvailable();

  /// Products for [ids]; unknown ids are left out.
  Future<List<StoreProduct>> loadProducts(Set<String> ids);

  /// Starts the store's purchase sheet. The result arrives on [purchases].
  Future<void> buy(String productId);

  /// Asks the store to re-deliver active subscriptions on [purchases].
  Future<void> restore();

  Stream<List<StorePurchase>> get purchases;

  /// Acknowledges a delivered purchase.
  Future<void> complete(StorePurchase purchase);
}

class BillingException implements Exception {
  const BillingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Used where no store exists (desktop, web, tests by default).
class UnavailableBillingService implements BillingService {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<StoreProduct>> loadProducts(Set<String> ids) async => const [];

  @override
  Future<void> buy(String productId) async =>
      throw const BillingException('Satın alma bu cihazda kullanılamıyor.');

  @override
  Future<void> restore() async {}

  @override
  Stream<List<StorePurchase>> get purchases => const Stream.empty();

  @override
  Future<void> complete(StorePurchase purchase) async {}
}
