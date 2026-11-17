import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Phone numbers for "Rehberden bul" (docs/arkadaslar.md).
///
/// Raw numbers never leave the phone. The app writes and looks up only
/// `phoneIndex/{hash}` where hash = sha256(salt + E.164 number), lower-case
/// hex. firestore.rules recomputes the same hash from the verified
/// `phone_number` of the Firebase Auth token, so nobody can publish a
/// number that is not theirs.

/// App-specific prefix ("salt") of every phone hash. Changing it orphans
/// every phoneIndex entry; keep it in sync with firestore.rules.
const phoneHashSalt = 'dilmac-rehber-v1:';

final _e164 = RegExp(r'^\+[1-9]\d{7,14}$');

/// [raw] as an E.164 number ("+905321234567"), or null when it cannot be one.
///
/// Numbers without a country code are taken as Turkish (+90): "0532 123 45 67",
/// "532 123 45 67" and "90 532 123 45 67" all become +905321234567. Other
/// local formats (short codes, extensions) are dropped.
String? normalizePhone(String raw, {String defaultCountryCode = '90'}) {
  var s = raw.trim();
  // Extensions ("… ext. 12", "…;12", "…,12") are not part of the number.
  s = s.split(RegExp(r'(?:ext\.?|x|#|;|,)', caseSensitive: false)).first;
  final plus = s.startsWith('+');
  var digits = s.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  String e164;
  if (plus) {
    e164 = '+$digits';
  } else if (digits.startsWith('00')) {
    e164 = '+${digits.substring(2)}';
  } else if (defaultCountryCode == '90') {
    if (digits.length == 12 && digits.startsWith('90')) {
      e164 = '+$digits';
    } else if (digits.length == 11 && digits.startsWith('0')) {
      e164 = '+90${digits.substring(1)}';
    } else if (digits.length == 10 && !digits.startsWith('0')) {
      e164 = '+90$digits';
    } else {
      return null;
    }
  } else {
    if (digits.startsWith('0')) digits = digits.substring(1);
    e164 = '+$defaultCountryCode$digits';
  }
  // Turkish numbers are always +90 and 10 more digits.
  if (e164.startsWith('+90') && e164.length != 13) return null;
  return _e164.hasMatch(e164) ? e164 : null;
}

/// The phoneIndex document id of an E.164 number.
String phoneHash(String e164) => sha256.convert(utf8.encode('$phoneHashSalt$e164')).toString();
