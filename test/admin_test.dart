import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/admin/admin_api.dart';
import 'package:lingora/admin/admin_app.dart';
import 'package:lingora/admin/catalog.dart';
import 'package:lingora/admin/csv.dart';
import 'package:lingora/admin/dashboard.dart';
import 'package:lingora/org/org.dart';
import 'package:lingora/services/firebase/firebase_providers.dart';

final _now = DateTime(2026, 11, 10, 12);

/// orgReport() reply as the server sends it.
Map<String, Object?> reportJson() => {
  'org': {
    'id': 'o1',
    'name': 'Deniz Otel',
    'type': 'kurum',
    'seats': 20,
    'seatsUsed': 3,
    'planExpiresAt': DateTime(2027, 6, 30).millisecondsSinceEpoch,
  },
  'viewerRole': 'admin',
  'staff': false,
  'classes': [
    {'id': 'c1', 'name': 'Resepsiyon', 'teacherUid': 't1', 'teacherName': 'Tina', 'memberCount': 2},
  ],
  'assignments': [
    {
      'id': 'a1',
      'classId': 'c1',
      'kind': 'lesson',
      'targetId': 't1n1',
      'courseId': 'pro_tourism',
      'title': 'Check-in',
      'dueAt': DateTime(2026, 11, 15).millisecondsSinceEpoch,
      'done': 1,
      'total': 2,
    },
  ],
  'codes': [
    {'code': 'K7QM3XPA', 'role': 'member', 'classId': 'c1', 'uses': 4},
  ],
  'members': [
    {
      'uid': 'u1',
      'displayName': 'Ali; "Kaptan"',
      'role': 'member',
      'classIds': ['c1'],
      'joinedAt': DateTime(2026, 11, 1).millisecondsSinceEpoch,
      'synced': true,
      'lessonsDone': 12,
      'totalXp': 340,
      'streak': 4,
      'weekXp': 90,
      'lastActiveDay': '2026-11-10',
      'assignments': {'a1': 'done'},
    },
    {
      'uid': 'u2',
      'displayName': '=Ayşe',
      'role': 'member',
      'classIds': ['c1'],
      'joinedAt': 0,
      'synced': false,
      'lessonsDone': 0,
      'totalXp': 0,
      'streak': 0,
      'weekXp': 0,
      'lastActiveDay': null,
      'assignments': {'a1': 'late'},
    },
    {
      'uid': 't1',
      'displayName': 'Tina',
      'role': 'teacher',
      'classIds': <String>[],
      'joinedAt': 0,
      'synced': true,
      'lessonsDone': 3,
      'totalXp': 50,
      'streak': 1,
      'weekXp': 10,
      'lastActiveDay': '2026-11-09',
      'assignments': <String, String>{},
    },
  ],
};

class FakeAdminApi implements AdminApi {
  OrgList orgs = const OrgList(lingoraAdmin: false, orgs: []);
  final calls = <String>[];

  @override
  Future<OrgList> listOrgs() async => orgs;

  @override
  Future<OrgReport> report(String orgId, {String? classId}) async => OrgReport.fromJson(reportJson());

  @override
  Future<String> joinWithCode(String code, String displayName) async {
    calls.add('join $code $displayName');
    if (code != 'ADMIN234') throw const AdminException('invalid_code');
    orgs = OrgList(
      lingoraAdmin: false,
      orgs: [OrgSummary.fromJson((reportJson()['org'] as Map).cast<String, Object?>())],
    );
    return 'Deniz Otel';
  }

  @override
  Future<String> createCode(String orgId, OrgRole role, {String? classId}) async {
    calls.add('code ${role.name} $classId');
    return 'NEWC0DE2';
  }

  @override
  Future<void> revokeCode(String code) async => calls.add('revoke $code');

  @override
  Future<String> rotateCode(String code) async => 'ROTATED2';

  @override
  Future<String> createOrg({
    required String name,
    required bool isSchool,
    required int seats,
    required DateTime planExpiresAt,
  }) async => 'ADMIN234';

  @override
  Future<void> updateOrg(String orgId, {String? name, int? seats, DateTime? planExpiresAt}) async {}

  @override
  Future<void> removeMember(String orgId, String uid) async => calls.add('remove $uid');

  @override
  Future<void> setRole(String orgId, String uid, OrgRole role) async {}

  @override
  Future<String> createClass(String orgId, String name, {String? teacherUid}) async => 'c2';

  @override
  Future<void> deleteClass(String orgId, String classId) async {}

  @override
  Future<void> setClassMember(String orgId, String classId, String uid, {required bool add}) async {}

  @override
  Future<String> createAssignment(
    String orgId, {
    required String classId,
    required AssignmentKind kind,
    required String targetId,
    String courseId = '',
    required String title,
    required DateTime dueAt,
  }) async => 'a2';

  @override
  Future<void> deleteAssignment(String orgId, String assignmentId) async {}
}

class FakeAuth implements AdminAuth {
  final calls = <String>[];
  @override
  Future<void> signIn(String email, String password) async => calls.add('in $email');
  @override
  Future<void> signUp(String email, String password) async => calls.add('up $email');
  @override
  Future<void> resetPassword(String email) async => calls.add('reset $email');
  @override
  Future<void> signOut() async => calls.add('out');
}

