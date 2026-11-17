/// Kurum lisansı ve sınıflar, without Cloud Functions (Spark plan).
///
/// Everything goes straight to Firestore and firestore.rules check every
/// write (section "Kurum lisansı ve sınıflar", docs/kurumlar.md):
///
/// - `licenseCodes/{code}`: one seat (12 characters), created by the
///   operator with functions/scripts/license_codes.mjs. Claimed once.
/// - `licenses/{uid}`: the user's org license; Premium while it lasts.
/// - `classes/{code}`: a teacher's class; the doc id is the 8-character
///   join code. Only teachers with an active teacher seat can create one.
/// - `classes/{code}/members/{uid}`: the student's progress summary
///   (streak, units, lessons, weekly XP, top mistake kinds), written by the
///   student's own app. No e-mail, phone, notes or diary.
/// - `classLinks/{uid}`: the classes the user joined.
library;

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/course_repository.dart';
import '../data/league.dart' show weekStart;
import '../data/progress.dart';
import '../models/course.dart';
import '../services/firebase/firebase_providers.dart';

/// Letters and digits that cannot be mixed up (no 0/O, 1/I); the same set
/// as friend codes and `[A-HJ-NP-Z2-9]` in firestore.rules.
const kurumAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const licenseCodeLength = 12;
const classCodeLength = 8;

/// At most this many classes per student (firestore.rules allows 5 links).
const maxClassesPerStudent = 5;

String _randomCode(int length, Random? random) {
  final r = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < length; i++) kurumAlphabet.codeUnitAt(r.nextInt(kurumAlphabet.length)),
  ]);
}

String newClassCode([Random? random]) => _randomCode(classCodeLength, random);

String? _normalize(String raw, int length) {
  final c = raw.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
  return RegExp('^[$kurumAlphabet]{$length}\$').hasMatch(c) ? c : null;
}

/// What the user typed (spaces and dashes allowed, any case); null when it
/// cannot be a seat code.
String? normalizeLicenseCode(String raw) => _normalize(raw, licenseCodeLength);

String? normalizeClassCode(String raw) => _normalize(raw, classCodeLength);

/// `ABCD-EFGH-JKLM`, easier to read out and type.
String formatLicenseCode(String code) => code.length == licenseCodeLength
    ? '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8)}'
    : code;

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

enum LicenseRole {
  student('Öğrenci'),
  teacher('Öğretmen');

  const LicenseRole(this.label);
  final String label;

  static LicenseRole parse(Object? v) => v == 'teacher' ? teacher : student;
}

class OrgLicense {
  const OrgLicense({required this.code, required this.org, required this.role, required this.expiresAt});

  final String code;
  final String org;
  final LicenseRole role;
  final DateTime expiresAt;

  bool activeAt(DateTime now) => expiresAt.isAfter(now);
  bool get isTeacher => role == LicenseRole.teacher;
}

class ClassRoom {
  const ClassRoom({
    required this.code,
    required this.name,
    required this.teacherName,
    required this.org,
    required this.open,
    required this.ownerUid,
  });

  final String code;
  final String name;
  final String teacherName;
  final String org;

  /// Whether new students may join with the code.
  final bool open;
  final String ownerUid;

  static ClassRoom fromDoc(String code, Map<String, Object?> d) => ClassRoom(
    code: code,
    name: d['name'] as String? ?? '',
    teacherName: d['teacherName'] as String? ?? '',
    org: d['org'] as String? ?? '',
    open: d['open'] == true,
    ownerUid: d['ownerUid'] as String? ?? '',
  );
}

/// The summary a student's app shares with the teacher. Exactly the fields
/// firestore.rules allow in `classes/{code}/members/{uid}`.
class ClassStats {
  const ClassStats({
    required this.streak,
    required this.lessonsDone,
    required this.unitsDone,
    required this.weekXp,
    required this.week,
    this.topErrors = const [],
  });

  final int streak;
  final int lessonsDone;
  final int unitsDone;
  final int weekXp;

