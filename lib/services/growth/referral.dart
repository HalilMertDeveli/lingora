import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress.dart';
import '../firebase/firebase_providers.dart';

/// The user's invite code and how many rewards it earned.
class InviteInfo {
  const InviteInfo({
    required this.code,
    this.rewardDays = 7,
    this.rewardedThisMonth = 0,
    this.maxPerMonth = 5,
    this.totalRewarded = 0,
  });

  factory InviteInfo.fromJson(Map<Object?, Object?> j) => InviteInfo(
    code: j['code'] as String,
    rewardDays: (j['rewardDays'] as num?)?.toInt() ?? 7,
    rewardedThisMonth: (j['rewardedThisMonth'] as num?)?.toInt() ?? 0,
    maxPerMonth: (j['maxPerMonth'] as num?)?.toInt() ?? 5,
    totalRewarded: (j['totalRewarded'] as num?)?.toInt() ?? 0,
  );

  final String code;
  final int rewardDays;
  final int rewardedThisMonth;
  final int maxPerMonth;
  final int totalRewarded;
}

/// A redemption the server refused, with its reason code
/// (functions/src/referral.ts), e.g. `own_code`, `device_used`.
class ReferralException implements Exception {
  const ReferralException(this.reason);
  final String reason;

  /// Turkish message for the user.
  String get message => switch (reason) {
    'invalid_code' || 'unknown_code' => 'Bu davet kodu geçersiz. Harfleri kontrol edip tekrar dene.',
    'own_code' => 'Kendi davet kodunu kullanamazsın.',
    'already_redeemed' => 'Bu hesap daha önce bir davet kodu kullandı.',
    'device_used' => 'Bu cihazda daha önce bir davet kodu kullanıldı.',
    'same_device' =>
      'Bu kod davet eden kişinin kullandığı bir telefonda kullanılamaz. Kendi telefonundan dene.',
    'mutual_invite' => 'Seni davet eden kişinin kodunu karşılıklı kullanamazsın.',
    'not_new_user' => 'Davet kodları yalnızca yeni hesaplarda (ilk 14 gün) kullanılabilir.',
    'sign_in_required' => 'Davet kodu kullanmak için önce Profil > Hesap bölümünden giriş yap.',
    'offline' => 'Sunucuya ulaşılamadı. İnternetini kontrol edip tekrar dene.',
    _ => 'Davet kodu şu an kullanılamadı. Biraz sonra tekrar dene.',
  };

  @override
  String toString() => 'ReferralException($reason)';
}

/// Where the user's own redemption stands.
enum InviteStatus {
  /// No code used.
  none,

  /// Code accepted; both get Premium after the user's first lesson.
  pending,

  /// Premium granted.
  rewarded;

  static InviteStatus byName(Object? name) => values.where((v) => v.name == name).firstOrNull ?? none;
}

abstract class ReferralService {
  /// The user's code; [deviceId] lets the server refuse it on this phone.
  Future<InviteInfo> myInvite({String? deviceId});

  /// Redeems [code]. Premium arrives through `entitlements/{uid}` once the
  /// user has finished their first lesson ([InviteStatus.pending] until then).
  Future<InviteStatus> redeem(String code, {required String deviceId});

  /// The user's own redemption.
  Future<InviteStatus> myStatus();
}

class CallableReferralService implements ReferralService {
  CallableReferralService(this._functions);
  final FirebaseFunctions _functions;

  @override
  Future<InviteInfo> myInvite({String? deviceId}) async {
    try {
      final res = await _functions.httpsCallable('getInviteCode').call<Object?>({'deviceId': ?deviceId});
      return InviteInfo.fromJson(res.data! as Map<Object?, Object?>);
    } on FirebaseFunctionsException catch (e) {
      throw ReferralException(_reason(e));
    }
  }

  @override
  Future<InviteStatus> redeem(String code, {required String deviceId}) async {
    try {
      final res = await _functions.httpsCallable('redeemInvite').call<Object?>({
        'code': code,
        'deviceId': deviceId,
      });
      final data = res.data;
      // Servers before the first-lesson rule rewarded at once.
      return data is Map ? InviteStatus.byName(data['status'] ?? 'rewarded') : InviteStatus.rewarded;
    } on FirebaseFunctionsException catch (e) {
      throw ReferralException(_reason(e));
    }
  }

  @override
  Future<InviteStatus> myStatus() async {
    try {
      final res = await _functions.httpsCallable('getInviteStatus').call<Object?>();
      final data = res.data;
      return data is Map ? InviteStatus.byName(data['status']) : InviteStatus.none;
    } on FirebaseFunctionsException catch (e) {
      throw ReferralException(_reason(e));
    }
  }

  static String _reason(FirebaseFunctionsException e) {
    if (e.code == 'unavailable' || e.code == 'deadline-exceeded') return 'offline';
    if (e.code == 'unauthenticated') return 'sign_in_required';
    return e.message ?? e.code;
  }
}

/// Null when Firebase is off or nobody is signed in.
final referralServiceProvider = Provider<ReferralService?>((ref) {
  final functions = ref.watch(functionsProvider);
  if (functions == null || ref.watch(currentUidProvider) == null) return null;
  return CallableReferralService(functions);
});

/// A random id for this installation, used only so one device cannot redeem
/// many invite codes. Not a hardware id; the server stores only its hash.
final installIdProvider = Provider<String>((ref) {
  const key = 'install.id';
  final prefs = ref.read(prefsProvider);
  final existing = prefs.getString(key);
  if (existing != null) return existing;
  final r = Random.secure();
  final id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  prefs.setString(key, id);
  return id;
});

/// Çenebaz on Google Play.
const dilmacPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.cenebaz.app';

/// [dilmacPlayStoreUrl] carrying [code] as an install referrer (for a later
/// automatic step; today the friend types the code).
String invitePlayLink(String code) => '$dilmacPlayStoreUrl&referrer=invite%3D$code';

/// Text shared with friends (share sheet): the code, the reward rule and
/// the Play link. The code is entered in Profil > Arkadaşını davet et.
String inviteShareText(InviteInfo info) =>
    'Çenebaz ile her gün birkaç dakika İngilizce çalışıyorum ve gerçekten işe yarıyor!\n'
    'Kısa dersler, konuşma pratiği, sınav hazırlığı; temel öğrenme ücretsiz.\n\n'
    'Davet kodum: ${info.code}\n'
    'Uygulamayı indir, Profil > Arkadaşını davet et bölümüne kodu gir ve ilk dersini bitir: '
    'ikimiz de ${info.rewardDays} gün Premium kazanalım.\n\n'
    '${invitePlayLink(info.code)}';
