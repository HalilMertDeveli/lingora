import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/level_report.dart';
import 'package:lingora/data/notes_repository.dart';
import 'package:lingora/data/placement.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/models/notes.dart';
import 'package:lingora/screens/grammar_path_screen.dart' show grammarLessonsProvider;
import 'package:lingora/screens/level_report_screen.dart';
import 'package:lingora/screens/level_test_screen.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/firebase/progress_merge.dart';
import 'package:lingora/services/profile.dart';
import 'package:lingora/ui/level_certificate.dart';
import 'package:shared_preferences/shared_preferences.dart';

LevelItem _item(String id, Cefr level, LevelSkill skill) => LevelItem(
  id: id,
  level: level,
  skill: skill,
  prompt: 'Q $id',
  choices: const ['right', 'wrong'],
  answer: 0,
);

/// Three questions per level for each of [skills].
List<LevelItem> _bank([List<LevelSkill> skills = LevelSkill.values]) => [
  for (final s in skills)
    for (final l in Cefr.values)
      for (var i = 0; i < 3; i++) _item('${s.name}_${l.code}_$i', l, s),
];

LevelReport _report(String day, Cefr? overall, Map<LevelSkill, Cefr?> skills) => LevelReport(
  day: day,
  overall: overall,
  skills: {for (final e in skills.entries) e.key: SkillScore(level: e.value, right: 2, total: 4)},
);