  /// Monday of the week [weekXp] belongs to, `YYYY-MM-DD`.
  final String week;

  /// [TrErrorCategory] names, most frequent first (at most 3).
  final List<String> topErrors;

  Map<String, Object?> toJson() => {
    'streak': streak.clamp(0, 10000),
    'lessonsDone': lessonsDone.clamp(0, 100000),
    'unitsDone': unitsDone.clamp(0, 10000),
    'weekXp': weekXp.clamp(0, 1000000),
    'week': week,
    'topErrors': topErrors.take(3).toList(),
  };

  static ClassStats fromJson(Map<String, Object?> j) => ClassStats(
    streak: (j['streak'] as num?)?.toInt() ?? 0,
    lessonsDone: (j['lessonsDone'] as num?)?.toInt() ?? 0,
    unitsDone: (j['unitsDone'] as num?)?.toInt() ?? 0,
    weekXp: (j['weekXp'] as num?)?.toInt() ?? 0,
    week: j['week'] as String? ?? '',
    topErrors: [for (final e in (j['topErrors'] as List? ?? const [])) '$e'],
  );

  /// This week's XP as seen on [now]: a summary from an older week counts 0.
  int weekXpAt(DateTime now) => week == _day(weekStart(now)) ? weekXp : 0;

  @override
  bool operator ==(Object other) =>
      other is ClassStats &&
      other.streak == streak &&
      other.lessonsDone == lessonsDone &&
      other.unitsDone == unitsDone &&
      other.weekXp == weekXp &&
      other.week == week &&
      other.topErrors.join(',') == topErrors.join(',');

  @override
  int get hashCode => Object.hash(streak, lessonsDone, unitsDone, weekXp, week, topErrors.join(','));
}

/// Units of [course] whose every node is done.
int unitsDoneIn(Progress p, Course? course) {
  if (course == null) return 0;
  var n = 0;
  for (final u in course.units) {
    if (u.nodes.isNotEmpty && u.nodes.every((node) => p.isDone(node.id))) n++;
  }
  return n;
}

ClassStats classStatsOf(Progress p, Course? course, DateTime now) {
  final monday = weekStart(now);
  return ClassStats(
    streak: p.streakAt(now),
    lessonsDone: p.lessonsDone,
    unitsDone: unitsDoneIn(p, course),
    weekXp: p.weekXp(monday),
    week: _day(monday),
    topErrors: [for (final (c, _) in p.topErrorCategories(3)) c.name],
  );
}

class ClassMember {
  const ClassMember({required this.uid, required this.name, required this.stats, this.updatedAt});

  final String uid;
  final String name;
  final ClassStats stats;
  final DateTime? updatedAt;
}

/// A failed licence or class action with a Turkish message to show.
class KurumException implements Exception {
  const KurumException(this.reason);

  /// format | notFound | used | expired | hasLicense | needsAccount |
  /// notTeacher | closed | tooMany | offline
  final String reason;

  String get message => switch (reason) {
    'format' => 'Kod eksik ya da hatalı görünüyor. Harfleri ve rakamları kontrol et.',
    'notFound' => 'Bu kod bulunamadı. Kurumundan aldığın kodu kontrol et.',
    'used' => 'Bu kod başka bir hesapta kullanılmış. Kurumundan yeni kod iste.',
    'expired' => 'Bu kodun süresi dolmuş. Kurumunla görüş.',
    'hasLicense' => 'Hesabında zaten süresi devam eden bir kurum lisansı var.',
    'needsAccount' => 'Lisans hesaba bağlanır. Önce Profil\'den hesap oluştur ya da giriş yap.',
    'notTeacher' => 'Sınıf açmak için öğretmen lisansı gerekiyor.',
    'closed' => 'Bu sınıf şu an yeni öğrenci almıyor. Öğretmenine sor.',
    'tooMany' => 'En fazla $maxClassesPerStudent sınıfa katılabilirsin.',
    _ => 'Şu an olmadı. İnternet bağlantını kontrol edip tekrar dene.',
  };

  @override
  String toString() => 'KurumException($reason)';
}

