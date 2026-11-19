import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/emoji_compat.dart';
import '../data/progress.dart';
import 'contacts/phone_numbers.dart';
import 'firebase/firebase_providers.dart';
import 'league_remote.dart' show leagueDisplayName, legacyDefaultName, shownName;
import 'profile.dart' show myDisplayNameProvider;

/// Friends and the shared daily streak. Everything goes straight to
/// Firestore; firestore.rules check every write, so this works without Cloud
/// Functions (docs/firebase-backend.md, "Arkadaşlar").
///
/// - `friendCodes/{code}`: a user's 8-character code {uid, name, avatar}.
/// - `friendships/{a}_{b}`: two friends, the Turkish day each last reached
///   the daily goal (`done`) and the shared streak.
/// - `friendships/{a}_{b}/cheers/{from}_{day}_{kind}`: preset cheers.

/// Turkish day number (UTC+3, no daylight saving), the same as `trDay()` in
/// firestore.rules. The server checks it against its own clock.
int friendDay(DateTime now) =>
    (now.toUtc().millisecondsSinceEpoch + 3 * 3600 * 1000) ~/ Duration.millisecondsPerDay;

/// Letters and digits that cannot be mixed up (no 0/O, 1/I).
const friendCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const friendCodeLength = 8;
final _codePattern = RegExp('^[$friendCodeAlphabet]{$friendCodeLength}\$');

String newFriendCode([Random? random]) {
  final r = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < friendCodeLength; i++)
      friendCodeAlphabet.codeUnitAt(r.nextInt(friendCodeAlphabet.length)),
  ]);
}

/// What the user typed, upper-cased and without spaces or dashes; null when
/// it cannot be a code.
String? normalizeFriendCode(String raw) {
  final c = raw.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
  return _codePattern.hasMatch(c) ? c : null;
}

const _avatars = ['🦊', '🐢', '🦉', '🐼', '🐝', '🐬', '🦁', '🐧', '🐙', '🦜'];

/// A stable animal for a uid, so friends are easy to tell apart.
String friendAvatar(String uid) =>
    legacyEmoji(_avatars[uid.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0xffff) % _avatars.length]);

String pairIdOf(String a, String b) => a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

/// Preset cheers: no free text, so nothing to moderate.
enum CheerKind {
  tebrik('🎉', 'Tebrikler!'),
  destek('💪', 'Yanındayım'),
  hadi('⏰', 'Hadi, bugün sen de!'),
  harika('⭐', 'Harika gidiyorsun');

  const CheerKind(this.emoji, this.label);
  final String emoji;
  final String label;
}

class Cheer {
  const Cheer({required this.from, required this.to, required this.kind, required this.day});
  final String from;
  final String to;
  final CheerKind kind;
  final int day;
}

/// One friendship as the signed-in user sees it.
class Friendship {
  const Friendship({
    required this.pairId,
    required this.friendUid,
    required this.name,
    required this.avatar,
    required this.myDay,
    required this.friendDay,
    required this.streak,
    required this.best,
    required this.streakDay,
    this.myName,
  });

  /// Null when the document is not a friendship of [me].
  static Friendship? fromMap(String pairId, Map<String, dynamic> d, String me) {
    final members = (d['members'] as List?)?.cast<String>() ?? const [];
    if (members.length != 2 || !members.contains(me)) return null;
    final other = members[0] == me ? members[1] : members[0];
    final names = Map<String, dynamic>.from(d['names'] as Map? ?? const {});
    final avatars = Map<String, dynamic>.from(d['avatars'] as Map? ?? const {});
    final done = Map<String, dynamic>.from(d['done'] as Map? ?? const {});
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    return Friendship(
      pairId: pairId,
      friendUid: other,
      name: shownName(names[other] as String? ?? 'Arkadaş'),
      avatar: avatars[other] as String? ?? '⭐',
      myDay: n(done[me]),
      friendDay: n(done[other]),
      streak: n(d['streak']),
      best: n(d['best']),
      streakDay: n(d['streakDay']),
      myName: names[me] as String?,
    );
  }

  final String pairId;
  final String friendUid;
  final String name;
  final String avatar;

  /// Turkish day the user / the friend last reached the daily goal.
  final int myDay;
  final int friendDay;

  /// Stored streak and the day it last grew.
  final int streak;
  final int best;
  final int streakDay;

  /// The user's own name as stored in this friendship (shown to the friend).
  final String? myName;

  bool meDone(int today) => myDay == today;
  bool friendDone(int today) => friendDay == today;

