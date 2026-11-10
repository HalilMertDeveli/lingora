import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Entitlements as stored by the server in Firestore `entitlements/{uid}`
/// (written only by Cloud Functions): Premium plus one-time exam packs.
class ServerEntitlement {
  const ServerEntitlement({
    required this.premium,
    required this.status,
    this.productId,
    this.expiresAt,
    this.packs = const {},
    this.source,
    this.familyOwnerUid,
    this.familyRole,
  });

  final bool premium;

  /// 'active' | 'grace' | 'pending' | 'expired' | 'invalid'
  final String status;
  final String? productId;
  final DateTime? expiresAt;

  /// Owned exam packs by exam id (`yds`, `lgs`), see `ExamPack.examId`.
  final Set<String> packs;

  /// Where Premium came from: 'play' | 'test' | 'family' | 'org'.
  final String? source;

  /// Family plan membership (null when not in a family).
  final String? familyOwnerUid;

  /// 'owner' | 'member'
  final String? familyRole;

  /// Output of the `verifyPurchase` / `redeemFamilyCode` callables
  /// (europe-west1): `{active, productId, expiresAt (ms since epoch), packs?}`.
  /// `premium` and `status` are accepted too.
  factory ServerEntitlement.fromJson(Map<String, Object?> j) {
    final premium = j['active'] == true || j['premium'] == true;
    final family = j['family'];
    return ServerEntitlement(
      premium: premium,
      status: (j['status'] as String?) ?? (premium ? 'active' : 'expired'),
      productId: j['productId'] as String?,
      expiresAt: switch (j['expiresAt']) {
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
        final DateTime d => d,
        _ => null,
      },
      packs: switch (j['packs']) {
        final Map<Object?, Object?> m => {
          for (final e in m.entries)
            if (e.value == true) '${e.key}',
        },
        _ => const {},
      },
      source: j['source'] as String?,
      familyOwnerUid: family is Map ? family['ownerUid'] as String? : null,
      familyRole: family is Map ? family['role'] as String? : null,
    );
  }

  /// An `entitlements/{uid}` document. The caller converts the Firestore
  /// `expiresAt` Timestamp to a [DateTime] or milliseconds first.
  factory ServerEntitlement.fromDoc(Map<String, Object?> data) => ServerEntitlement.fromJson(data);

  bool activeAt(DateTime now) => premium && (expiresAt == null || expiresAt!.isAfter(now));
}

/// The server refused the purchase for good (e.g. `already-exists`: the
/// token belongs to another account, or `invalid-argument`). Unlike network
/// errors, the app must not fall back to trusting the store.
class EntitlementRejected implements Exception {
  const EntitlementRejected(this.code);
  final String code;
  @override
  String toString() => 'EntitlementRejected($code)';
}

/// Server side of Premium and exam packs. The Firebase implementation calls
/// the `verifyPurchase` callable and watches `entitlements/{uid}`; it
/// overrides [entitlementBackendProvider] once Firebase is ready.
abstract class EntitlementBackend {
  /// Verifies a Google Play purchase token server-side and returns the
  /// resulting entitlement. Throws [EntitlementRejected] when the server
  /// refuses the purchase, anything else on network/server errors
  /// (including `unimplemented`), after which the store is trusted for now.
  Future<ServerEntitlement> verify({required String productId, required String purchaseToken});

  /// The signed-in user's entitlement document (null when it doesn't exist).
  Stream<ServerEntitlement?> watch();
}

/// Null means "no server": Premium then relies on the store and the local
/// cache only.
final entitlementBackendProvider = Provider<EntitlementBackend?>((ref) => null);
