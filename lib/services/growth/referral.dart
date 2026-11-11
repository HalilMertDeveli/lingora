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
    'mutual_invite' => 'Seni davet eden kişinin kodunu karşılıklı kullanamazsın.',
    'not_new_user' => 'Davet kodları yalnızca yeni hesaplarda (ilk 14 gün) kullanılabilir.',
    'sign_in_required' => 'Davet kodu kullanmak için önce Profil > Hesap bölümünden giriş yap.',
    'offline' => 'Sunucuya ulaşılamadı. İnternetini kontrol edip tekrar dene.',
    _ => 'Davet kodu şu an kullanılamadı. Biraz sonra tekrar dene.',
  };

  @override
  String toString() => 'ReferralException($reason)';
}

abstract class ReferralService {
  Future<InviteInfo> myInvite();

  /// Redeems [code]; Premium arrives through `entitlements/{uid}`.
  Future<void> redeem(String code, {required String deviceId});
}

class CallableReferralService implements ReferralService {
  CallableReferralService(this._functions);
  final FirebaseFunctions _functions;

  @override
  Future<InviteInfo> myInvite() async {
    try {
      final res = await _functions.httpsCallable('getInviteCode').call<Object?>();
      return InviteInfo.fromJson(res.data! as Map<Object?, Object?>);
    } on FirebaseFunctionsException catch (e) {
      throw ReferralException(_reason(e));
    }
  }

  @override
  Future<void> redeem(String code, {required String deviceId}) async {
    try {
      await _functions.httpsCallable('redeemInvite').call<Object?>({'code': code, 'deviceId': deviceId});
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

/// Text shared with friends. The code is entered in the app (Profil >
/// Arkadaşını davet et); the Play link carries it as an install referrer
/// for a later automatic step.
String inviteShareText(InviteInfo info) =>
    'Dilbaz ile İngilizce öğreniyorum: kısa dersler, can sistemi yok, temel öğrenme ücretsiz. '
    'Uygulamayı indir, Profil > Arkadaşını davet et bölümüne ${info.code} kodunu gir; '
    'ikimiz de ${info.rewardDays} gün Premium kazanalım! '
    'https://play.google.com/store/apps/details?id=com.lingora.lingora&referrer=invite%3D${info.code}';