  /// The streak as shown today: still alive while today can extend it.
  int streakOn(int today) => streakDay >= today - 1 ? streak : 0;
}

/// The update that marks [me]'s daily goal on [day], growing the shared
/// streak when the friend already made it today (firestore.rules,
/// validStreak). Null when there is nothing to change.
Map<String, Object>? goalUpdate(Map<String, dynamic> d, String me, int day) {
  final done = Map<String, dynamic>.from(d['done'] as Map? ?? const {});
  if (((done[me] as num?)?.toInt() ?? 0) >= day) return null;
  final members = (d['members'] as List).cast<String>();
  final other = members[0] == me ? members[1] : members[0];
  final update = <String, Object>{'done.$me': day};
  final streakDay = (d['streakDay'] as num?)?.toInt() ?? 0;
  if ((done[other] as num?)?.toInt() == day && streakDay != day) {
    final next = streakDay == day - 1 ? ((d['streak'] as num?)?.toInt() ?? 0) + 1 : 1;
    update['streak'] = next;
    update['streakDay'] = day;
    update['best'] = max((d['best'] as num?)?.toInt() ?? 0, next);
  }
  return update;
}

/// A friend request (`friendRequests/{from}_{to}`), sent from the phone
/// book. [name] and [avatar] are the sender's, copied into the friendship
/// when the receiver accepts.
class FriendRequest {
  const FriendRequest({required this.from, required this.to, required this.name, required this.avatar});

  static FriendRequest? fromMap(Map<String, dynamic> d) {
    final from = d['from'], to = d['to'];
    if (from is! String || to is! String) return null;
    return FriendRequest(
      from: from,
      to: to,
      name: shownName(d['name'] as String? ?? 'Arkadaş'),
      avatar: d['avatar'] as String? ?? '⭐',
    );
  }

  final String from;
  final String to;
  final String name;
  final String avatar;

  String get id => '${from}_$to';
}

/// What sending a request did.
enum RequestResult {
  /// Waiting for the other person.
  sent,

  /// They had already asked us: accepted, you are friends now.
  friends,
}

/// Why adding a friend failed, with the Turkish message for the screen.
class FriendException implements Exception {
  const FriendException(this.reason);
  final String reason;

  String get message => switch (reason) {
    'format' => 'Kod 8 karakter olmalı (harf ve rakam).',
    'notFound' => 'Bu kodla bir arkadaş bulunamadı. Kodu kontrol et.',
    'self' => 'Bu senin kendi kodun.',
    'already' => 'Bu kişiyle zaten arkadaşsınız.',
    'noPhone' => 'Bu seçenek için telefon numaranla giriş yapmış olman gerekir.',
    _ => 'Şu an bağlanılamadı. İnternetini kontrol edip yeniden dene.',
  };

  @override
  String toString() => 'FriendException($reason)';
}

/// What the friends screen needs (mockable in tests).
abstract class FriendsApi {
  String get uid;

  /// The name friends see (Profil > ad, or the account's first name).
  String get myName;

  /// The user's code, created on first use.
  Future<String> myCode();

  /// Adds the owner of [code] as a friend; returns their name.
  Future<String> addFriend(String code);

  Stream<List<Friendship>> friendships();

  /// Today's cheers in one friendship, both directions.
  Stream<List<Cheer>> cheers(String pairId, int day);

  Future<void> sendCheer(Friendship f, CheerKind kind, int day);

  Future<void> remove(String pairId);

  /// Marks today's daily goal in every friendship that does not have it yet.
  Future<void> markGoal(int day);

  /// Writes [myName] into the user's code and, with [friendships], into
  /// every friendship that still shows an older name.
  Future<void> syncMyName({bool friendships = true});

  // ---- Friend requests (phone book) ----

  /// Asks [toUid] to be friends. When they already asked us, accepts theirs.
  Future<RequestResult> sendRequest(String toUid);

  /// Requests waiting for the user's answer.
  Stream<List<FriendRequest>> incomingRequests();

  /// Requests the user sent that are not answered yet.
  Stream<List<FriendRequest>> outgoingRequests();

  /// Makes the sender a friend and removes the request; returns the pair id.
  Future<String> acceptRequest(FriendRequest r);

  /// Declines an incoming or withdraws an outgoing request.
  Future<void> deleteRequest(FriendRequest r);

  // ---- Discoverability by phone number (opt-in) ----

  /// The verified number of the account (Firebase phone sign-in), or null.
  String? get verifiedPhone;

