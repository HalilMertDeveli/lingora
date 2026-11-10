/// Data layer of the Lingora Kurumsal web panel: thin wrappers around the
/// org* callables in functions/src/orgs.ts (report shape: orgReport()).
library;

import 'package:cloud_functions/cloud_functions.dart';

import '../org/org.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
DateTime _ms(Object? v) => DateTime.fromMillisecondsSinceEpoch(_int(v));
Map<String, Object?> _map(Object? v) => (v as Map? ?? const {}).cast<String, Object?>();
List<Map<String, Object?>> _list(Object? v) => [for (final e in (v as List? ?? const [])) _map(e)];

class OrgSummary {
  const OrgSummary({
    required this.id,
    required this.name,
    required this.isSchool,
    required this.seats,
    required this.seatsUsed,
    required this.planExpiresAt,
    this.role,
  });

  factory OrgSummary.fromJson(Map<String, Object?> j) => OrgSummary(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    isSchool: j['type'] == 'okul',
    seats: _int(j['seats']),
    seatsUsed: _int(j['seatsUsed']),
    planExpiresAt: _ms(j['planExpiresAt']),
    role: j['role'] == null ? null : OrgRole.parse(j['role']),
  );

  final String id;
  final String name;
  final bool isSchool;
  final int seats;
  final int seatsUsed;
  final DateTime planExpiresAt;

  /// The viewer's role (null for Lingora staff looking at any org).
  final OrgRole? role;

  String get typeLabel => isSchool ? 'Okul' : 'Kurum';
}

class OrgList {
  const OrgList({required this.lingoraAdmin, required this.orgs});
  final bool lingoraAdmin;
  final List<OrgSummary> orgs;
}

class ClassInfo {
  const ClassInfo({
    required this.id,
    required this.name,
    required this.teacherUid,
    required this.teacherName,
    required this.memberCount,
  });

  factory ClassInfo.fromJson(Map<String, Object?> j) => ClassInfo(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    teacherUid: j['teacherUid'] as String? ?? '',
    teacherName: j['teacherName'] as String? ?? '',
    memberCount: _int(j['memberCount']),
  );

  final String id;
  final String name;
  final String teacherUid;
  final String teacherName;
  final int memberCount;
}

class AssignmentInfo {
  const AssignmentInfo({
    required this.id,
    required this.classId,
    required this.kind,
    required this.targetId,
    required this.courseId,
    required this.title,
    required this.dueAt,
    required this.done,
    required this.total,
  });

  factory AssignmentInfo.fromJson(Map<String, Object?> j) => AssignmentInfo(
    id: j['id'] as String,
    classId: j['classId'] as String? ?? '',
    kind: AssignmentKind.parse(j['kind']) ?? AssignmentKind.lesson,
    targetId: j['targetId'] as String? ?? '',
    courseId: j['courseId'] as String? ?? '',
    title: j['title'] as String? ?? '',
    dueAt: _ms(j['dueAt']),
    done: _int(j['done']),
    total: _int(j['total']),
  );

  final String id;
  final String classId;
  final AssignmentKind kind;
  final String targetId;
  final String courseId;
  final String title;
  final DateTime dueAt;
  final int done;
  final int total;
}

class CodeInfo {
  const CodeInfo({required this.code, required this.role, required this.classId, required this.uses});

  factory CodeInfo.fromJson(Map<String, Object?> j) => CodeInfo(
    code: j['code'] as String,
    role: OrgRole.parse(j['role']),
    classId: j['classId'] as String? ?? '',
    uses: _int(j['uses']),
  );

  final String code;
  final OrgRole role;
  final String classId;
  final int uses;

  /// "K7QM-3XPA", easier to read out loud.
  String get pretty => code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;
}

/// What an admin or teacher may see about one person: learning numbers only.
class MemberRow {
  const MemberRow({
    required this.uid,
    required this.displayName,
    required this.role,
    required this.classIds,
    required this.joinedAt,
    required this.synced,
    required this.lessonsDone,
    required this.totalXp,
    required this.streak,
    required this.weekXp,
    required this.lastActiveDay,
    required this.assignments,
  });

  factory MemberRow.fromJson(Map<String, Object?> j) => MemberRow(
    uid: j['uid'] as String,
    displayName: j['displayName'] as String? ?? '',
    role: OrgRole.parse(j['role']),
    classIds: [for (final c in (j['classIds'] as List? ?? const [])) c as String],
    joinedAt: _ms(j['joinedAt']),
    synced: j['synced'] == true,
    lessonsDone: _int(j['lessonsDone']),
    totalXp: _int(j['totalXp']),
    streak: _int(j['streak']),
    weekXp: _int(j['weekXp']),
    lastActiveDay: j['lastActiveDay'] as String?,
    assignments: {
      for (final e in _map(j['assignments']).entries)
        e.key: AssignmentStatus.values.firstWhere(
          (s) => s.name == e.value,
          orElse: () => AssignmentStatus.open,
        ),
    },
  );

