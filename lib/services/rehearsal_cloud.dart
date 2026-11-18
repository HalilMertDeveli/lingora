import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/rehearsal.dart';
import 'firebase/firebase_providers.dart';

/// Mülakat Provası history follows the account: the analysed rehearsals the
/// server keeps in `rehearsals/{uid}/items` (transcripts and analysis, never
/// audio) come back on a new phone or after a reinstall. Real accounts only;
/// runs again when the account changes. Listened to in main.dart.
final rehearsalCloudSyncProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(firestoreProvider);
  final user = ref.watch(authStateProvider).value;
  if (db == null || user == null || user.isAnonymous) return 0;
  try {
    final snap = await db.collection('rehearsals').doc(user.uid).collection('items').limit(100).get();
    final sessions = [
      for (final d in snap.docs)
        ?RehearsalStore.fromCloud(d.id, d.data(), createdAt: (d.data()['createdAt'] as Timestamp?)?.toDate()),
    ];
    if (!ref.mounted) return 0;
    return ref.read(rehearsalProvider.notifier).mergeFromCloud(sessions);
  } on Object {
    return 0; // offline or not allowed: the phone's own history stays
  }
});