  /// Whether others can find the user by their number; null without a
  /// verified number.
  Future<bool?> discoverable();

  /// Publishes or removes the user's phone hash.
  Future<void> setDiscoverable(bool on);

  /// The uids behind those phone hashes that are discoverable, by hash.
  /// One `get` per hash: the index cannot be listed.
  Future<Map<String, String>> lookupPhones(Iterable<String> hashes);
}

class FirestoreFriendsApi implements FriendsApi {
  FirestoreFriendsApi(this._db, {required this.uid, required this.name, String? avatar, this.verifiedPhone})
    : avatar = avatar ?? friendAvatar(uid);
  final FirebaseFirestore _db;
  @override
  final String uid;
  final String name;
  final String avatar;
  @override
  final String? verifiedPhone;

  @override
  String get myName => name;

  CollectionReference<Map<String, dynamic>> get _codes => _db.collection('friendCodes');

  @override
  Future<void> syncMyName({bool friendships = true}) async {
    final mine = await _codes.where('uid', isEqualTo: uid).get();
    for (final d in mine.docs) {
      if (d.data()['name'] != name || d.data()['avatar'] != avatar) await d.reference.set(_codeDoc());
    }
    if (!friendships) return;
    final pairs = await _pairs.where('members', arrayContains: uid).get();
    for (final p in pairs.docs) {
      final names = p.data()['names'];
      if (names is Map && names[uid] != name) {
        // Only the user's own entry; firestore.rules (validOwnChange) allow it.
        await p.reference.update({'names.$uid': name});
      }
    }
  }

  CollectionReference<Map<String, dynamic>> get _pairs => _db.collection('friendships');
  CollectionReference<Map<String, dynamic>> get _requests => _db.collection('friendRequests');
  CollectionReference<Map<String, dynamic>> get _phones => _db.collection('phoneIndex');

  @override
  Future<String> myCode() async {
    final mine = await _codes.where('uid', isEqualTo: uid).limit(1).get();
    if (mine.docs.isNotEmpty) {
      final d = mine.docs.first;
      if (d.data()['name'] != name || d.data()['avatar'] != avatar) {
        await d.reference.set(_codeDoc());
      }
      return d.id;
    }
    // A taken code is refused by the rules (it would be an update of
    // someone else's code); 32^8 codes make a second clash unlikely.
    for (var attempt = 0; ; attempt++) {
      final code = newFriendCode();
      try {
        await _codes.doc(code).set(_codeDoc());
        return code;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied' || attempt >= 4) rethrow;
      }
    }
  }

  Map<String, Object> _codeDoc() => {
    'uid': uid,
    'name': name,
    'avatar': avatar,
    'createdAt': FieldValue.serverTimestamp(),
  };

