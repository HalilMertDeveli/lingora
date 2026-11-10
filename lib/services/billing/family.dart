import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'entitlement_backend.dart';

enum FamilyRole { none, member, owner }

class FamilyMember {
  const FamilyMember({required this.uid, this.displayName, this.joinedAt});
  final String uid;
  final String? displayName;
  final DateTime? joinedAt;
}

/// Output of the `getFamily` callable (functions/src/family.ts).
class FamilyInfo {
  const FamilyInfo({
    this.role = FamilyRole.none,
    this.ownerUid,
    this.ownerName,
    this.expiresAt,
    this.active = false,
    this.seats = 5,
    this.members = const [],
    this.code,
    this.codeExpiresAt,
  });

  final FamilyRole role;
  final String? ownerUid;
  final String? ownerName;
  final DateTime? expiresAt;

  /// Owner: the family plan is paid up.
  final bool active;

  /// People in the plan, owner included.
  final int seats;
  final List<FamilyMember> members;

  /// Current invite code (owner only), null when none or expired.
  final String? code;
  final DateTime? codeExpiresAt;

  int get freeSeats => seats - 1 - members.length;

  static DateTime? _ms(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;

  factory FamilyInfo.fromJson(Map<String, Object?> j) => FamilyInfo(
    role: switch (j['role']) {
      'owner' => FamilyRole.owner,
      'member' => FamilyRole.member,
      _ => FamilyRole.none,
    },
    ownerUid: j['ownerUid'] as String?,
    ownerName: j['ownerName'] as String?,
    expiresAt: _ms(j['expiresAt']),
    active: j['active'] == true || (j['role'] == 'member'),
    seats: (j['seats'] as int?) ?? 5,
    members: [
      for (final m in (j['members'] as List?) ?? const [])
        if (m is Map)
          FamilyMember(
            uid: m['uid'] as String,
            displayName: m['displayName'] as String?,
            joinedAt: _ms(m['joinedAt']),
          ),
    ],
    code: j['code'] as String?,
    codeExpiresAt: _ms(j['codeExpiresAt']),
  );
}

/// A family call failed; [code] is the callable error code and [reason] its
/// message (e.g. `family_full`). [message] is Turkish, for the user.
class FamilyException implements Exception {
  const FamilyException(this.code, [this.reason]);
  final String code;
  final String? reason;

  String get message => switch (reason) {
    'invalid_code' => 'Kod 8 karakter olmalı (ör. ABCD-EFGH).',
    'unknown_code' => 'Bu davet kodu bulunamadı. Aile yöneticisinden yeni bir kod iste.',
    'code_expired' => 'Bu davet kodunun süresi dolmuş. Aile yöneticisinden yeni bir kod iste.',
    'own_family' => 'Bu senin kendi aile planının kodu.',
    'owns_family' => 'Kendi aile planın varken başka bir aileye katılamazsın.',
    'family_expired' => 'Bu aile planının süresi dolmuş.',
    'family_full' => 'Bu aile planı dolu (en fazla 5 kişi).',
    'in_other_family' => 'Zaten başka bir aile planındasın. Önce oradan ayrıl.',
    'no_family_plan' => 'Davet kodu için etkin bir aile planı gerekiyor.',
    'not_a_member' => 'Bu kişi artık ailende değil.',
    'not_in_family' => 'Bir aile planında değilsin.',
    _ => switch (code) {
      'unauthenticated' => 'Önce Profil > Hesap bölümünden giriş yapmalısın.',
      'unavailable' || 'deadline-exceeded' || 'internal' => 'Sunucuya ulaşılamadı. İnternetini kontrol et.',
      _ => 'İşlem tamamlanamadı. Biraz sonra tekrar dene.',
    },
  };

  @override
  String toString() => 'FamilyException($code, $reason)';
}

/// Family plan calls (Cloud Functions). Errors are [FamilyException]s.
abstract class FamilyBackend {
  Future<FamilyInfo> getFamily();

  /// Owner: a new invite code (the old one stops working).
  Future<({String code, DateTime expiresAt})> createInvite();

  /// Joins the family of the code's owner; returns the new Premium.
  Future<ServerEntitlement> redeem(String code);

  /// Owner removes a member.
  Future<void> removeMember(String uid);

  /// Member leaves their family.
  Future<void> leave();
}

/// Null when there is no server (Firebase off): the family plan then can't
/// work and the UI says so.
final familyBackendProvider = Provider<FamilyBackend?>((ref) => null);
