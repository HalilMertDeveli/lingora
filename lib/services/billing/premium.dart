import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress.dart';
import 'billing_service.dart';
import 'entitlement_backend.dart';
import 'iap_billing_service.dart';
import 'products.dart';

export 'billing_service.dart' show StoreProduct;
export 'products.dart';

/// `--dart-define=LINGORA_PREMIUM=1` unlocks Premium for local testing.
/// Ignored in release builds.
const _devPremiumFlag = String.fromEnvironment('LINGORA_PREMIUM');
final premiumDevOverrideProvider = Provider<bool>(
  (ref) => !kReleaseMode && (_devPremiumFlag == '1' || _devPremiumFlag == 'true'),
);

final billingServiceProvider = Provider<BillingService>((ref) {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) return IapBillingService();
  return UnavailableBillingService();
});

/// After a restore request, how long to wait for the store to re-deliver
/// purchases before saying there was nothing to restore.
const restoreSettle = Duration(seconds: 2);

/// Extra days the offline cache keeps Premium after a period ends, so a
/// renewal that hasn't been re-confirmed yet doesn't lock the user out.
const offlineGraceDays = 3;

enum PremiumSource { none, store, server }

@immutable
class PremiumState {
  const PremiumState({
    this.active = false,
    this.source = PremiumSource.none,
    this.productId,
    this.expiresAt,
    this.storeAvailable,
    this.products = const [],
    this.busy = false,
    this.pending = false,
    this.error,
    this.message,
    this.justPurchased = false,
  });

  /// Entitlement (before the expiry check, see [premiumProvider]).
  final bool active;
  final PremiumSource source;
  final String? productId;
  final DateTime? expiresAt;

  /// null until checked.
  final bool? storeAvailable;
  final List<StoreProduct> products;

  /// A purchase or restore is running.
  final bool busy;

  /// The store reported a pending payment (e.g. awaiting cash/bank approval).
  final bool pending;
  final String? error;

  /// Neutral information, e.g. "nothing to restore".
  final String? message;

  /// Set when a new purchase has just been granted (the paywall closes).
  final bool justPurchased;

  StoreProduct? product(PremiumPlan plan) {
    for (final p in products) {
      if (p.id == plan.id) return p;
    }
    return null;
  }

  PremiumState copyWith({
    bool? active,
    PremiumSource? source,
    String? Function()? productId,
    DateTime? Function()? expiresAt,
    bool? storeAvailable,
    List<StoreProduct>? products,
    bool? busy,
    bool? pending,
    String? Function()? error,
    String? Function()? message,
    bool? justPurchased,
  }) => PremiumState(
    active: active ?? this.active,
    source: source ?? this.source,
    productId: productId != null ? productId() : this.productId,
    expiresAt: expiresAt != null ? expiresAt() : this.expiresAt,
    storeAvailable: storeAvailable ?? this.storeAvailable,
    products: products ?? this.products,
    busy: busy ?? this.busy,
    pending: pending ?? this.pending,
    error: error != null ? error() : this.error,
    message: message != null ? message() : this.message,
    justPurchased: justPurchased ?? this.justPurchased,
  );
}

/// Owns the store connection and the Premium entitlement.
///
/// Sources, strongest first: the server entitlement (`entitlements/{uid}`,
/// via [entitlementBackendProvider]) when Firebase is ready; otherwise the
/// store's own purchase delivery. The result is cached in SharedPreferences
/// with an expiry so Premium works offline and lapses on its own if a
/// subscription is cancelled and never re-confirmed.
class PremiumController extends Notifier<PremiumState> {
  static const _cacheKey = 'premium.cache';

  BillingService get _billing => ref.read(billingServiceProvider);
  DateTime _now() => ref.read(clockProvider)();
  bool _restoring = false;
  bool _restoredSomething = false;

