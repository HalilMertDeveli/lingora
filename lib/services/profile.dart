import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../data/progress.dart';
import 'firebase/firebase_providers.dart';
import 'league_remote.dart' show leagueDisplayName;
import 'showcase.dart';

/// The learner's own photo and display name (docs/firebase-backend.md,
/// "Profil").
///
/// - A guest keeps both only on this device (SharedPreferences).
/// - With an account they also go to `profiles/{uid}`, so they come back on
///   another phone and friends see them. The photo is a small JPEG stored
///   in the document itself: Cloud Storage needs the Blaze plan.

/// Side of the square avatar in pixels.
const avatarSize = 256;

/// Largest photo firestore.rules accept (validProfile).
const maxAvatarBytes = 60 * 1024;

/// Longest display name (validName in firestore.rules).
const maxNameLength = 24;

/// Why a picked image could not be used.
class AvatarException implements Exception {
  const AvatarException();

  String get message => 'Bu fotoğraf açılamadı. Başka bir fotoğraf dene.';
}

/// Crops [raw] (any format the image package reads) to a centred square,
/// shrinks it to [avatarSize] and encodes it as JPEG of at most
/// [maxAvatarBytes]. Throws [AvatarException] when it cannot be decoded.
Uint8List processAvatar(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) throw const AvatarException();
  // Phone cameras store the rotation in EXIF; JPEG output drops it.
  final upright = img.bakeOrientation(decoded);
  final square = img.copyResizeCropSquare(
    upright,
    size: avatarSize,
    interpolation: img.Interpolation.average,
  );
  for (var quality = 85; ; quality -= 15) {
    final jpg = img.encodeJpg(square, quality: quality);
    if (jpg.length <= maxAvatarBytes || quality <= 25) {
      if (jpg.length > maxAvatarBytes) throw const AvatarException();
      return jpg;
    }
  }
}

/// [processAvatar] off the UI thread.
Future<Uint8List> processAvatarAsync(Uint8List raw) => compute(processAvatar, raw);

/// Trims and collapses spaces and cuts the name to [maxNameLength] UTF-16
/// units without splitting a character; null when nothing is left.
String? cleanDisplayName(String? raw) {
  final t = raw?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
  if (t.isEmpty) return null;
  final out = StringBuffer();
  for (final c in t.characters) {
    if (out.length + c.length > maxNameLength) break;
    out.write(c);
  }
  final s = out.toString().trimRight();
  return s.isEmpty ? null : s;
}

