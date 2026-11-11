import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress.dart';
import 'billing_service.dart';
import 'entitlement_backend.dart';
import 'premium.dart';

@immutable
class ExamPackState {
  const ExamPackState({
    this.owned = const {},
    this.products = const [],
    this.storeAvailable,
    this.busy,
    this.pending = const {},
    this.error,
    this.message,
    this.justPurchased,
  });

  /// Owned packs by [ExamPack.examId].
  final Set<String> owned;
  final List<StoreProduct> products;

  /// null until checked.
  final bool? storeAvailable;

  /// Pack whose purchase or restore is running.
  final ExamPack? busy;

  /// Packs whose payment is pending (e.g. cash/bank approval).
  final Set<String> pending;
  final String? error;
  final String? message;

  /// Set when a pack was just bought (the UI congratulates once).
  final ExamPack? justPurchased;

  StoreProduct? product(ExamPack pack) {
    for (final p in products) {
      if (p.id == pack.id) return p;
    }
    return null;
  }

  ExamPackState copyWith({
    Set<String>? owned,
    List<StoreProduct>? products,
    bool? storeAvailable,
    ExamPack? Function()? busy,
    Set<String>? pending,
    String? Function()? error,
    String? Function()? message,
    ExamPack? Function()? justPurchased,
  }) => ExamPackState(
    owned: owned ?? this.owned,
    products: products ?? this.products,
    storeAvailable: storeAvailable ?? this.storeAvailable,
    busy: busy != null ? busy() : this.busy,
    pending: pending ?? this.pending,
    error: error != null ? error() : this.error,
    message: message != null ? message() : this.message,
    justPurchased: justPurchased != null ? justPurchased() : this.justPurchased,
  );
}

/// One-time exam packs: purchase, server verification, restore and a
/// permanent local cache (a bought pack never expires; only the server can
/// take it back, e.g. after a refund).
class ExamPackController extends Notifier<ExamPackState> {
  static const _cacheKey = 'packs.owned';

  BillingService get _billing => ref.read(billingServiceProvider);
  bool _restoring = false;
  bool _restoredSomething = false;

  @override
  ExamPackState build() {
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
    final owned = ref.read(prefsProvider).getStringList(_cacheKey) ?? const [];
    return ExamPackState(owned: {...owned});
  }

  void _setOwned(Set<String> owned) {
    state = state.copyWith(owned: owned);
    ref.read(prefsProvider).setStringList(_cacheKey, owned.toList()..sort());
  }

  Future<void> loadProducts() async {
    state = state.copyWith(error: () => null, message: () => null);
    try {
      final available = await _billing.isAvailable();
      final products = available ? await _billing.loadProducts(ExamPack.ids) : const <StoreProduct>[];
      state = state.copyWith(storeAvailable: available && products.isNotEmpty, products: products);
    } on Object catch (e) {
      state = state.copyWith(storeAvailable: false, error: () => _describe(e));
    }
  }

  Future<void> buy(ExamPack pack) async {
    if (state.busy != null) return;
    state = state.copyWith(busy: () => pack, error: () => null, message: () => null);
    try {
      await _billing.buy(pack.id);
    } on Object catch (e) {
      state = state.copyWith(busy: () => null, error: () => _describe(e));
    }
  }

  Future<void> restore(ExamPack pack) async {
    if (state.busy != null) return;
    state = state.copyWith(busy: () => pack, error: () => null, message: () => null);
    _restoring = true;
    _restoredSomething = false;
    try {
      await _billing.restore();
      await Future<void>.delayed(restoreSettle);
      if (_restoring && !_restoredSomething) {
        state = state.copyWith(
          busy: () => null,
          message: () => 'Bu Google hesabında geri yüklenecek sınav paketi bulunamadı.',
        );
      } else {
        state = state.copyWith(busy: () => null);
      }
    } on Object catch (e) {
      state = state.copyWith(busy: () => null, error: () => _describe(e));
    } finally {
      _restoring = false;
    }
  }

  void acknowledge() =>
      state = state.copyWith(justPurchased: () => null, message: () => null, error: () => null);

  Future<void> _onPurchases(List<StorePurchase> purchases) async {
    for (final p in purchases) {
      final pack = ExamPack.byId(p.productId);
      if (pack == null) continue;
      switch (p.status) {
        case StorePurchaseStatus.pending:
          state = state.copyWith(busy: () => null, pending: {...state.pending, pack.examId});
        case StorePurchaseStatus.canceled:
          state = state.copyWith(busy: () => null, pending: {...state.pending}..remove(pack.examId));
        case StorePurchaseStatus.error:
          state = state.copyWith(
            busy: () => null,
            pending: {...state.pending}..remove(pack.examId),
            error: () => 'Satın alma tamamlanamadı${p.errorMessage == null ? '' : ' (${p.errorMessage})'}.',
          );
        case StorePurchaseStatus.purchased || StorePurchaseStatus.restored:
          if (p.status == StorePurchaseStatus.restored) _restoredSomething = true;
          await _grant(pack, p);
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

  Future<void> _grant(ExamPack pack, StorePurchase p) async {
    final isNew = p.status == StorePurchaseStatus.purchased;
    final backend = ref.read(entitlementBackendProvider);
    if (backend != null && p.token != null && p.token!.isNotEmpty) {
      try {
        final e = await backend.verify(productId: pack.id, purchaseToken: p.token!);
        if (!ref.mounted) return;
        if (!e.packs.contains(pack.examId)) {
          _fail(
            pack,
            isNew ? 'Satın alma doğrulanamadı. Ücret alındıysa "Satın alımları geri yükle"yi dene.' : null,
          );
          return;
        }
      } on EntitlementRejected catch (e) {
        if (!ref.mounted) return;
        _fail(
          pack,
          e.code == 'already-exists'
              ? 'Bu paket başka bir Dilbaz hesabına bağlı.'
              : 'Satın alma doğrulanamadı. Ücret alındıysa "Satın alımları geri yükle"yi dene.',
        );
        return;
      } on Object {
        // Server unreachable: trust the store; the next restore re-verifies.
      }
    }
    if (!ref.mounted) return;
    _setOwned({...state.owned, pack.examId});
    state = state.copyWith(
      busy: () => null,
      pending: {...state.pending}..remove(pack.examId),
      error: () => null,
      justPurchased: isNew ? () => pack : null,
    );
  }

  void _fail(ExamPack pack, String? error) {
    state = state.copyWith(
      busy: () => null,
      pending: {...state.pending}..remove(pack.examId),
      error: () => error,
    );
  }

  void _onServer(ServerEntitlement? e) {
    if (e == null) return;
    // The server is authoritative once it has seen packs (refunds remove
    // them); a document without any pack doesn't wipe a store-only grant
    // that hasn't been verified yet.
    if (e.packs.isEmpty) return;
    _setOwned({...e.packs.where((k) => ExamPack.values.any((p) => p.examId == k))});
  }

  static String _describe(Object e) =>
      e is BillingException ? e.message : 'Google Play\'e bağlanılamadı. İnternetini kontrol et.';
}

final examPackControllerProvider = NotifierProvider<ExamPackController, ExamPackState>(
  ExamPackController.new,
);

/// The full mock exams of [examId] are unlocked (pack owned, or Premium).
final examPackUnlockedProvider = Provider.family<bool, String>((ref, examId) {
  if (ref.watch(premiumProvider)) return true;
  return ref.watch(examPackControllerProvider.select((s) => s.owned.contains(examId)));
});
