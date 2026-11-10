import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../billing/entitlement_backend.dart';
import '../billing/family.dart';
import 'firebase_providers.dart';

/// Calls a callable Cloud Function and returns its data. A seam so the
/// backends can be tested without Firebase.
typedef CallFunction = Future<Object?> Function(String name, Map<String, Object?> data);

CallFunction callableOf(FirebaseFunctions functions) =>
    (name, data) async => (await functions.httpsCallable(name).call<Object?>(data)).data;

Map<String, Object?> _map(Object? data) =>
    data is Map ? {for (final e in data.entries) '${e.key}': e.value} : const {};

/// `verifyPurchase` + `entitlements/{uid}` (functions/src/purchase.ts).
class FirebaseEntitlementBackend implements EntitlementBackend {
  FirebaseEntitlementBackend({required this.call, this.firestore, this.uid});

  final CallFunction call;
  final FirebaseFirestore? firestore;
  final String? uid;

  @override
  Future<ServerEntitlement> verify({required String productId, required String purchaseToken}) async {
    try {
      final data = await call('verifyPurchase', {'productId': productId, 'purchaseToken': purchaseToken});
      return ServerEntitlement.fromJson(_map(data));
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'already-exists' || e.code == 'invalid-argument') throw EntitlementRejected(e.code);
      rethrow;
    }
  }

  @override
  Stream<ServerEntitlement?> watch() {
    final db = firestore, id = uid;
    if (db == null || id == null) return const Stream.empty();
    return db.doc('entitlements/$id').snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return ServerEntitlement.fromDoc({
        ...data,
        'expiresAt': switch (data['expiresAt']) {
          final Timestamp t => t.millisecondsSinceEpoch,
          _ => null,
        },
      });
    });
  }
}

/// Family plan callables (functions/src/family.ts).
class FirebaseFamilyBackend implements FamilyBackend {
  FirebaseFamilyBackend(this.call);
  final CallFunction call;

  Future<Map<String, Object?>> _call(String name, [Map<String, Object?> data = const {}]) async {
    try {
      return _map(await call(name, data));
    } on FirebaseFunctionsException catch (e) {
      throw FamilyException(e.code, e.message);
    } on FamilyException {
      rethrow;
    } on Object {
      throw const FamilyException('unavailable');
    }
  }

  @override
  Future<FamilyInfo> getFamily() async => FamilyInfo.fromJson(await _call('getFamily'));

  @override
  Future<({String code, DateTime expiresAt})> createInvite() async {
    final r = await _call('createFamilyInvite');
    return (
      code: r['code'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch((r['expiresAt'] as num).toInt()),
    );
  }

  @override
  Future<ServerEntitlement> redeem(String code) async =>
      ServerEntitlement.fromJson(await _call('redeemFamilyCode', {'code': code}));

  @override
  Future<void> removeMember(String uid) => _call('removeFamilyMember', {'memberUid': uid});

  @override
  Future<void> leave() => _call('leaveFamily');
}

/// Overrides for `entitlementBackendProvider` and `familyBackendProvider`
/// (see main.dart): real backends once Firebase is ready, null otherwise.
final firebaseBillingOverrides = [
  entitlementBackendProvider.overrideWith((ref) {
    // Only with Firebase on and a signed-in user; otherwise Premium and packs
    // rely on the store and the local cache.
    final functions = ref.watch(functionsProvider);
    final uid = ref.watch(currentUidProvider);
    if (functions == null || uid == null) return null;
    return FirebaseEntitlementBackend(
      call: callableOf(functions),
      firestore: ref.watch(firestoreProvider),
      uid: uid,
    );
  }),
  familyBackendProvider.overrideWith((ref) {
    final functions = ref.watch(functionsProvider);
    return functions == null ? null : FirebaseFamilyBackend(callableOf(functions));
  }),
];