  @override
  PremiumState build() {
    final billing = ref.watch(billingServiceProvider);
    final backend = ref.watch(entitlementBackendProvider);
    final subs = <StreamSubscription<Object?>>[
      billing.purchases.listen(_onPurchases, onError: (Object _) {}),
      if (backend != null) backend.watch().listen(_onServer, onError: (Object _) {}),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    final cached = _readCache();
    if (cached.active) {
      // Re-confirm a cached subscription quietly (extends the cache).
      Future.microtask(() async {
        try {
          if (await billing.isAvailable()) await billing.restore();
        } on Object {
          // Offline: the cache stays valid until it expires.
        }
      });
    }
    return cached;
  }

  PremiumState _readCache() {
    final raw = ref.read(prefsProvider).getString(_cacheKey);
    if (raw == null) return const PremiumState();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final until = DateTime.fromMillisecondsSinceEpoch(j['until'] as int);
      if (!until.isAfter(_now())) return const PremiumState();
      return PremiumState(
        active: true,
        source: j['source'] == 'server' ? PremiumSource.server : PremiumSource.store,
        productId: j['productId'] as String?,
        expiresAt: until,
      );
    } on Object {
      return const PremiumState();
    }
  }

  void _writeCache() {
    final prefs = ref.read(prefsProvider);
    if (!state.active || state.expiresAt == null) {
      prefs.remove(_cacheKey);
      return;
    }
    prefs.setString(
      _cacheKey,
      jsonEncode({
        'productId': state.productId,
        'until': state.expiresAt!.millisecondsSinceEpoch,
        'source': state.source.name,
      }),
    );
  }

  /// Checks the store and loads prices. Called when the paywall opens.
  Future<void> loadProducts() async {
    state = state.copyWith(error: () => null, message: () => null, justPurchased: false);
    try {
      final available = await _billing.isAvailable();
      final products = available ? await _billing.loadProducts(PremiumPlan.ids) : const <StoreProduct>[];
      state = state.copyWith(storeAvailable: available && products.isNotEmpty, products: products);
    } on Object catch (e) {
      state = state.copyWith(storeAvailable: false, error: () => _describe(e));
    }
  }