abstract interface class KurumApi {
  String get uid;

  /// The user's license, null when there is none or the operator revoked the
  /// seat (its code no longer points at this user).
  Stream<OrgLicense?> license();

  Future<OrgLicense> redeem(String code);

  // Teacher.
  Stream<List<ClassRoom>> teacherClasses();
  Future<ClassRoom> createClass({required String name, required String teacherName, required String org});
  Future<void> setOpen(String code, bool open);
  Future<void> deleteClass(String code);
  Stream<List<ClassMember>> members(String code);
  Future<void> removeMember(String code, String memberUid);

  // Student.
  Stream<List<String>> myClassCodes();
  Future<ClassRoom?> classInfo(String code);
  Future<ClassRoom> joinClass(String code, {required String name, required ClassStats stats});
  Future<void> leaveClass(String code);

  /// Updates the student's summary in [code]; false when the teacher removed
  /// the student (the link is then dropped).
  Future<bool> publish(String code, ClassStats stats);
}

class FirestoreKurumApi implements KurumApi {
  FirestoreKurumApi(this.db, this.uid, {this.isGuest = false, this.random});

  final FirebaseFirestore db;
  @override
  final String uid;

  /// Anonymous sign-in: licences need an account (the seat would be lost
  /// with the phone), joining a class does not.
  final bool isGuest;

  /// For tests; secure random otherwise.
  final Random? random;

  DocumentReference<Map<String, dynamic>> get _license => db.doc('licenses/$uid');
  DocumentReference<Map<String, dynamic>> get _links => db.doc('classLinks/$uid');
  DocumentReference<Map<String, dynamic>> _code(String c) => db.doc('licenseCodes/$c');
  DocumentReference<Map<String, dynamic>> _class(String c) => db.doc('classes/$c');
  DocumentReference<Map<String, dynamic>> _member(String c, String u) => db.doc('classes/$c/members/$u');

