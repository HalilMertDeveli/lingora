import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/org/org.dart';
import 'package:lingora/org/org_widgets.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/services/firebase/firebase_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 11, 10, 12);

class FakeOrgService implements OrgService {
  MyOrg? org;
  Object? joinError;
  final joins = <(String, String)>[];
  int leaves = 0;

  @override
  Future<MyOrg?> mine() async => org;

  @override
  Future<String> join({required String code, required String displayName}) async {
    joins.add((code, displayName));
    if (joinError != null) throw joinError!;
    org = MyOrg(
      id: 'o1',
      name: 'Deniz Otel',
      isSchool: false,
      role: OrgRole.member,
      displayName: displayName,
      planExpiresAt: DateTime(2027, 1, 31),
      classes: const ['Resepsiyon'],
    );
    return 'Deniz Otel';
  }

  @override
  Future<void> leave() async {
    leaves++;
    org = null;
  }
}

OrgAssignment assignment(String id, {AssignmentKind kind = AssignmentKind.lesson, int dueInDays = 3}) =>
    OrgAssignment(
      id: id,
      kind: kind,
      targetId: id,
      courseId: 'tr_en',
      title: 'Ödev $id',
      dueAt: _now.add(Duration(days: dueInDays)),
    );

Future<void> pump(
  WidgetTester tester,
  Widget child, {
  OrgService? service,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(p),
        clockProvider.overrideWithValue(() => _now),
        orgServiceProvider.overrideWithValue(service),
        currentUidProvider.overrideWithValue(service == null ? null : 'u1'),
      ],
      child: MaterialApp(
        home: Scaffold(body: ListView(children: [child])),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('models', () {
    test('MyOrg.fromJson reads the orgMine reply and skips unknown kinds', () {
      final org = MyOrg.fromJson({
        'org': {'id': 'o1', 'name': 'Ata Koleji', 'type': 'okul', 'planExpiresAt': 1800000000000},
        'role': 'teacher',
        'displayName': 'Ayşe',
        'classes': [
          {'id': 'c1', 'name': '8-A'},
        ],
        'assignments': [
          {
            'id': 'a1',
            'kind': 'grammar',
            'targetId': 'past_simple',
            'courseId': '',
            'title': 'Past simple',
            'dueAt': 1800000000000,
            'className': '8-A',
            'status': 'open',
          },
          {'id': 'a2', 'kind': 'video', 'targetId': 'x', 'title': 'Yeni tür', 'dueAt': 1},
        ],
      })!;
      expect(org.isSchool, isTrue);
      expect(org.role, OrgRole.teacher);
      expect(org.classes, ['8-A']);
      expect(org.assignments.single.kind, AssignmentKind.grammar);
      expect(MyOrg.fromJson({'org': null}), isNull);
    });

    test('completion follows local progress, like the server', () {
      const p = Progress(completed: {'u1l1': 1, 'gl_past_simple': 2}, examBest: {'lgs': 60});
      expect(assignment('u1l1').isDone(p), isTrue);
      expect(assignment('u1l2').isDone(p), isFalse);
      expect(assignment('past_simple', kind: AssignmentKind.grammar).isDone(p), isTrue);
      expect(assignment('lgs', kind: AssignmentKind.exam).isDone(p), isTrue);
      expect(assignment('u1l2', dueInDays: -1).status(p, _now), AssignmentStatus.late);
      expect(assignment('u1l2').status(p, _now), AssignmentStatus.open);
    });

    test('error codes have Turkish messages', () {
      expect(const OrgException('no_seats').message, contains('koltuk'));
      expect(const OrgException('already_in_org').message, contains('başka bir kurum'));
      expect(const OrgException('plan_expired').message, contains('sona ermiş'));
      expect(const OrgException('internal').message, contains('tekrar dene'));
    });
  });

  testWidgets('without Firebase the org section is hidden', (tester) async {
    await pump(tester, const OrgSection());
    expect(find.text('Kurum koduyla katıl'), findsNothing);
  });

  testWidgets('join with a code, then leave', (tester) async {
    final service = FakeOrgService();
    await pump(tester, const OrgSection(), service: service);
    await tester.tap(find.text('Kurum koduyla katıl'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Günlüğün, notların'), findsOneWidget); // KVKK note

    // Wrong length and missing name are caught before calling the server.
    await tester.enterText(find.byKey(const ValueKey('org-code')), 'abc');
    await tester.tap(find.text('Katıl'));
    await tester.pumpAndSettle();
    expect(find.textContaining('8 karakter'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('org-code')), 'k7qm-3xpa');
    await tester.tap(find.text('Katıl'));
    await tester.pumpAndSettle();
    expect(find.textContaining('adını yaz'), findsOneWidget);
    expect(service.joins, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('org-name')), ' Ali Yılmaz ');
    await tester.tap(find.text('Katıl'));
    await tester.pumpAndSettle();
    expect(service.joins.single, ('K7QM3XPA', 'Ali Yılmaz'));
    expect(find.text('Deniz Otel kurumuna katıldın!'), findsOneWidget);
    expect(find.text('Deniz Otel'), findsOneWidget);
    expect(find.text('Üye · Resepsiyon'), findsOneWidget);
    expect(find.textContaining('31.01.2027'), findsOneWidget);

    await tester.tap(find.text('Kurumdan ayrıl'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayrıl'));
    await tester.pumpAndSettle();
    expect(service.leaves, 1);
    expect(find.text('Kurum koduyla katıl'), findsOneWidget);
  });

  testWidgets('server refusals are shown in Turkish and the dialog stays open', (tester) async {
    final service = FakeOrgService()..joinError = const OrgException('no_seats');
    await pump(tester, const OrgSection(), service: service);
    await tester.tap(find.text('Kurum koduyla katıl'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('org-code')), 'K7QM3XPA');
    await tester.enterText(find.byKey(const ValueKey('org-name')), 'Ali');
    await tester.tap(find.text('Katıl'));
    await tester.pumpAndSettle();
    expect(find.textContaining('boş koltuğu kalmamış'), findsOneWidget);
    expect(find.byType(JoinOrgDialog), findsOneWidget);
  });

  testWidgets('Ödevlerim card counts pending work and opens the lesson', (tester) async {
    final service = FakeOrgService()
      ..org = MyOrg(
        id: 'o1',
        name: 'Ata Koleji',
        isSchool: true,
        role: OrgRole.member,
        displayName: 'Ali',
        planExpiresAt: DateTime(2027),
        assignments: [assignment('u1l1', dueInDays: -1), assignment('u1l2'), assignment('u1l3')],
      );
    final done = jsonEncode(const Progress(onboarded: true, completed: {'u1l3': 1}).toJson());
    await pump(tester, const OrgAssignmentsCard(), service: service, prefs: {'progress_v1': done});
    expect(find.text('Ödevlerim · 2 bekliyor'), findsOneWidget);
    expect(find.text('1 ödevin süresi geçti'), findsOneWidget);

    await tester.tap(find.text('Ödevlerim · 2 bekliyor'));
    await tester.pumpAndSettle();
    expect(find.text('Süresi geçti'), findsNothing); // the status is in the subtitle line
    expect(find.textContaining('Süresi geçti'), findsOneWidget);
    expect(find.textContaining('Tamamlandı'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Ödev u1l1'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LessonScreen), findsOneWidget);
  });

  testWidgets('Ödevlerim card is hidden without an org', (tester) async {
    await pump(tester, const OrgAssignmentsCard(), service: FakeOrgService());
    expect(find.textContaining('Ödevlerim'), findsNothing);
  });
}