  Future<void> buy(PremiumPlan plan) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, error: () => null, message: () => null, justPurchased: false);
    try {
      await _billing.buy(plan.id);
    } on Object catch (e) {
      state = state.copyWith(busy: false, error: () => _describe(e));
    }
  }

  Future<void> restore() async {
    if (state.busy) return;
    state = state.copyWith(busy: true, error: () => null, message: () => null, justPurchased: false);
    _restoring = true;
    _restoredSomething = false;
    try {
      await _billing.restore();
      await Future<void>.delayed(restoreSettle);
      if (_restoring && !_restoredSomething) {
        state = state.copyWith(
          busy: false,
          message: () => 'Bu Google hesabında geri yüklenecek aktif abonelik bulunamadı.',
        );
      }
    } on Object catch (e) {
      state = state.copyWith(busy: false, error: () => _describe(e));
    } finally {
      _restoring = false;
    }
  }

  /// Clears transient flags once the UI has reacted to them.
  void acknowledge() => state = state.copyWith(justPurchased: false, message: () => null, error: () => null);

  Future<void> _onPurchases(List<StorePurchase> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case StorePurchaseStatus.pending:
          state = state.copyWith(busy: false, pending: true);
        case StorePurchaseStatus.canceled:
          state = state.copyWith(busy: false, pending: false);
        case StorePurchaseStatus.error:
          state = state.copyWith(
            busy: false,
            pending: false,
            error: () => 'Satın alma tamamlanamadı${p.errorMessage == null ? '' : ' (${p.errorMessage})'}.',
          );
        case StorePurchaseStatus.purchased || StorePurchaseStatus.restored:
          if (PremiumPlan.byId(p.productId) != null) {
            if (p.status == StorePurchaseStatus.restored) _restoredSomething = true;
            await _grant(p);
          }
      }
      if (p.needsCompletion) {
        try {
          await _billing.complete(p);
        } on Object {
          // Re-delivered by the store on next launch.
        }
      }
    }
  }

  Future<void> _grant(StorePurchase p) async {
    final plan = PremiumPlan.byId(p.productId)!;
    final isNew = p.status == StorePurchaseStatus.purchased;
    final backend = ref.read(entitlementBackendProvider);
    if (backend != null && p.token != null && p.token!.isNotEmpty) {
      try {
        final e = await backend.verify(productId: p.productId, purchaseToken: p.token!);
        if (!ref.mounted) return;
        if (e.activeAt(_now())) {
          _setActive(
            PremiumSource.server,
            e.productId ?? p.productId,
            e.expiresAt ?? _now().add(Duration(days: plan.days)),
            isNew,
          );
        } else if (e.status == 'pending') {
          state = state.copyWith(busy: false, pending: true);
        } else {
          state = state.copyWith(
            busy: false,
            pending: false,
            error: () => isNew
                ? 'Satın alma doğrulanamadı. Ücret alındıysa "Satın alımları geri yükle"yi dene.'
                : null,
          );
        }
        return;
      } on EntitlementRejected catch (e) {
        if (!ref.mounted) return;
        state = state.copyWith(
          busy: false,
          pending: false,
          error: () => e.code == 'already-exists'
              ? 'Bu abonelik başka bir Lingora hesabına bağlı.'
              : 'Satın alma doğrulanamadı. Ücret alındıysa "Satın alımları geri yükle"yi dene.',
        );
        return;
      } on Object {
        // Server unreachable: trust the store for now; the next restore
        // re-verifies.
      }
    }
    if (!ref.mounted) return;
    _setActive(
      PremiumSource.store,
      p.productId,
      _now().add(Duration(days: plan.days + offlineGraceDays)),
      isNew,
    );
  }

  void _setActive(PremiumSource source, String productId, DateTime until, bool isNew) {
    state = state.copyWith(
      active: true,
      source: source,
      productId: () => productId,
      expiresAt: () => until,
      busy: false,
      pending: false,
      error: () => null,
      justPurchased: isNew || state.justPurchased || _restoring,
    );
    _writeCache();
  }

  void _onServer(ServerEntitlement? e) {
    if (e == null) return;
    if (e.activeAt(_now())) {
      state = state.copyWith(
        active: true,
        source: PremiumSource.server,
        productId: () => e.productId,
        expiresAt: () => e.expiresAt ?? _now().add(const Duration(days: 1)),
      );
    } else {
      // The server is authoritative: cancelled/expired/refunded.
      state = state.copyWith(active: false, source: PremiumSource.none, expiresAt: () => null);
    }
    _writeCache();
  }

  static String _describe(Object e) =>
      e is BillingException ? e.message : 'Google Play\'e bağlanılamadı. İnternetini kontrol et.';
}

final premiumControllerProvider = NotifierProvider<PremiumController, PremiumState>(PremiumController.new);

/// True when the user may use Premium features right now.
final premiumProvider = Provider<bool>((ref) {
  if (ref.watch(premiumDevOverrideProvider)) return true;
  final s = ref.watch(premiumControllerProvider);
  if (!s.active) return false;
  return s.expiresAt == null || s.expiresAt!.isAfter(ref.read(clockProvider)());
});

/// Free mock exams used today (resets at local midnight).
class MockExamQuota extends Notifier<int> {
  static const _key = 'premium.mock_quota';

  String _today() {
    final d = ref.read(clockProvider)();
    return '${d.year}-${d.month}-${d.day}';
  }

  @override
  int build() {
    final raw = ref.read(prefsProvider).getString(_key);
    if (raw == null) return 0;
    final i = raw.lastIndexOf(':');
    if (i < 0 || raw.substring(0, i) != _today()) return 0;
    return int.tryParse(raw.substring(i + 1)) ?? 0;
  }

  /// Re-reads the date (e.g. after midnight).
  void refresh() => state = build();

  void recordStart() {
    state = build() + 1;
    ref.read(prefsProvider).setString(_key, '${_today()}:$state');
  }
}

final mockExamQuotaProvider = NotifierProvider<MockExamQuota, int>(MockExamQuota.new);

/// The user may start another mini mock exam now.
bool canStartMockExam(WidgetRef ref) {
  if (ref.read(premiumProvider)) return true;
  ref.read(mockExamQuotaProvider.notifier).refresh();
  return ref.read(mockExamQuotaProvider) < freeMockExamsPerDay;
}
