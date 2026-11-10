import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress.dart';
import 'account_service.dart';
import 'firebase_providers.dart';
import 'progress_merge.dart';

/// Version of the `users/{uid}` document layout.
const userDocSchema = 1;

/// Fields of `users/{uid}` owned by the app (functions may add others).
const userDocFields = ['schemaVersion', 'progress', 'totalXp', 'displayName', 'clientUpdatedAt', 'updatedAt'];

const _metaKey = 'progress_sync_meta_v1';

enum SyncState {
  /// Firebase is not configured: progress lives only on this device.
  off,

  /// Waiting for a (possibly anonymous) user.
  signedOut,

  /// Reading the cloud copy.
  syncing,

  /// Local changes not yet confirmed by the server (e.g. offline).
  pending,

  /// The cloud copy matches this device.
  synced,
  error,
}

@immutable
class SyncStatus {
  const SyncStatus(this.state, {this.lastSyncedAt, this.error});
  final SyncState state;
  final DateTime? lastSyncedAt;
  final String? error;

  bool get backedUp => state == SyncState.synced;
}

/// Delay before local changes are written, so a lesson's burst of saves
/// becomes a single write.
final syncDebounceProvider = Provider<Duration>((ref) => const Duration(seconds: 3));

/// Offline-first, two-way sync of [progressProvider] with `users/{uid}`.
///
/// * every local save marks the device copy as changed and schedules a
///   debounced write;
/// * the cloud document is watched; whenever it differs it is merged with
///   [mergeProgress] (max/union, newest settings) and both sides converge.
///
/// Firestore's offline cache queues writes while there is no connection.
class ProgressSync extends Notifier<SyncStatus> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Timer? _timer;
  DocumentReference<Map<String, dynamic>>? _doc;
  String? _applied;
  bool _applying = false;
  int _uploads = 0;
  DateTime? _lastSynced;

  @override
  SyncStatus build() {
    ref.watch(autoAnonymousSignInProvider);
    final db = ref.watch(firestoreProvider);
    if (db == null) return const SyncStatus(SyncState.off);
    final uid = ref.watch(currentUidProvider);
    if (uid == null) return const SyncStatus(SyncState.signedOut);

    _doc = db.collection('users').doc(uid);
    _sub = _doc!.snapshots().listen(_onRemote, onError: _onError);
    ref.listen(progressProvider, (_, next) => _onLocal(next));
    ref.onDispose(() {
      _sub?.cancel();
      _timer?.cancel();
      _timer = null;
      _doc = null;
    });
    return SyncStatus(SyncState.syncing, lastSyncedAt: _lastSynced);
  }

  int get _localUpdatedAt {
    final raw = ref.read(prefsProvider).getString(_metaKey);
    if (raw == null) return 0;
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)['localUpdatedAt'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  set _localUpdatedAt(int ms) =>
      ref.read(prefsProvider).setString(_metaKey, jsonEncode({'localUpdatedAt': ms}));

  void _onLocal(Progress next) {
    if (_applying || canonicalProgress(next) == _applied) return;
    _localUpdatedAt = ref.read(clockProvider)().millisecondsSinceEpoch;
    _schedule();
  }

  void _onRemote(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (snap.metadata.hasPendingWrites) return; // our own write echoing back
    final data = snap.data();
    final rawProgress = data?['progress'];
    if (data == null || rawProgress is! Map) {
      _schedule(immediately: true);
      return;
    }
    final remote = progressFromFirestore(Map<String, dynamic>.from(rawProgress));
    final remoteAt = (data['clientUpdatedAt'] as num?)?.toInt() ?? 0;
    final localAt = _localUpdatedAt;
    final local = ref.read(progressProvider);
    final merged = mergeProgress(local, remote, localNewer: localAt >= remoteAt);

    if (canonicalProgress(merged) != canonicalProgress(local)) {
      _applying = true;
      try {
        ref.read(progressProvider.notifier).applySynced(merged);
      } finally {
        _applying = false;
      }
      _applied = canonicalProgress(ref.read(progressProvider));
      _localUpdatedAt = localAt > remoteAt ? localAt : remoteAt;
    }
    if (canonicalProgress(ref.read(progressProvider)) != canonicalProgress(remote)) {
      _schedule(immediately: true);
    } else if (_timer == null && _uploads == 0) {
      _setSynced();
    }
  }

  void _onError(Object e) {
    debugPrint('Progress sync error: $e');
    state = SyncStatus(SyncState.error, lastSyncedAt: _lastSynced, error: '$e');
  }

  void _schedule({bool immediately = false}) {
    if (_doc == null) return;
    _timer?.cancel();
    state = SyncStatus(SyncState.pending, lastSyncedAt: _lastSynced);
    _timer = Timer(immediately ? Duration.zero : ref.read(syncDebounceProvider), _upload);
  }

  Future<void> _upload() async {
    _timer = null;
    final doc = _doc;
    if (doc == null) return;
    final p = ref.read(progressProvider);
    _uploads++;
    try {
      await doc.set({
        'schemaVersion': userDocSchema,
        'progress': p.toJson(),
        'totalXp': p.totalXp,
        'displayName': shortDisplayName(ref.read(authStateProvider).value?.displayName),
        'clientUpdatedAt': _localUpdatedAt,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(mergeFields: userDocFields));
      _uploads--;
      if (ref.mounted && _doc == doc && _timer == null && _uploads == 0) _setSynced();
    } catch (e) {
      _uploads--;
      if (ref.mounted && _doc == doc) _onError(e);
    }
  }

  void _setSynced() {
    _lastSynced = ref.read(clockProvider)();
    state = SyncStatus(SyncState.synced, lastSyncedAt: _lastSynced);
  }
}

final progressSyncProvider = NotifierProvider<ProgressSync, SyncStatus>(ProgressSync.new);

/// Firestore rules accept a display name of at most 40 characters (or null).
String? shortDisplayName(String? name) {
  final t = name?.trim();
  if (t == null || t.isEmpty) return null;
  final chars = t.characters;
  return chars.length <= 40 ? t : chars.take(40).toString().trimRight();
}