  final String uid;
  final String displayName;
  final OrgRole role;
  final List<String> classIds;
  final DateTime joinedAt;

  /// False until the learner's app has backed up progress once.
  final bool synced;
  final int lessonsDone;
  final int totalXp;
  final int streak;
  final int weekXp;

  /// yyyy-mm-dd, Turkish time.
  final String? lastActiveDay;
  final Map<String, AssignmentStatus> assignments;

  int get assignmentsDone => assignments.values.where((s) => s == AssignmentStatus.done).length;
  int get assignmentsLate => assignments.values.where((s) => s == AssignmentStatus.late).length;
}

class OrgReport {
  const OrgReport({
    required this.org,
    required this.viewerRole,
    required this.staff,
    required this.classes,
    required this.assignments,
    required this.codes,
    required this.members,
  });

  factory OrgReport.fromJson(Map<String, Object?> j) => OrgReport(
    org: OrgSummary.fromJson(_map(j['org'])),
    viewerRole: OrgRole.parse(j['viewerRole']),
    staff: j['staff'] == true,
    classes: _list(j['classes']).map(ClassInfo.fromJson).toList(),
    assignments: _list(j['assignments']).map(AssignmentInfo.fromJson).toList(),
    codes: _list(j['codes']).map(CodeInfo.fromJson).toList(),
    members: _list(j['members']).map(MemberRow.fromJson).toList(),
  );

  final OrgSummary org;
  final OrgRole viewerRole;
  final bool staff;
  final List<ClassInfo> classes;
  final List<AssignmentInfo> assignments;
  final List<CodeInfo> codes;
  final List<MemberRow> members;

  bool get isAdmin => viewerRole == OrgRole.admin;
  String className(String id) => classes.where((c) => c.id == id).firstOrNull?.name ?? '';
}

/// Everything the panel asks the server. [CallableAdminApi] in production,
/// fakes in tests.
abstract interface class AdminApi {
  Future<OrgList> listOrgs();
  Future<OrgReport> report(String orgId, {String? classId});
  Future<String> createOrg({
    required String name,
    required bool isSchool,
    required int seats,
    required DateTime planExpiresAt,
  });
  Future<void> updateOrg(String orgId, {String? name, int? seats, DateTime? planExpiresAt});
  Future<String> joinWithCode(String code, String displayName);
  Future<String> createCode(String orgId, OrgRole role, {String? classId});
  Future<String> rotateCode(String code);
  Future<void> revokeCode(String code);
  Future<void> removeMember(String orgId, String uid);
  Future<void> setRole(String orgId, String uid, OrgRole role);
  Future<String> createClass(String orgId, String name, {String? teacherUid});
  Future<void> deleteClass(String orgId, String classId);
  Future<void> setClassMember(String orgId, String classId, String uid, {required bool add});
  Future<String> createAssignment(
    String orgId, {
    required String classId,
    required AssignmentKind kind,
    required String targetId,
    String courseId = '',
    required String title,
    required DateTime dueAt,
  });
  Future<void> deleteAssignment(String orgId, String assignmentId);
}

/// A refused call with a Turkish message for the panel.
class AdminException implements Exception {
  const AdminException(this.code);
  final String code;

  String get message => switch (code) {
    'invalid_code' => 'Kod geçersiz ya da iptal edilmiş.',
    'already_in_org' => 'Bu hesap zaten başka bir kuruma bağlı.',
    'plan_expired' => 'Kurumun planı sona ermiş. Lingora ile iletişime geçin.',
    'no_seats' => 'Boş koltuk kalmadı. Koltuk eklemek için Lingora ile iletişime geçin.',
    'seats_below_used' => 'Koltuk sayısı, kullanılan koltuktan az olamaz.',
    'last_admin' => 'Kurumda en az bir yönetici kalmalı.',
    'use_leave' => 'Kendinizi buradan çıkaramazsınız.',
    'too_many_codes' => 'Çok fazla etkin kod var. Kullanılmayanları iptal edin.',
    'too_many_classes' => 'Sınıf sınırına ulaşıldı.',
    'too_many_assignments' => 'Bu sınıf için ödev sınırına ulaşıldı.',
    'not_your_class' || 'not_allowed' || 'permission-denied' => 'Bu işlem için yetkiniz yok.',
    'lingora_admin_only' => 'Bu işlemi yalnızca Lingora ekibi yapabilir.',
    'unauthenticated' => 'Oturumunuz kapanmış. Lütfen yeniden giriş yapın.',
    final c when c.startsWith('invalid_') => 'Lütfen alanları kontrol edin.',
    _ => 'İşlem tamamlanamadı. Bağlantınızı kontrol edip tekrar deneyin.',
  };