void main() {
  group('skill scoring', () {
    test('half right at or above a level gives that level', () {
      expect(estimateSkillLevel([(Cefr.a2, true), (Cefr.b1, true), (Cefr.b2, false), (Cefr.b1, true)]), Cefr.b1);
      expect(estimateSkillLevel([(Cefr.a2, true), (Cefr.b1, true), (Cefr.b2, true), (Cefr.c1, false)]), Cefr.b2);
      expect(estimateSkillLevel([(Cefr.a2, true), (Cefr.b1, true), (Cefr.b2, true), (Cefr.c1, true)]), Cefr.c1);
    });

    test('a beginner stays below A1 and nothing answered is no level', () {
      expect(estimateSkillLevel([(Cefr.a2, false), (Cefr.a1, false), (Cefr.a1, false), (Cefr.a1, false)]), isNull);
      expect(estimateSkillLevel([(Cefr.a2, false), (Cefr.a1, true), (Cefr.a2, false), (Cefr.a1, true)]), Cefr.a1);
      expect(estimateSkillLevel(const []), isNull);
    });

    test('overall is the lower median of the measured skills', () {
      expect(overallLevel([Cefr.a2, Cefr.b1, Cefr.b2, Cefr.c1]), Cefr.b1);
      expect(overallLevel([Cefr.b2, Cefr.a2, Cefr.b1]), Cefr.b1);
      expect(overallLevel([null, null, Cefr.a1]), isNull);
      expect(overallLevel(const []), isNull);
    });
  });

  group('adaptive session', () {
    test('asks 4 per skill in turns, all right climbs to C1', () {
      final s = LevelTestSession(_bank(), start: const {}, fallbackStart: Cefr.a2);
      expect(s.planned, 16);
      final order = <LevelSkill>[];
      while (!s.isFinished) {
        order.add(s.current!.skill);
        s.answer(s.current!.answer);
      }
      expect(order.take(4), LevelSkill.values);
      final r = s.report('2026-11-18');
      expect(r.total, 16);
      expect(r.right, 16);
      // A2 → B1 → B2 → C1: the last answer was at C1.
      expect(r.skills[LevelSkill.grammar]!.level, Cefr.c1);
      expect(r.overall, Cefr.c1);
    });

    test('all wrong drops below A1, honestly', () {
      final s = LevelTestSession(_bank());
      while (!s.isFinished) {
        s.answer(-1);
      }
      final r = s.report('2026-11-18');
      expect(r.right, 0);
      expect(r.overall, isNull);
      expect(levelLabel(r.overall), 'A1 öncesi');
    });

    test('skipping listening drops it from the report', () {
      final s = LevelTestSession(_bank());
      while (!s.isFinished) {
        if (s.current!.skill == LevelSkill.listening) {
          s.skip(LevelSkill.listening);
          continue;
        }
        s.answer(s.current!.answer);
      }
      final r = s.report('2026-11-18');
      expect(r.skills.keys, isNot(contains(LevelSkill.listening)));
      expect(r.total, 12);
    });

    test('a bank without a skill only measures the others', () {
      final s = LevelTestSession(_bank([LevelSkill.grammar, LevelSkill.reading]));
      expect(s.planned, 8);
    });

    test('start levels come from last month', () {
      final s = LevelTestSession(_bank(), start: const {LevelSkill.grammar: Cefr.b2});
      expect(s.current!.skill, LevelSkill.grammar);
      expect(s.current!.level, Cefr.b2);
    });

    test('never repeats a question', () {
      final s = LevelTestSession(_bank(), seed: 7);
      final ids = <String>{};
      while (!s.isFinished) {
        expect(ids.add(s.current!.id), isTrue);
        s.answer(0);
      }
    });

    test('real banks: placement and course listening yield items at every level', () {
      final placement = parsePlacementBank(File('assets/placement/questions.json').readAsStringSync());
      final items = [for (final q in placement) LevelItem.fromPlacement(q)];
      final listening = <LevelItem>[];
      for (final f in Directory('assets/courses/tr_en').listSync().whereType<File>()) {
        if (!f.path.endsWith('.json')) continue;
        void walk(Object? o) {
          if (o is List) {
            o.forEach(walk);
          } else if (o is Map<String, dynamic>) {
            if (o['type'] == 'listening' && o['lines'] != null) {
              final node = PathNode.fromJson(o);
              if (LevelItem.fromListening(node) case final item?) listening.add(item);
            } else {
              o.values.forEach(walk);
            }
          }
        }

        walk(jsonDecode(f.readAsStringSync()));
      }
      for (final skill in LevelSkill.values) {
        for (final level in Cefr.values) {
          final n = [...items, ...listening].where((q) => q.skill == skill && q.level == level).length;
          expect(n, greaterThanOrEqualTo(3), reason: '${skill.name} ${level.code}');
        }
      }
      for (final q in listening) {
        expect(q.answer, inInclusiveRange(0, q.choices.length - 1));
      }
    });
  });

  group('30-day gate', () {
    final reports = [_report('2026-10-20', Cefr.b1, {LevelSkill.grammar: Cefr.b1})];

    test('open with no reports', () {
      expect(canTakeLevelTest(const [], DateTime(2026, 11, 18)), isTrue);
      expect(nextLevelTestDay(const []), isNull);
    });

    test('closed for 30 days, open on day 30', () {
      expect(canTakeLevelTest(reports, DateTime(2026, 10, 20, 23)), isFalse);
      expect(canTakeLevelTest(reports, DateTime(2026, 11, 18, 23, 59)), isFalse);
      expect(canTakeLevelTest(reports, DateTime(2026, 11, 19)), isTrue);
      expect(nextLevelTestDay(reports), DateTime(2026, 11, 19));
      expect(daysUntilLevelTest(reports, DateTime(2026, 11, 18, 10)), 1);
      expect(daysUntilLevelTest(reports, DateTime(2026, 12, 1)), 0);
    });

    test('the latest report decides, whatever the order', () {
      final two = [_report('2026-11-10', Cefr.b1, const {}), ...reports];
      expect(nextLevelTestDay(two), DateTime(2026, 12, 10));
    });

    test('the notifier refuses a second test inside the window', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime(2026, 11, 1);
      final c = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs), clockProvider.overrideWithValue(() => now)],
      );
      addTearDown(c.dispose);
      final n = c.read(progressProvider.notifier);
      expect(n.addLevelReport(_report('2026-11-01', Cefr.a2, const {})), isTrue);
      now = DateTime(2026, 11, 20);
      expect(n.addLevelReport(_report('2026-11-20', Cefr.b1, const {})), isFalse);
      now = DateTime(2026, 12, 1);
      expect(n.addLevelReport(_report('2026-12-01', Cefr.b1, const {})), isTrue);
      expect(c.read(progressProvider).levelReports.map((r) => r.day), ['2026-11-01', '2026-12-01']);
    });
  });

  group('storage and sync', () {
    test('json round trip through Progress', () {
      final r = _report('2026-11-18', Cefr.b1, {LevelSkill.grammar: Cefr.b2, LevelSkill.listening: null});
      final p = Progress(levelReports: [r]);
      final back = Progress.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      final b = back.levelReports.single;
      expect(b.day, '2026-11-18');
      expect(b.overall, Cefr.b1);
      expect(b.skills[LevelSkill.grammar]!.level, Cefr.b2);
      expect(b.skills[LevelSkill.listening]!.level, isNull);
      expect(b.skills.containsKey(LevelSkill.reading), isFalse);
    });

    test('old progress without reports still loads', () {
      expect(Progress.fromJson(const {}).levelReports, isEmpty);
    });

    test('merge unites devices, one report per day', () {
      final a = Progress(levelReports: [_report('2026-09-01', Cefr.a2, const {})]);
      final b = Progress(
        levelReports: [_report('2026-10-01', Cefr.b1, const {}), _report('2026-09-01', Cefr.a2, const {})],
      );
      final m = mergeProgress(a, b, localNewer: true);
      expect(m.levelReports.map((r) => r.day), ['2026-09-01', '2026-10-01']);
    });

    test('keeps the newest reports only', () {
      final many = [
        for (var i = 0; i < levelReportsKept + 5; i++)
          _report(dayKey(DateTime(2020).add(Duration(days: 31 * i))), Cefr.a1, const {}),
      ];
      final kept = mergeLevelReports(many, const []);
      expect(kept.length, levelReportsKept);
      expect(kept.last.day, many.last.day);
    });
  });

  group('trends and suggestions', () {
    test('change since last month per skill', () {
      final prev = _report('2026-10-01', Cefr.a2, {LevelSkill.grammar: Cefr.a2, LevelSkill.reading: Cefr.b1});
      final cur = _report('2026-11-01', Cefr.b1, {LevelSkill.grammar: Cefr.b1, LevelSkill.listening: Cefr.a2});
      expect(skillChange(cur, prev, LevelSkill.grammar), 1);
      expect(skillChange(cur, prev, LevelSkill.listening), isNull);
      expect(skillChange(cur, null, LevelSkill.grammar), isNull);
    });

    test('suggests the weakest skills one level up', () {
      final r = _report('2026-11-01', Cefr.b1, {
        LevelSkill.grammar: Cefr.b2,
        LevelSkill.vocabulary: Cefr.b1,
        LevelSkill.reading: Cefr.a2,
        LevelSkill.listening: Cefr.c1,
      });
      final s = studySuggestions(r);
      expect(s.map((x) => x.skill), [LevelSkill.reading, LevelSkill.vocabulary]);
      expect(s.first.target, Cefr.b1);
      final top = studySuggestions(_report('d', Cefr.c1, {LevelSkill.grammar: Cefr.c1}));
      expect(top.single.target, Cefr.c1);
    });
  });

  group('screens', () {
    Future<ProviderContainer> pump(
      WidgetTester tester,
      Widget screen, {
      bool premium = false,
      List<LevelReport> reports = const [],
      DateTime? now,
    }) async {
      SharedPreferences.setMockInitialValues({
        if (reports.isNotEmpty) 'progress_v1': jsonEncode(Progress(levelReports: reports).toJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final scope = ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => now ?? DateTime(2026, 11, 18)),
          premiumProvider.overrideWithValue(premium),
          myDisplayNameProvider.overrideWithValue('Deniz'),
          levelTestBankProvider.overrideWith((ref) async => _bank(const [
            LevelSkill.grammar,
            LevelSkill.vocabulary,
            LevelSkill.reading,
          ])),
          grammarLessonsProvider.overrideWith((ref) async => const []),
          notesProvider.overrideWith((ref) => Completer<NotesBundle>().future),
          karneListeningNodesProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(home: screen),
      );
      await tester.pumpWidget(scope);
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    }

    testWidgets('taking the test saves a report and shows the karne', (tester) async {
      final c = await pump(tester, const LevelTestScreen());
      var guard = 0;
      while (find.byKey(const Key('level-next')).evaluate().isNotEmpty && guard++ < 20) {
        await tester.tap(find.byKey(const ValueKey('level_choice_0')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('level-next')));
        await tester.pumpAndSettle();
      }
      expect(guard, 12);
      final saved = c.read(progressProvider).levelReports.single;
      expect(saved.day, '2026-11-18');
      expect(saved.total, 12);
      expect(find.text('Seviye Karnesi'), findsOneWidget);
      expect(find.textContaining('TAHMİNİ SEVİYE'), findsOneWidget);
      expect(find.textContaining('Dinleme bu ay ölçülmedi'), findsOneWidget);
      // The gate is now closed.
      expect(find.byKey(const Key('karne-next-test')), findsOneWidget);
      // Free: the Premium part is locked.
      await tester.scrollUntilVisible(find.byKey(const Key('karne-locked')), 200);
      expect(find.byKey(const Key('karne-chart')), findsNothing);
    });

    testWidgets('premium sees the chart, trends and suggestions', (tester) async {
      await pump(
        tester,
        const LevelReportScreen(),
        premium: true,
        reports: [
          _report('2026-09-15', Cefr.a2, {LevelSkill.grammar: Cefr.a2, LevelSkill.reading: Cefr.a2}),
          _report('2026-10-16', Cefr.b1, {LevelSkill.grammar: Cefr.b1, LevelSkill.reading: Cefr.a2}),
        ],
      );
      expect(find.byKey(const Key('karne-locked')), findsNothing);
      expect(find.byKey(const Key('karne-chart')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('karne-trends')), 200);
      expect(find.text('A2 → B1'), findsWidgets);
      await tester.scrollUntilVisible(find.byKey(const Key('karne-suggestions')), 200);
      expect(find.textContaining('Okuma hikâyeleri'), findsOneWidget);
      // 2026-10-16 + 30 days = 2026-11-15: open again on the 18th.
      expect(find.byKey(const Key('karne-start-test')), findsOneWidget);
    });

    testWidgets('the intro start button waits for the gate', (tester) async {
      await pump(
        tester,
        const LevelTestIntroScreen(),
        reports: [_report('2026-11-10', Cefr.b1, const {})],
      );
      final button = tester.widget<FilledButton>(find.byKey(const Key('level-test-start')));
      expect(button.onPressed, isNull);
      expect(find.textContaining('10 Aralık 2026'), findsOneWidget);
    });

    testWidgets('certificate shows name, level, date and the footnote', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: LevelCertificate(
              name: 'Deniz',
              report: _report('2026-11-18', Cefr.b2, {LevelSkill.grammar: Cefr.b2}),
              kid: true,
            ),
          ),
        ),
      );
      expect(find.text('Deniz'), findsOneWidget);
      expect(find.text('B2'), findsOneWidget);
      expect(find.text('18 Kasım 2026'), findsOneWidget);
      expect(find.textContaining('resmî bir dil sertifikası değildir'), findsOneWidget);
      expect(find.textContaining('Dilmaç ile ölçüldü'), findsOneWidget);
      // Kid mode: Pofuduk, not Çaycı Dayı.
      expect(find.bySemanticsLabel('Pofuduk'), findsOneWidget);
      expect(find.byKey(const ValueKey('dilbaz-logo')), findsNothing);
    });
  });
}
