import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/gold_wallet.dart';
import '../data/progress.dart';
import '../data/shop_catalog.dart';
import 'firebase/firebase_providers.dart';
import 'profile.dart' show accountUidProvider;

/// What friends see of the learner's Mağaza items (the "vitrin"): the worn
/// avatar and frame and up to [maxShowcase] chosen items. Stored in the
/// `showcase` map of `profiles/{uid}` (docs/altin.md); friends may read it,
/// only the owner may write it, and firestore.rules check its shape.
@immutable
class Showcase {
  const Showcase({this.avatar, this.frame, this.items = const [], this.useAvatar = false});

  /// Show [avatar] instead of the photo (Profil > Fotoğraf / Avatar).
  final bool useAvatar;

  final String? avatar;
  final String? frame;
  final List<String> items;

  bool get isEmpty => avatar == null && frame == null && items.isEmpty;

  /// The learner's own showcase, from their wallet.
  factory Showcase.of(Wallet w) => Showcase(
    avatar: equippedIn(w, WalletSlot.avatar)?.id,
    frame: equippedIn(w, WalletSlot.frame)?.id,
    useAvatar: prefersAvatar(w),
    items: [
      for (final id in w.showcase)
        if (shopItem(id) case final item? when item.showcasable && ownsItem(w, item)) id,
    ].take(maxShowcase).toList(),
  );

  Map<String, Object?> toMap() => {'avatar': avatar, 'frame': frame, 'items': items, 'useAvatar': useAvatar};

  /// From Firestore; unknown items (a newer app version) are skipped.
  static Showcase? fromMap(Object? raw) {
    if (raw is! Map) return null;
    String? known(Object? id) => id is String && shopItem(id) != null ? id : null;
    final items = raw['items'];
    return Showcase(
      avatar: known(raw['avatar']),
      frame: known(raw['frame']),
      useAvatar: raw['useAvatar'] == true,
      items: [
        if (items is List)
          for (final id in items.take(maxShowcase)) ?known(id),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Showcase &&
      other.avatar == avatar &&
      other.frame == frame &&
      other.useAvatar == useAvatar &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(avatar, frame, useAvatar, Object.hashAll(items));
}

/// Writes the showcase into `profiles/{uid}` (mockable in tests).
abstract class ShowcaseApi {
  Future<void> save(String uid, Showcase showcase);
}

class FirestoreShowcaseApi implements ShowcaseApi {
  FirestoreShowcaseApi(this._db);
  final FirebaseFirestore _db;

  @override
  Future<void> save(String uid, Showcase showcase) => _db.collection('profiles').doc(uid).set({
    'showcase': showcase.toMap(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

final showcaseApiProvider = Provider<ShowcaseApi?>((ref) {
  final db = ref.watch(firestoreProvider);
  return db == null ? null : FirestoreShowcaseApi(db);
});

/// The learner's own showcase, live.
final myShowcaseProvider = Provider<Showcase>((ref) => Showcase.of(ref.watch(walletProvider)));

/// Delay before a changed showcase is written (a burst of taps → one write).
final showcaseDebounceProvider = Provider<Duration>((ref) => const Duration(seconds: 2));

const _pushedKey = 'showcase_pushed_v1';

/// Keeps `profiles/{uid}.showcase` in step with the wallet for a signed-in
/// account. Guests keep it on the device (nobody can see it anyway).
/// Listened to in main.dart.
final showcaseSyncProvider = Provider<void>((ref) {
  final uid = ref.watch(accountUidProvider);
  final api = ref.watch(showcaseApiProvider);
  if (uid == null || api == null) return;
  Timer? timer;
  ref.onDispose(() => timer?.cancel());

  Future<void> push(Showcase s) async {
    final prefs = ref.read(prefsProvider);
    final tag = '$uid|${jsonEncode(s.toMap())}';
    if (prefs.getString(_pushedKey) == tag) return;
    try {
      await api.save(uid, s);
      await prefs.setString(_pushedKey, tag);
    } catch (e) {
      // Best effort: the next change or start tries again.
      debugPrint('Showcase upload failed: $e');
    }
  }

  ref.listen<Showcase>(myShowcaseProvider, (_, next) {
    timer?.cancel();
    timer = Timer(ref.read(showcaseDebounceProvider), () => push(next));
  }, fireImmediately: true);
});