/// True for bytes that start like a JPEG (FF D8 FF), as the rules check.
bool looksLikeJpeg(Uint8List b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

@immutable
class ProfileData {
  const ProfileData({this.name, this.photo, this.updatedAt = 0, this.owner, this.showcase});

  /// A friend's Mağaza showcase (read from Firestore only; the own one
  /// comes from the wallet, see lib/services/showcase.dart).
  final Showcase? showcase;

  /// Chosen display name; null uses the account's name.
  final String? name;

  /// JPEG avatar; null shows the mascot.
  final Uint8List? photo;

  /// Milliseconds of the last change on any device (0: never changed).
  final int updatedAt;

  /// Account uid the local copy belongs to; null for a guest.
  final String? owner;

  bool get isEmpty => name == null && photo == null;

  ProfileData copyWith({
    String? name,
    Uint8List? photo,
    bool clearName = false,
    bool clearPhoto = false,
    int? updatedAt,
    String? owner,
  }) => ProfileData(
    name: clearName ? null : (name ?? this.name),
    photo: clearPhoto ? null : (photo ?? this.photo),
    updatedAt: updatedAt ?? this.updatedAt,
    owner: owner ?? this.owner,
    showcase: showcase,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'photo': photo == null ? null : base64Encode(photo!),
    'updatedAt': updatedAt,
    'owner': owner,
  };

  factory ProfileData.fromJson(Map<String, dynamic> j) {
    final p = j['photo'];
    return ProfileData(
      name: cleanDisplayName(j['name'] as String?),
      photo: p is String && p.isNotEmpty ? base64Decode(p) : null,
      updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      owner: j['owner'] as String?,
    );
  }

  /// `profiles/{uid}` as read from Firestore; null when it is malformed.
  static ProfileData? fromFirestore(Map<String, dynamic>? d, String uid) {
    if (d == null) return null;
    final photo = d['photo'];
    return ProfileData(
      name: cleanDisplayName(d['name'] as String?),
      photo: photo is Blob ? photo.bytes : null,
      updatedAt: (d['clientUpdatedAt'] as num?)?.toInt() ?? 0,
      owner: uid,
      showcase: Showcase.fromMap(d['showcase']),
    );
  }

  Map<String, Object?> toFirestore() => {
    'name': name,
    'photo': photo == null ? null : Blob(photo!),
    'clientUpdatedAt': updatedAt,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/// Reads and writes `profiles/{uid}` (mockable in tests).
abstract class ProfileApi {
  Future<ProfileData?> fetch(String uid);

  Future<void> save(String uid, ProfileData profile);

  /// A friend's profile, live. Null when there is none or it may not be read.
  Stream<ProfileData?> watch(String uid);
}

class FirestoreProfileApi implements ProfileApi {
  FirestoreProfileApi(this._db);
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _db.collection('profiles').doc(uid);

  @override
  Future<ProfileData?> fetch(String uid) async =>
      ProfileData.fromFirestore((await _doc(uid).get()).data(), uid);

  @override
  Future<void> save(String uid, ProfileData profile) =>
      _doc(uid).set(profile.toFirestore(), SetOptions(merge: true));

  @override
  Stream<ProfileData?> watch(String uid) =>
      _doc(uid).snapshots().map((s) => ProfileData.fromFirestore(s.data(), uid));
}

/// Null when Firebase is off.
final profileApiProvider = Provider<ProfileApi?>((ref) {
  final db = ref.watch(firestoreProvider);
  return db == null ? null : FirestoreProfileApi(db);
});

/// Uid of a signed-in account (not a guest), or null.
final accountUidProvider = Provider<String?>((ref) {
  final user = ref.watch(authStateProvider).value;
  return user == null || user.isAnonymous ? null : user.uid;
});

class ProfileNotifier extends Notifier<ProfileData> {
  static const key = 'profile_v1';

  @override
  ProfileData build() {
    ref.listen(accountUidProvider, (_, uid) {
      if (uid != null) unawaited(_syncWith(uid));
    }, fireImmediately: true);
    final raw = ref.read(prefsProvider).getString(key);
    if (raw == null) return const ProfileData();
    try {
      return ProfileData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ProfileData();
    }
  }

  int _now() => ref.read(clockProvider)().millisecondsSinceEpoch;

  void _store(ProfileData p) {
    state = p;
    unawaited(ref.read(prefsProvider).setString(key, jsonEncode(p.toJson())));
  }

  /// Signing in: the newer of the device copy and `profiles/{uid}` wins. A
  /// copy left by another account on this phone is dropped.
  Future<void> _syncWith(String uid) async {
    final api = ref.read(profileApiProvider);
    if (api == null) return;
    // Read the state after build() has returned.
    await Future<void>.value();
    if (!ref.mounted) return;
    var local = state;
    if (local.owner != null && local.owner != uid) local = const ProfileData();
    ProfileData? remote;
    try {
      remote = await api.fetch(uid);
    } catch (e) {
      debugPrint('Profile fetch failed: $e');
      return;
    }
    if (!ref.mounted || ref.read(accountUidProvider) != uid) return;
    if (remote != null && (remote.updatedAt >= local.updatedAt || local.isEmpty)) {
      _store(remote.copyWith(owner: uid));
    } else {
      _store(local.copyWith(owner: uid));
      if (!local.isEmpty) await _upload(uid);
    }
  }

  Future<void> _upload(String uid) async {
    try {
      await ref.read(profileApiProvider)?.save(uid, state);
    } catch (e) {
      // Best effort: the next change or sign-in uploads it again.
      debugPrint('Profile upload failed: $e');
    }
  }

  Future<void> _changed(ProfileData p) async {
    final uid = ref.read(accountUidProvider);
    _store(p.copyWith(updatedAt: _now(), owner: uid));
    if (uid != null) await _upload(uid);
  }

  /// Sets the display name; an empty one goes back to the account's name.
  Future<void> setName(String? raw) {
    final name = cleanDisplayName(raw);
    return _changed(name == null ? state.copyWith(clearName: true) : state.copyWith(name: name));
  }

  /// Stores an already processed JPEG (see [processAvatar]).
  Future<void> setPhoto(Uint8List jpeg) => _changed(state.copyWith(photo: jpeg));

  Future<void> removePhoto() => _changed(state.copyWith(clearPhoto: true));
}

final profileProvider = NotifierProvider<ProfileNotifier, ProfileData>(ProfileNotifier.new);

/// The name shown to friends and the league: the chosen one, else the
/// account's first name.
final myDisplayNameProvider = Provider<String>((ref) {
  final chosen = ref.watch(profileProvider.select((p) => p.name));
  return chosen ?? leagueDisplayName(ref.watch(authStateProvider).value?.displayName);
});

/// A friend's photo and name, live. Null while loading, without Firebase,
/// or when the friend has no profile.
final friendProfileProvider = StreamProvider.family<ProfileData?, String>((ref, uid) {
  final api = ref.watch(profileApiProvider);
  if (api == null || ref.watch(accountUidProvider) == null) return Stream.value(null);
  return api.watch(uid).handleError((Object _) {});
});
