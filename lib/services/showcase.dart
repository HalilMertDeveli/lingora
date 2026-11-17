import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/gold_wallet.dart';
import '../data/progress.dart';
import '../data/showcase_data.dart';
import 'firebase/firebase_providers.dart';
import 'profile.dart' show accountUidProvider;

export '../data/showcase_data.dart';

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
