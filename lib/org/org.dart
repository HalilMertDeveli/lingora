/// Lingora Kurumsal on the learner's side: which org the user belongs to,
/// joining with a code and the assignments from their teacher.
///
/// Server: functions/src/orgs.ts (callables orgJoin, orgLeave, orgMine).
/// Without Firebase (the default build) there is no service and every
/// org feature stays hidden.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../services/firebase/firebase_providers.dart';

enum OrgRole {
  admin('Yönetici'),
  teacher('Öğretmen'),
  member('Üye');

  const OrgRole(this.label);
  final String label;

  static OrgRole parse(Object? v) => values.firstWhere((r) => r.name == v, orElse: () => member);
}

enum AssignmentKind {
  lesson('Ders'),
  grammar('Gramer'),
  exam('Deneme');

  const AssignmentKind(this.label);
  final String label;

  static AssignmentKind? parse(Object? v) => values.where((k) => k.name == v).firstOrNull;
}

enum AssignmentStatus { done, open, late }

class OrgAssignment {
  const OrgAssignment({
    required this.id,
    required this.kind,
    required this.targetId,
    required this.title,
    required this.dueAt,
    this.courseId = '',
    this.className = '',
  });

  /// Returns null for kinds this app version does not know.
  static OrgAssignment? fromJson(Map<String, Object?> j) {
    final kind = AssignmentKind.parse(j['kind']);
    if (kind == null) return null;
    return OrgAssignment(
      id: j['id'] as String,
      kind: kind,
      targetId: j['targetId'] as String,
      courseId: j['courseId'] as String? ?? '',
      title: j['title'] as String? ?? '',
      className: j['className'] as String? ?? '',
      dueAt: DateTime.fromMillisecondsSinceEpoch((j['dueAt'] as num).toInt()),
    );
  }

  final String id;
  final AssignmentKind kind;

  /// Course node id, grammar lesson id or exam id.
  final String targetId;

  /// Course asset id for [AssignmentKind.lesson].
  final String courseId;
  final String title;
  final String className;
  final DateTime dueAt;

  /// Same rule as the server (functions/src/orgs.ts assignmentDone), but on
  /// the local progress so it updates right after the lesson.
  bool isDone(Progress p) => switch (kind) {
    AssignmentKind.lesson => p.isDone(targetId),
    AssignmentKind.grammar => p.isDone('gl_$targetId'),
    AssignmentKind.exam => p.examBest.containsKey(targetId),
  };

  AssignmentStatus status(Progress p, DateTime now) {
    if (isDone(p)) return AssignmentStatus.done;
    return dueAt.isBefore(now) ? AssignmentStatus.late : AssignmentStatus.open;
  }
}

class MyOrg {
  const MyOrg({
    required this.id,
    required this.name,
    required this.isSchool,
    required this.role,
    required this.displayName,
    required this.planExpiresAt,
    this.classes = const [],
    this.assignments = const [],
  });

  /// Null when the user is in no org.
  static MyOrg? fromJson(Map<String, Object?> j) {
    final org = j['org'];
    if (org is! Map) return null;
    final o = org.cast<String, Object?>();
    return MyOrg(
      id: o['id'] as String,
      name: o['name'] as String,
      isSchool: o['type'] == 'okul',
      planExpiresAt: DateTime.fromMillisecondsSinceEpoch((o['planExpiresAt'] as num).toInt()),
      role: OrgRole.parse(j['role']),
      displayName: j['displayName'] as String? ?? '',
      classes: [for (final c in (j['classes'] as List? ?? const [])) (c as Map)['name'] as String],
      assignments: [
        for (final a in (j['assignments'] as List? ?? const []))
          ?OrgAssignment.fromJson((a as Map).cast<String, Object?>()),
      ],
    );
  }

  final String id;
  final String name;
  final bool isSchool;
  final OrgRole role;
  final String displayName;
  final DateTime planExpiresAt;
  final List<String> classes;
  final List<OrgAssignment> assignments;
}

/// A failed org call with a Turkish message to show.
class OrgException implements Exception {
  const OrgException(this.code);
  final String code;

  String get message => switch (code) {
    'invalid_code' || 'invalid-argument' => 'Kod geçersiz ya da artık kullanılmıyor. Yöneticine sor.',
    'plan_expired' => 'Kurumun Lingora planı sona ermiş. Yöneticinle görüş.',
    'already_in_org' => 'Zaten başka bir kuruma bağlısın. Önce oradan ayrılman gerekiyor.',
    'no_seats' => 'Kurumun boş koltuğu kalmamış. Yöneticinden koltuk eklemesini iste.',
    'unauthenticated' => 'Hesabın henüz hazır değil. Birkaç saniye sonra tekrar dene.',
    _ => 'Şu an olmadı. İnternet bağlantını kontrol edip tekrar dene.',
  };

  @override
  String toString() => 'OrgException($code)';
}

abstract interface class OrgService {
  Future<MyOrg?> mine();

  /// Returns the org's name.
  Future<String> join({required String code, required String displayName});
  Future<void> leave();
}

class CallableOrgService implements OrgService {
  CallableOrgService(this._functions);
  final FirebaseFunctions _functions;

  Future<Map<String, Object?>> _call(String name, [Map<String, Object?> data = const {}]) async {
    try {
      final res = await _functions.httpsCallable(name).call<Object?>(data);
      return (res.data as Map? ?? const {}).cast<String, Object?>();
    } on FirebaseFunctionsException catch (e) {
      // Our own reasons ("no_seats") come as the message; fall back to the code.
      final reason = e.message ?? '';
      throw OrgException(RegExp(r'^[a-z_]+$').hasMatch(reason) ? reason : e.code);
    }
  }

  @override
  Future<MyOrg?> mine() async => MyOrg.fromJson(await _call('orgMine'));

  @override
  Future<String> join({required String code, required String displayName}) async {
    final r = await _call('orgJoin', {'code': code, 'displayName': displayName});
    return r['orgName'] as String? ?? '';
  }

  @override
  Future<void> leave() => _call('orgLeave');
}

/// Null when Firebase is off: the org features are then hidden.
final orgServiceProvider = Provider<OrgService?>((ref) {
  final functions = ref.watch(functionsProvider);
  return functions == null ? null : CallableOrgService(functions);
});

/// The signed-in user's org, or null. Invalidate after joining or leaving.
final myOrgProvider = FutureProvider<MyOrg?>((ref) async {
  final service = ref.watch(orgServiceProvider);
  final uid = ref.watch(currentUidProvider);
  if (service == null || uid == null) return null;
  try {
    return await service.mine();
  } on OrgException {
    return null; // offline: just hide the card
  }
});
