import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Premium entitlement as stored by the server in Firestore
/// `entitlements/{uid}` (written only by Cloud Functions).
class ServerEntitlement {
  const ServerEntitlement({required this.premium, required this.status, this.productId, this.expiresAt});

  final bool premium;

  /// 'active' | 'grace' | 'pending' | 'expired' | 'invalid'
  final String status;
  final String? productId;
  final DateTime? expiresAt;

  /// Output of the `verifyPurchase` callable:
  /// `{premium, status, productId, expiresAt (ms since epoch | null)}`.
  factory ServerEntitlement.fromJson(Map<String, Object?> j) => ServerEntitlement(
    premium: j['premium'] == true,
    status: (j['status'] as String?) ?? 'invalid',
    productId: j['productId'] as String?,
    expiresAt: switch (j['expiresAt']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    },
  );

  bool activeAt(DateTime now) => premium && (expiresAt == null || expiresAt!.isAfter(now));
}

/// Server side of Premium. The Firebase implementation calls the
/// `verifyPurchase` callable and watches `entitlements/{uid}`; it overrides
/// [entitlementBackendProvider] once Firebase is ready.
abstract class EntitlementBackend {
  /// Verifies a Google Play purchase token server-side and returns the
  /// resulting entitlement. Throws on network/server errors.
  Future<ServerEntitlement> verify({required String productId, required String purchaseToken});

  /// The signed-in user's entitlement document (null when it doesn't exist).
  Stream<ServerEntitlement?> watch();
}

/// Null means "no server": Premium then relies on the store and the local
/// cache only.
final entitlementBackendProvider = Provider<EntitlementBackend?>((ref) => null);