  static DateTime _time(Object? v) => switch (v) {
    final Timestamp t => t.toDate(),
    final DateTime d => d,
    _ => DateTime.fromMillisecondsSinceEpoch(0),
  };

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on KurumException {
      rethrow;
    } on Object {
      throw const KurumException('offline');
    }
  }

  @override
  Stream<OrgLicense?> license() => _license.snapshots().asyncMap((snap) async {
    final d = snap.data();
    if (d == null) return null;
    final code = d['code'] as String? ?? '';
    // The operator frees a seat by clearing claimedBy (docs/kurumlar.md).
    try {
      final c = await _code(code).get();
      if (c.exists && c.data()?['claimedBy'] != uid) return null;
    } on Object {
      // Offline: trust the license until the code can be checked.
    }
    return OrgLicense(
      code: code,
      org: d['org'] as String? ?? '',
      role: LicenseRole.parse(d['role']),
      expiresAt: _time(d['expiresAt']),
    );
  });

  @override
  Future<OrgLicense> redeem(String raw) async {
    final code = normalizeLicenseCode(raw);
    if (code == null) throw const KurumException('format');
    if (isGuest) throw const KurumException('needsAccount');
    return _guard(() async {
      final snap = await _code(code).get();
      final c = snap.data();
      if (c == null) throw const KurumException('notFound');
      final expiresAt = c['expiresAt'];
      final claimedBy = c['claimedBy'];
      if (claimedBy != null && claimedBy != uid) throw const KurumException('used');
      final now = DateTime.now();
      if (!_time(expiresAt).isAfter(now)) throw const KurumException('expired');
      final current = (await _license.get()).data();
      if (current != null && current['code'] != code && _time(current['expiresAt']).isAfter(now)) {
        throw const KurumException('hasLicense');
      }
      final batch = db.batch();
      if (claimedBy == null) {
        batch.update(_code(code), {'claimedBy': uid, 'claimedAt': FieldValue.serverTimestamp()});
      }
      batch.set(_license, {
        'code': code,
        'org': c['org'],
        'role': c['role'],
        'expiresAt': expiresAt,
        'claimedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      return OrgLicense(
        code: code,
        org: c['org'] as String? ?? '',
        role: LicenseRole.parse(c['role']),
        expiresAt: _time(expiresAt),
      );
    });
  }

  @override
  Stream<List<ClassRoom>> teacherClasses() => db
      .collection('classes')
      .where('ownerUid', isEqualTo: uid)
      .snapshots()
      .map(
        (q) =>
            [for (final d in q.docs) ClassRoom.fromDoc(d.id, d.data())]
              ..sort((a, b) => a.name.compareTo(b.name)),
      );

  @override
  Future<ClassRoom> createClass({required String name, required String teacherName, required String org}) =>
      _guard(() async {
        // A taken code fails the create (it would be an update of someone
        // else's class); try a few fresh ones.
        for (var attempt = 0; attempt < 4; attempt++) {
          final code = newClassCode(random);
          final ref = _class(code);
          if ((await ref.get()).exists) continue;
          try {
            await ref.set({
              'ownerUid': uid,
              'name': name,
              'teacherName': teacherName,
              'org': org,
              'open': true,
              'createdAt': FieldValue.serverTimestamp(),
            });
          } on FirebaseException catch (e) {
            if (e.code == 'permission-denied') throw const KurumException('notTeacher');
            rethrow;
          }
          return ClassRoom(
            code: code,
            name: name,
            teacherName: teacherName,
            org: org,
            open: true,
            ownerUid: uid,
          );
        }
        throw const KurumException('offline');
      });

  @override
  Future<void> setOpen(String code, bool open) => _guard(() => _class(code).update({'open': open}));

  @override
  Future<void> deleteClass(String code) => _guard(() async {
    final members = await _class(code).collection('members').get();
    final batch = db.batch();
    for (final m in members.docs) {
      batch.delete(m.reference);
    }
    batch.delete(_class(code));
    await batch.commit();
  });

  @override
  Stream<List<ClassMember>> members(String code) => _class(code)
      .collection('members')
      .snapshots()
      .map(
        (q) => [
          for (final d in q.docs)
            ClassMember(
              uid: d.id,
              name: d.data()['name'] as String? ?? '',
              stats: ClassStats.fromJson(d.data()),
              updatedAt: d.data()['updatedAt'] == null ? null : _time(d.data()['updatedAt']),
            ),
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      );

  @override
  Future<void> removeMember(String code, String memberUid) => _guard(() => _member(code, memberUid).delete());

  @override
  Stream<List<String>> myClassCodes() =>
      _links.snapshots().map((s) => [for (final c in (s.data()?['codes'] as List? ?? const [])) '$c']);

  Future<List<String>> _codes() async => [
    for (final c in ((await _links.get()).data()?['codes'] as List? ?? const [])) '$c',
  ];

  Future<void> _setCodes(List<String> codes) =>
      _links.set({'codes': codes, 'updatedAt': FieldValue.serverTimestamp()});

  @override
  Future<ClassRoom?> classInfo(String raw) async {
    final code = normalizeClassCode(raw);
    if (code == null) return null;
    final d = (await _class(code).get()).data();
    return d == null ? null : ClassRoom.fromDoc(code, d);
  }

  @override
  Future<ClassRoom> joinClass(String raw, {required String name, required ClassStats stats}) async {
    final code = normalizeClassCode(raw);
    if (code == null) throw const KurumException('format');
    return _guard(() async {
      final room = await classInfo(code);
      if (room == null) throw const KurumException('notFound');
      final codes = await _codes();
      final member = _member(code, uid);
      if ((await member.get()).exists) {
        await member.update({'name': name, ...stats.toJson(), 'updatedAt': FieldValue.serverTimestamp()});
      } else {
        if (!room.open) throw const KurumException('closed');
        if (codes.length >= maxClassesPerStudent && !codes.contains(code)) {
          throw const KurumException('tooMany');
        }
        await member.set({
          'name': name,
          ...stats.toJson(),
          'joinedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (!codes.contains(code)) await _setCodes([...codes, code]);
      return room;
    });
  }

  @override
  Future<void> leaveClass(String code) => _guard(() async {
    try {
      await _member(code, uid).delete();
    } on FirebaseException catch (e) {
      // Already removed by the teacher (then reading it is denied).
      if (e.code != 'permission-denied' && e.code != 'not-found') rethrow;
    }
    await _setCodes([
      for (final c in await _codes())
        if (c != code) c,
    ]);
  });

  @override
  Future<bool> publish(String code, ClassStats stats) async {
    try {
      await _member(code, uid).update({...stats.toJson(), 'updatedAt': FieldValue.serverTimestamp()});
      return true;
    } on FirebaseException catch (e) {
      // Removed by the teacher (or the class was deleted): stop reporting.
      if (e.code == 'not-found' || e.code == 'permission-denied') {
        await _setCodes([
          for (final c in await _codes())
            if (c != code) c,
        ]);
        return false;
      }
      rethrow;
    }
  }
}

/// Null without Firebase or before sign-in: every Kurum feature is hidden.
final kurumApiProvider = Provider<KurumApi?>((ref) {
  final db = ref.watch(firestoreProvider);
  final user = ref.watch(authStateProvider).value;
  if (db == null || user == null) return null;
  return FirestoreKurumApi(db, user.uid, isGuest: user.isAnonymous);
});

final orgLicenseProvider = StreamProvider<OrgLicense?>((ref) {
  final api = ref.watch(kurumApiProvider);
  if (api == null) return Stream.value(null);
  return api.license().handleError((Object _) {});
});

/// Premium from an org seat (see premiumProvider).
final licensePremiumProvider = Provider<bool>((ref) {
  final l = ref.watch(orgLicenseProvider).value;
  return l != null && l.activeAt(ref.read(clockProvider)());
});

/// The teacher's classes (only with an active teacher license).
final teacherClassesProvider = StreamProvider<List<ClassRoom>>((ref) {
  final api = ref.watch(kurumApiProvider);
  if (api == null) return Stream.value(const []);
  return api.teacherClasses();
});

final classMembersProvider = StreamProvider.family<List<ClassMember>, String>((ref, code) {
  final api = ref.watch(kurumApiProvider);
  if (api == null) return Stream.value(const []);
  return api.members(code);
});

/// The classes the student joined, with their names.
final myClassesProvider = StreamProvider<List<ClassRoom>>((ref) {
  final api = ref.watch(kurumApiProvider);
  if (api == null) return Stream.value(const []);
  return api.myClassCodes().asyncMap((codes) async {
    final rooms = <ClassRoom>[];
    for (final c in codes) {
      try {
        final r = await api.classInfo(c);
        if (r != null) rooms.add(r);
      } on Object {
        // Offline: shown again on the next update.
      }
    }
    return rooms;
  });
});

/// The student's current summary for teachers.
final classStatsProvider = Provider<ClassStats>((ref) {
  final p = ref.watch(progressProvider);
  final course = ref.watch(courseOutlineProvider).value;
  return classStatsOf(p, course, ref.read(clockProvider)());
});

/// Keeps the summary in every joined class up to date. Listened to from
/// main.dart; writes only when the summary changed, a few seconds after the
/// last change.
final classReportSyncProvider = Provider<void>((ref) {
  final api = ref.watch(kurumApiProvider);
  if (api == null) return;
  final codes = ref.watch(myClassesProvider).value?.map((c) => c.code).toList() ?? const [];
  if (codes.isEmpty) return;
  final published = <String, ClassStats>{};
  Timer? timer;
  void schedule(ClassStats stats) {
    timer?.cancel();
    timer = Timer(const Duration(seconds: 5), () async {
      for (final c in codes) {
        if (published[c] == stats) continue;
        try {
          if (await api.publish(c, stats)) published[c] = stats;
        } on Object {
          // Offline: tried again on the next change.
        }
      }
    });
  }

  ref.listen(classStatsProvider, (_, s) => schedule(s), fireImmediately: true);
  ref.onDispose(() => timer?.cancel());
});