  @override
  Future<String> addFriend(String raw) async {
    final code = normalizeFriendCode(raw);
    if (code == null) throw const FriendException('format');
    final DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _codes.doc(code).get();
    } on FirebaseException {
      throw const FriendException('offline');
    }
    final owner = snap.data();
    if (owner == null) throw const FriendException('notFound');
    final other = owner['uid'] as String;
    if (other == uid) throw const FriendException('self');
    try {
      if (await _isFriend(other)) throw const FriendException('already');
      await _pairs
          .doc(pairIdOf(uid, other))
          .set(_pairDoc(other, code, owner['name'] as String? ?? '', owner['avatar'] as String? ?? ''));
    } on FirebaseException {
      throw const FriendException('offline');
    }
    await _dropRequestsWith(other);
    return owner['name'] as String? ?? 'Arkadaşın';
  }

  /// Pending requests between the user and [other], in either direction.
  Future<List<DocumentReference<Map<String, dynamic>>>> _requestsWith(String other) async {
    final res = await Future.wait([
      _requests.where('to', isEqualTo: uid).where('from', isEqualTo: other).get(),
      _requests.where('from', isEqualTo: uid).where('to', isEqualTo: other).get(),
    ]);
    return [for (final s in res) ...s.docs.map((d) => d.reference)];
  }

  /// Best effort: once friends, requests between the two are moot.
  Future<void> _dropRequestsWith(String other) async {
    try {
      for (final r in await _requestsWith(other)) {
        await r.delete();
      }
    } on FirebaseException {
      // Left for the friends screen, which hides requests from friends.
    }
  }

  Map<String, Object> _pairDoc(String other, String code, String otherName, String otherAvatar) => {
    'members': [uid, other]..sort(),
    'code': code,
    'names': {uid: name, other: otherName},
    'avatars': {uid: avatar, other: otherAvatar},
    'done': <String, Object>{},
    'streak': 0,
    'best': 0,
    'streakDay': 0,
    'createdAt': FieldValue.serverTimestamp(),
  };

  Future<bool> _isFriend(String other) async =>
      (await _pairs.where('members', arrayContains: uid).get()).docs.any((d) => d.id == pairIdOf(uid, other));

  @override
  Future<RequestResult> sendRequest(String toUid) async {
    if (toUid == uid) throw const FriendException('self');
    try {
      if (await _isFriend(toUid)) throw const FriendException('already');
      final theirs = await _requests.where('to', isEqualTo: uid).where('from', isEqualTo: toUid).get();
      if (theirs.docs.isNotEmpty) {
        final r = FriendRequest.fromMap(theirs.docs.first.data());
        if (r != null) {
          await acceptRequest(r);
          return RequestResult.friends;
        }
      }
      await _requests.doc('${uid}_$toUid').set({
        'from': uid,
        'to': toUid,
        'name': name,
        'avatar': avatar,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return RequestResult.sent;
    } on FirebaseException {
      throw const FriendException('offline');
    }
  }

  Stream<List<FriendRequest>> _requestQuery(String field) => _requests
      .where(field, isEqualTo: uid)
      .snapshots()
      .map((s) => [for (final d in s.docs) ?FriendRequest.fromMap(d.data())]);

  @override
  Stream<List<FriendRequest>> incomingRequests() => _requestQuery('to');

  @override
  Stream<List<FriendRequest>> outgoingRequests() => _requestQuery('from');

  @override
  Future<String> acceptRequest(FriendRequest r) async {
    final pairId = pairIdOf(r.from, r.to);
    try {
      final batch = _db.batch()
        ..set(_pairs.doc(pairId), _pairDoc(r.from, '', r.name, r.avatar))
        ..delete(_requests.doc(r.id));
      await batch.commit();
    } on FirebaseException {
      // Already friends (e.g. they added our code meanwhile): just tidy up.
      if (!await _isFriend(r.from)) throw const FriendException('offline');
      await _requests.doc(r.id).delete();
    }
    await _dropRequestsWith(r.from);
    return pairId;
  }

  @override
  Future<void> deleteRequest(FriendRequest r) => _requests.doc(r.id).delete();

  String? get _myPhoneHash => verifiedPhone == null ? null : phoneHash(verifiedPhone!);

  @override
  Future<bool?> discoverable() async {
    final h = _myPhoneHash;
    if (h == null) return null;
    final d = await _phones.doc(h).get();
    return d.data()?['uid'] == uid;
  }

  @override
  Future<void> setDiscoverable(bool on) async {
    final h = _myPhoneHash;
    if (h == null) throw const FriendException('noPhone');
    if (on) {
      await _phones.doc(h).set({'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
    } else {
      final d = await _phones.doc(h).get();
      if (d.exists) await d.reference.delete();
    }
  }

  @override
  Future<Map<String, String>> lookupPhones(Iterable<String> hashes) async {
    final out = <String, String>{};
    final list = hashes.toSet().toList();
    // A few gets at a time: each is one document read.
    for (var i = 0; i < list.length; i += 20) {
      final chunk = list.sublist(i, min(i + 20, list.length));
      final snaps = await Future.wait(chunk.map((h) => _phones.doc(h).get()));
      for (final s in snaps) {
        final owner = s.data()?['uid'];
        if (owner is String && owner != uid) out[s.id] = owner;
      }
    }
    return out;
  }

  @override
  Stream<List<Friendship>> friendships() => _pairs
      .where('members', arrayContains: uid)
      .snapshots()
      .map((s) => [for (final d in s.docs) ?Friendship.fromMap(d.id, d.data(), uid)]);

  @override
  Stream<List<Cheer>> cheers(String pairId, int day) => _pairs
      .doc(pairId)
      .collection('cheers')
      .where('day', isEqualTo: day)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            if (CheerKind.values.asNameMap()[d.data()['kind']] case final kind?)
              Cheer(
                from: d.data()['from'] as String? ?? '',
                to: d.data()['to'] as String? ?? '',
                kind: kind,
                day: day,
              ),
        ],
      );

  @override
  Future<void> sendCheer(Friendship f, CheerKind kind, int day) =>
      _pairs.doc(f.pairId).collection('cheers').doc('${uid}_${day}_${kind.name}').set({
        'from': uid,
        'to': f.friendUid,
        'kind': kind.name,
        'day': day,
        'createdAt': FieldValue.serverTimestamp(),
      });

  /// Removes the friendship and its cheers, so a later friendship of the
  /// same two people starts clean (a cheer cannot be overwritten).
  @override
  Future<void> remove(String pairId) async {
    final cheers = await _pairs.doc(pairId).collection('cheers').get();
    for (final c in cheers.docs) {
      await c.reference.delete();
    }
    await _pairs.doc(pairId).delete();
  }

  @override
  Future<void> markGoal(int day) async {
    final pairs = await _pairs.where('members', arrayContains: uid).get();
    for (final p in pairs.docs) {
      if (goalUpdate(p.data(), uid, day) == null) continue;
      // A transaction, so a friend marking at the same moment is seen and
      // the streak grows exactly once.
      await _db.runTransaction((tx) async {
        final fresh = await tx.get(p.reference);
        final data = fresh.data();
        if (data == null) return;
        final update = goalUpdate(data, uid, day);
        if (update != null) tx.update(p.reference, update);
      });
    }
  }
}

/// Null when Firebase is off or the user is a guest: friends need a real
/// account (an anonymous uid is lost with the phone).
final friendsApiProvider = Provider<FriendsApi?>((ref) {
  final db = ref.watch(firestoreProvider);
  final user = ref.watch(authStateProvider).value;
  if (db == null || user == null || user.isAnonymous) return null;
  return FirestoreFriendsApi(
    db,
    uid: user.uid,
    name: ref.watch(myDisplayNameProvider),
    verifiedPhone: user.phoneNumber,
  );
});

/// The user's friendships, live. Null when friends are not available.
final friendshipsProvider = StreamProvider<List<Friendship>?>((ref) {
  final api = ref.watch(friendsApiProvider);
  if (api == null) return Stream.value(null);
  return api.friendships();
});

/// Today's cheers in one friendship.
final cheersProvider = StreamProvider.family<List<Cheer>, String>((ref, pairId) {
  final api = ref.watch(friendsApiProvider);
  if (api == null) return Stream.value(const []);
  return api.cheers(pairId, friendDay(ref.read(clockProvider)()));
});

/// Marks the daily goal in every friendship as soon as today's XP reaches
/// it. Kept alive from the app root; does nothing without friends.
final friendGoalSyncProvider = Provider<void>((ref) {
  final api = ref.watch(friendsApiProvider);
  if (api == null) return;
  final now = ref.read(clockProvider);
  final reached = ref.watch(progressProvider.select((p) => p.xpOn(now()) >= p.dailyGoal));
  final friends = ref.watch(friendshipsProvider).value;
  if (!reached || friends == null) return;
  final today = friendDay(now());
  if (friends.every((f) => f.meDone(today))) return;
  // Best effort: a failure (offline, a clock off near midnight) is retried
  // the next time progress or the friend list changes.
  unawaited(api.markGoal(today).catchError((_) {}));
});

/// The fallback name of an account without a chosen or Google name.
final defaultFriendName = leagueDisplayName(null);

/// True when friends would see only the generic name: ask for a name first.
bool isDefaultFriendName(String name) =>
    name == defaultFriendName || name == legacyDefaultName || name == 'Arkadaş';

/// Keeps the name friends see up to date: after the user renames
/// themselves in Profil, their code and every friendship get the new name
/// (friends also read it live from profiles/{uid}). Kept alive from the app
/// root; does nothing without friends or a code.
final friendNameSyncProvider = Provider<void>((ref) {
  final api = ref.watch(friendsApiProvider);
  if (api == null) return;
  final stale = ref.watch(
    friendshipsProvider.select(
      (a) => a.value?.any((f) => f.myName != null && f.myName != api.myName) ?? false,
    ),
  );
  // Best effort: retried when the name or the friend list changes.
  unawaited(api.syncMyName(friendships: stale).catchError((_) {}));
});

/// Friend requests waiting for the user's answer, live. Requests from
/// people who are already friends are hidden.
final incomingRequestsProvider = StreamProvider<List<FriendRequest>>((ref) {
  final api = ref.watch(friendsApiProvider);
  if (api == null) return Stream.value(const []);
  return api.incomingRequests();
});

/// Requests the user sent that are still open, live.
final outgoingRequestsProvider = StreamProvider<List<FriendRequest>>((ref) {
  final api = ref.watch(friendsApiProvider);
  if (api == null) return Stream.value(const []);
  return api.outgoingRequests();
});