Future<void> pumpPanel(WidgetTester tester, FakeAdminApi api, {AppUser? user, FakeAuth? auth}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminApiProvider.overrideWithValue(api),
        adminAuthProvider.overrideWithValue(auth ?? FakeAuth()),
        authStateProvider.overrideWithValue(AsyncData(user)),
        adminClockProvider.overrideWithValue(() => _now),
      ],
      child: const AdminApp(),
    ),
  );
  await tester.pumpAndSettle();
}

const _admin = AppUser(uid: 'boss', isAnonymous: false, email: 'mudur@otel.com');

void main() {
  test('report parsing and CSV export (Excel-safe, no private fields)', () {
    final r = OrgReport.fromJson(reportJson());
    expect(r.isAdmin, isTrue);
    expect(r.members.first.assignmentsDone, 1);
    expect(r.members[1].assignmentsLate, 1);
    expect(r.codes.single.pretty, 'K7QM-3XPA');

    final csv = membersCsv(r);
    expect(csv.startsWith('﻿Ad Soyad;Rol;Sınıflar'), isTrue);
    final lines = csv.trim().split('\r\n');
    expect(lines, hasLength(4));
    expect(lines[1], '"Ali; ""Kaptan""";Üye;Resepsiyon;12;340;90;4;2026-11-10;1;0;1;2026-11-01');
    expect(lines[2].startsWith("'=Ayşe;"), isTrue); // no formula injection
    expect(csv.toLowerCase(), isNot(contains('günlük')));
  });

  test('every assignable target exists in the app assets', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final targets = await loadAssignTargets(rootBundle);
    expect(targets.where((t) => t.kind == AssignmentKind.lesson), isNotEmpty);
    expect(targets.where((t) => t.kind == AssignmentKind.grammar), isNotEmpty);
    expect(
      targets.where((t) => t.kind == AssignmentKind.exam).map((t) => t.targetId),
      containsAll(['yds', 'lgs']),
    );
    expect(targets.where((t) => t.courseId == 'pro_tourism'), isNotEmpty);
    // Ids must pass the server's check (functions/src/orgs.ts ID_RE).
    final idRe = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
    expect(targets.every((t) => idRe.hasMatch(t.targetId)), isTrue);
  });

  testWidgets('signed out: email sign-in', (tester) async {
    final auth = FakeAuth();
    await pumpPanel(tester, FakeAdminApi(), auth: auth);
    expect(find.text('Kurum paneline giriş'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('email')), 'mudur@otel.com');
    await tester.enterText(find.byKey(const ValueKey('password')), '123');
    await tester.tap(find.text('Giriş yap'));
    await tester.pumpAndSettle();
    expect(find.textContaining('en az 6'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('password')), 'gizli-sifre');
    await tester.tap(find.text('Giriş yap'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['in mudur@otel.com']);
  });

  testWidgets('new admin enters the code, then sees the dashboard', (tester) async {
    final api = FakeAdminApi();
    await pumpPanel(tester, api, user: _admin);
    expect(find.textContaining('henüz bir kuruma bağlı değil'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('admin-code')), 'wrong-123');
    await tester.enterText(find.byKey(const ValueKey('admin-name')), 'Müdür');
    await tester.tap(find.text('Kuruma bağlan'));
    await tester.pumpAndSettle();
    expect(find.text('Kod geçersiz ya da iptal edilmiş.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('admin-code')), 'admin-234');
    await tester.tap(find.text('Kuruma bağlan'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'join ADMIN234 Müdür');
    expect(find.text('Deniz Otel · Yönetici'), findsOneWidget);
    expect(find.text('3 / 20'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget); // active in the last 7 days
    expect(find.textContaining('Günlükler, kişisel notlar'), findsOneWidget);
  });

  testWidgets('people table and codes', (tester) async {
    final api = FakeAdminApi()
      ..orgs = OrgList(
        lingoraAdmin: false,
        orgs: [OrgSummary.fromJson((reportJson()['org'] as Map).cast<String, Object?>())],
      );
    await pumpPanel(tester, api, user: _admin);

    await tester.tap(find.text('Kişiler'));
    await tester.pumpAndSettle();
    expect(find.text('Ali; "Kaptan"'), findsOneWidget);
    expect(find.text('Uygulama henüz eşitlenmedi'), findsOneWidget);
    expect(find.text('0/1 · 1 gecikti'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'tina');
    await tester.pumpAndSettle();
    expect(find.text('Ali; "Kaptan"'), findsNothing);

    await tester.tap(find.text('Davet kodları'));
    await tester.pumpAndSettle();
    expect(find.text('K7QM-3XPA'), findsOneWidget);
    expect(find.textContaining('4 kez kullanıldı'), findsOneWidget);
    await tester.tap(find.text('İptal et'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('revoke K7QM3XPA'));

    await tester.tap(find.text('Yeni kod'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oluştur'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('code member null'));
    expect(find.text('NEWC-0DE2'), findsOneWidget);
  });
}