  @override
  String toString() => 'AdminException($code)';
}

class CallableAdminApi implements AdminApi {
  CallableAdminApi(this._functions);
  final FirebaseFunctions _functions;

  Future<Map<String, Object?>> _call(String name, [Map<String, Object?> data = const {}]) async {
    try {
      final res = await _functions.httpsCallable(name).call<Object?>(data);
      return _map(res.data);
    } on FirebaseFunctionsException catch (e) {
      final reason = e.message ?? '';
      throw AdminException(RegExp(r'^[a-z_]+$').hasMatch(reason) ? reason : e.code);
    }
  }

  @override
  Future<OrgList> listOrgs() async {
    final r = await _call('orgList');
    return OrgList(
      lingoraAdmin: r['lingoraAdmin'] == true,
      orgs: _list(r['orgs']).map(OrgSummary.fromJson).toList(),
    );
  }

  @override
  Future<OrgReport> report(String orgId, {String? classId}) async =>
      OrgReport.fromJson(await _call('orgReport', {'orgId': orgId, 'classId': ?classId}));

  @override
  Future<String> createOrg({
    required String name,
    required bool isSchool,
    required int seats,
    required DateTime planExpiresAt,
  }) async {
    final r = await _call('orgCreate', {
      'name': name,
      'type': isSchool ? 'okul' : 'kurum',
      'seats': seats,
      'planExpiresAt': planExpiresAt.millisecondsSinceEpoch,
    });
    return r['adminCode'] as String;
  }

  @override
  Future<void> updateOrg(String orgId, {String? name, int? seats, DateTime? planExpiresAt}) => _call(
    'orgUpdate',
    {'orgId': orgId, 'name': ?name, 'seats': ?seats, 'planExpiresAt': ?planExpiresAt?.millisecondsSinceEpoch},
  );

  @override
  Future<String> joinWithCode(String code, String displayName) async =>
      (await _call('orgJoin', {'code': code, 'displayName': displayName}))['orgName'] as String? ?? '';

  @override
  Future<String> createCode(String orgId, OrgRole role, {String? classId}) async =>
      (await _call('orgCreateCode', {'orgId': orgId, 'role': role.name, 'classId': ?classId}))['code']
          as String;

  @override
  Future<String> rotateCode(String code) async =>
      (await _call('orgRotateCode', {'code': code}))['code'] as String;

  @override
  Future<void> revokeCode(String code) => _call('orgRevokeCode', {'code': code});

  @override
  Future<void> removeMember(String orgId, String uid) =>
      _call('orgRemoveMember', {'orgId': orgId, 'uid': uid});

  @override
  Future<void> setRole(String orgId, String uid, OrgRole role) =>
      _call('orgSetRole', {'orgId': orgId, 'uid': uid, 'role': role.name});

  @override
  Future<String> createClass(String orgId, String name, {String? teacherUid}) async =>
      (await _call('orgCreateClass', {'orgId': orgId, 'name': name, 'teacherUid': ?teacherUid}))['classId']
          as String;

  @override
  Future<void> deleteClass(String orgId, String classId) =>
      _call('orgDeleteClass', {'orgId': orgId, 'classId': classId});

  @override
  Future<void> setClassMember(String orgId, String classId, String uid, {required bool add}) =>
      _call('orgSetClassMember', {'orgId': orgId, 'classId': classId, 'uid': uid, 'add': add});

  @override
  Future<String> createAssignment(
    String orgId, {
    required String classId,
    required AssignmentKind kind,
    required String targetId,
    String courseId = '',
    required String title,
    required DateTime dueAt,
  }) async =>
      (await _call('orgCreateAssignment', {
            'orgId': orgId,
            'classId': classId,
            'kind': kind.name,
            'targetId': targetId,
            if (courseId.isNotEmpty) 'courseId': courseId,
            'title': title,
            'dueAt': dueAt.millisecondsSinceEpoch,
          }))['assignmentId']
          as String;

  @override
  Future<void> deleteAssignment(String orgId, String assignmentId) =>
      _call('orgDeleteAssignment', {'orgId': orgId, 'assignmentId': assignmentId});
}
