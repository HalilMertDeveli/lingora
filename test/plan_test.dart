// "Bugün" daily plan (docs/sinav/yds-faz1-yontem.md §3, §6): the year plan
// file, blocks scaled to 2/3/4 hours, weeks that move on by steps, mock and
// light days, the streak freeze, the reading counter and "Nasıl öğretiyoruz?".
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/placement.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/models/study_plan.dart';
import 'package:lingora/screens/study/methods_screen.dart';
import 'package:lingora/screens/study/today_screen.dart';
import 'package:lingora/services/firebase/progress_merge.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/study/daily_plan.dart';
import 'package:lingora/study/methods.dart';
import 'package:lingora/study/year_plan.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'study_test.dart' show readCourse;
import 'widget_test.dart' show FakeNotifications, FakeSpeech;

final year = YearPlan.fromJson(jsonDecode(File(yearPlanAsset).readAsStringSync()) as Map<String, dynamic>);
late final Course general;
final yds = readCourse('exam_yds');
late final Map<String, Unit> units;
// A Wednesday.
final now = DateTime(2026, 11, 11, 9);
final today = dayKey(now);

StudyPlan plan({int week = 1, int minutes = 180, String? weekStart, int base = 0}) => StudyPlan(
  exam: 'yds',
  week: week,
  weekStart: weekStart ?? today,
  dailyMinutes: minutes,
  startDay: today,
  weekWordsBase: base,
);

/// Every step of [weekNo]'s units, done.
Map<String, int> weekDone(int weekNo) => {
  for (final id in year.week(weekNo).unitIds)
    for (final n in units[id]!.nodes) n.id: 1,
};

Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  Widget child, {
  Progress? progress,
  Cefr? level,
}) async {
  SharedPreferences.setMockInitialValues({
    'progress_v1': jsonEncode(
      (progress ?? const Progress(onboarded: true, remindersEnabled: false)).toJson(),
    ),
    if (level != null) 'placement_v1': jsonEncode({'level': level.code, 'reason': 'academic', 'day': today}),
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      speechProvider.overrideWithValue(FakeSpeech()),
      notificationServiceProvider.overrideWithValue(FakeNotifications()),
      clockProvider.overrideWithValue(() => now),
      courseProvider.overrideWith((ref) async => yds),
      yearPlanProvider.overrideWith((ref) async => year),
      planDataProvider.overrideWith((ref) async => (year: year, units: units)),
    ],
  );
  addTearDown(c.dispose);
  await c.read(courseProvider.future);
  await c.read(planDataProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildTheme(), home: child),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The general course with its section and extension files, as the app loads it.
    general = await loadCourse(rootBundle, 'tr_en');
    units = planUnits([general, yds]);
  });

  group('year plan file', () {
    test('52 weeks, block shares add up to 1, every unit id exists', () {
      expect(year.length, 52);
      expect(year.shares.values.fold(0.0, (a, b) => a + b), closeTo(1, 0.001));
      final missing = [
        for (final w in year.weeks)
          for (final id in [...w.unitIds])
            if (!units.containsKey(id)) '${w.week}:$id',
      ];
      expect(missing, isEmpty);
      expect(year.weeks.where((w) => w.reviewWeek).map((w) => w.week), containsAll([10, 34, 42, 52]));
      expect(year.targetSeconds['reading'], 180);
    });

    test('start weeks: A0–A1 → 1, A2 → 11, B1 → 21', () {
      expect(
        [startWeekFor(null), startWeekFor(Cefr.a1), startWeekFor(Cefr.a2), startWeekFor(Cefr.b1)],
        [1, 1, 11, 21],
      );
      expect(startWeeks(year), [1, 11, 21, 35, 43]);
    });
  });

  group('blocks', () {
    test('3.5 hours is 30/60/45/45/20; 2, 3 and 4 hours scale and add up', () {
      final m = blockMinutes(210, year.shares);
      expect(m, {
        PlanBlock.review: 30,
        PlanBlock.lesson: 60,
        PlanBlock.reading: 45,
        PlanBlock.questions: 45,
        PlanBlock.mistakes: 20,
      });
      for (final daily in dailyMinuteChoices) {
        final b = blockMinutes(daily, year.shares);
        expect(b.values.fold(0, (a, v) => a + v), daily - breakMinutes(daily), reason: '$daily');
        expect(b.values.every((v) => v >= 5), isTrue);
      }
      expect(
        blockMinutes(240, year.shares)[PlanBlock.lesson],
        greaterThan(blockMinutes(120, year.shares)[PlanBlock.lesson]!),
      );
    });

    test('a normal day: five blocks measured against the week targets', () {
      final week = year.week(11);
      final blocks = dayBlocks(
        kind: DayKind.normal,
        plan: plan(week: 11),
        year: year,
        week: week,
        c: const DayCounts(
          cardsLeft: 10,
          cardsDone: 10,
          lessonsToday: 1,
          questionsToday: 25,
          readingToday: 500,
        ),
        nextStep: 'Kipler 1',
      );
      expect(blocks.map((b) => b.block), [
        PlanBlock.review,
        PlanBlock.lesson,
        PlanBlock.reading,
        PlanBlock.questions,
        PlanBlock.mistakes,
      ]);
      expect(blocks[0].progress, 0.5);
      expect(blocks[1].progress, 0.5);
      expect(blocks[2].progress, 500 / week.readingWordsPerDay);
      expect(blocks[3].done, isTrue);
      expect(blocks[4].done, isTrue);
    });

    test('a week without questions has no question block; a short day starts with memory', () {
      final blocks = dayBlocks(
        kind: DayKind.normal,
        plan: plan(minutes: 30),
        year: year,
        week: year.week(1),
        c: const DayCounts(mistakesDue: 2),
      );
      expect(blocks.map((b) => b.block), [
        PlanBlock.review,
        PlanBlock.mistakes,
        PlanBlock.lesson,
        PlanBlock.reading,
      ]);
      expect(blocks.fold(0, (a, b) => a + b.minutes), lessThanOrEqualTo(30));
    });

    test(
      'mocks come from the plan\'s mocks field: a level check is no mock day, a second mock 3 days on',
      () {
        final saturday = DateTime(2026, 11, 14);
        final tuesday = DateTime(2026, 11, 17);
        // H10: level check only.
        final h10 = year.week(10);
        expect(h10.mocks.single.kind, MockKind.check);
        expect(todayMock(plan: plan(week: 10), week: h10, now: saturday), isNull);
        expect(dayKind(plan: plan(week: 10), week: h10, now: saturday), isNot(DayKind.mock));
        // H26: the ys1 section mock, 20 questions / 45 min.
        final h26 = year.week(26);
        final section = todayMock(plan: plan(week: 26), week: h26, now: saturday)!;
        expect((section.kind, section.nodeId, section.minutes), (MockKind.section, 'ys1u10m', 45));
        final blocks = dayBlocks(
          kind: DayKind.mock,
          plan: plan(week: 26),
          year: year,
          week: h26,
          c: const DayCounts(),
          mock: section,
        );
        expect((blocks.last.minutes, blocks.last.name), (45, 'Bölüm denemesi'));
        // H48: two full mocks, Saturday and three days later (Tuesday).
        final h48 = year.week(48);
        expect(h48.examMocks.map((m) => m.id), ['yds_m5', 'yds_m16']);
        expect(todayMock(plan: plan(week: 48), week: h48, now: saturday)!.id, 'yds_m5');
        expect(todayMock(plan: plan(week: 48), week: h48, now: tuesday)!.id, 'yds_m16');
        expect(todayMock(plan: plan(week: 26), week: h26, now: tuesday), isNull);
      },
    );

    test('a plan file without mocks falls back to the week\'s text', () {
      expect(PlanMock.fromText('Seviye kontrolü (genel kurs s4 sonu)').single.kind, MockKind.check);
      expect(PlanMock.fromText('Tam deneme 3 (yeni: yds_m11)').single.id, 'yds_m11');
      expect(PlanMock.fromText('Yarım deneme 2').single.minutes, 90);
      expect(PlanMock.fromText(null), isEmpty);
    });

    test('mock day, the day after and the light day', () {
      final mockWeek = year.weeks.firstWhere((w) => w.examMocks.any((m) => m.kind == MockKind.full));
      final p = plan(week: mockWeek.week);
      final saturday = DateTime(2026, 11, 14);
      expect(dayKind(plan: p, week: mockWeek, now: saturday), DayKind.mock);
      final m = todayMock(plan: p, week: mockWeek, now: saturday)!;
      final mock = dayBlocks(
        kind: DayKind.mock,
        plan: p,
        year: year,
        week: mockWeek,
        c: const DayCounts(),
        mock: m,
      );
      expect(mock.map((b) => (b.block, b.minutes)), [(PlanBlock.review, 20), (PlanBlock.mock, 180)]);

      final sunday = DateTime(2026, 11, 15);
      expect(dayKind(plan: p, week: mockWeek, now: sunday, mockYesterday: true), DayKind.afterMock);
      final after = dayBlocks(
        kind: DayKind.afterMock,
        plan: p,
        year: year,
        week: mockWeek,
        c: const DayCounts(),
      );
      expect(after.map((b) => b.block), contains(PlanBlock.mockReview));
      expect(after.map((b) => b.block), isNot(contains(PlanBlock.questions)));

      expect(dayKind(plan: p, week: year.week(1), now: sunday), DayKind.light);
      final light = dayBlocks(
        kind: DayKind.light,
        plan: p,
        year: year,
        week: year.week(1),
        c: const DayCounts(),
      );
      expect(light.map((b) => b.block), [PlanBlock.review, PlanBlock.mistakes, PlanBlock.reading]);
      expect(light.fold(0, (a, b) => a + b.minutes), 90);
    });
  });

  group('weeks move on by steps', () {
    test('missed days do not move the week; finishing its steps and words does', () {
      final p0 = plan(weekStart: dayKey(now.subtract(const Duration(days: 30))));
      // A month passed with nothing done: still week 1.
      expect(settleWeek(plan: p0, year: year, units: units, progress: const Progress(), now: now).week, 1);

      final steps = Progress(completed: weekDone(1));
      final status = weekStatus(plan: p0, year: year, units: units, progress: steps);
      expect(status.stepsDone, status.stepsTotal);
      expect(status.done, isFalse, reason: 'new words not started yet');
      final words = steps.copyWith(wordBox: {for (var i = 0; i < year.week(1).newWords; i++) 'gm_w$i': 1});
      final next = settleWeek(plan: p0, year: year, units: units, progress: words, now: now);
      expect((next.week, next.weekStart, next.weekWordsBase), (2, today, year.week(1).newWords));
      // Only one week per call.
      expect(settleWeek(plan: next, year: year, units: units, progress: words, now: now).week, 2);
    });

    test('with no new cards to learn, the steps alone finish the week', () {
      final s = weekStatus(
        plan: plan(),
        year: year,
        units: units,
        progress: Progress(completed: weekDone(1)),
        noNewCards: true,
      );
      expect(s.done, isTrue);
    });

    test('a review week ends after a week of study days', () {
      final p = plan(week: 10, weekStart: dayKey(now.subtract(const Duration(days: 9))));
      final five = Progress(
        xpByDay: {for (var i = 0; i < 5; i++) dayKey(now.subtract(Duration(days: i))): 20},
      );
      expect(weekStatus(plan: p, year: year, units: units, progress: five).done, isFalse);
      final six = five.copyWith(xpByDay: {...five.xpByDay, dayKey(now.subtract(const Duration(days: 6))): 5});
      expect(weekStatus(plan: p, year: year, units: units, progress: six).done, isTrue);
    });

    test('the next step is the first unfinished step of the week', () {
      final first = year.week(1).unitIds.first;
      final (unit, node) = nextPlanStep(year.week(1), units, const Progress())!;
      expect((unit.id, node.id), (first, units[first]!.nodes.first.id));
      expect(nextPlanStep(year.week(1), units, Progress(completed: weekDone(1))), isNull);
    });

    test('a side-path unit left from an earlier week stays in the plan', () {
      final earlier = year.weeks.firstWhere((w) => w.parallelUnitIds.any(units.containsKey));
      final later = year.week(earlier.week + 1);
      final left = earlier.parallelUnitIds.firstWhere(units.containsKey);
      final done = {
        for (final id in [...later.unitIds, ...later.parallelUnitIds])
          for (final n in units[id]?.nodes ?? const <PathNode>[]) n.id: 1,
      };
      final (unit, _) = nextPlanStep(later, units, Progress(completed: done), year: year)!;
      expect(unit.id, left);
      expect(nextPlanStep(later, units, Progress(completed: done)), isNull);
    });
  });

  group('progress', () {
    Future<ProviderContainer> container(Progress p, DateTime at) async {
      SharedPreferences.setMockInitialValues({'progress_v1': jsonEncode(p.toJson())});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs), clockProvider.overrideWithValue(() => at)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('with a plan, one missed day a week keeps the streak', () async {
      final twoDaysAgo = dayKey(now.subtract(const Duration(days: 2)));
      final p = Progress(streak: 9, lastActiveDay: twoDaysAgo, studyPlan: plan());
      expect(p.streakAt(now), 9);
      expect(Progress(streak: 9, lastActiveDay: twoDaysAgo).streakAt(now), 0);
      final c = await container(p, now);
      final reward = c.read(progressProvider.notifier).completeNode('x', xp: 10, answered: 1, correct: 1);
      expect(reward.streak, 10);
      final used = c.read(progressProvider).studyPlan!.freezeWeek;
      expect(used, isNotNull);
      // The same week, another missed day: the freeze is used up.
      final again = Progress(
        streak: 10,
        lastActiveDay: twoDaysAgo,
        studyPlan: plan().copyWith(freezeWeek: used),
      );
      expect(again.streakAt(now), 0);
    });

    test('the reading counter adds today and all time', () async {
      final c = await container(const Progress(), now);
      c.read(progressProvider.notifier)
        ..addReading(220)
        ..addReading(180);
      final p = c.read(progressProvider);
      expect((p.readingWords, p.readingWordsOn(today)), (400, 400));
    });

    test('the plan and reading count survive a save and a cloud merge', () {
      final local = Progress(studyPlan: plan(week: 12), readingWords: 5000);
      final remote = Progress(studyPlan: plan(week: 14), readingWords: 7000);
      final merged = mergeProgress(local, remote, localNewer: true);
      expect((merged.studyPlan!.week, merged.readingWords), (14, 7000));
      final back = Progress.fromJson(jsonDecode(jsonEncode(merged.toJson())) as Map<String, dynamic>);
      expect(back.studyPlan!.week, 14);
      expect(Progress.fromJson(const {}).studyPlan, isNull);
    });
  });

  group('screens', () {
    testWidgets('setup: the placement level picks the start week; saving starts the plan and the reminder', (
      tester,
    ) async {
      final c = await pumpApp(tester, const TodayScreen(), level: Cefr.a2);
      expect(find.text('YDS planını kuralım'), findsOneWidget);
      final chip = tester.widget<ChoiceChip>(find.byKey(const Key('start-11')));
      expect(chip.selected, isTrue);
      await tester.tap(find.byKey(const Key('minutes-240')));
      await tester.enterText(find.byKey(const Key('plan-place')), 'Kütüphane');
      await tester.tap(find.byKey(const Key('light-7')));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('plan-save')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan-save')));
      await tester.pumpAndSettle();
      final p = c.read(progressProvider);
      expect((p.studyPlan!.week, p.studyPlan!.dailyMinutes, p.studyPlan!.place), (11, 240, 'Kütüphane'));
      expect(p.remindersEnabled, isTrue);
      // Weeks 1–10 count as known.
      expect(p.isDone(units[year.week(1).unitIds.first]!.nodes.first.id), isTrue);
      expect(find.byKey(const Key('block-review')), findsOneWidget);
      expect(find.byKey(const Key('block-lesson')), findsOneWidget);
      expect(find.text('240 dk'), findsNothing);
      expect(find.textContaining('Hafta 11 / 52'), findsOneWidget);
    });

    testWidgets('a week in progress: blocks, week steps and the finish estimate', (tester) async {
      final p = Progress(onboarded: true, remindersEnabled: false, studyPlan: plan(week: 1));
      await pumpApp(tester, const TodayScreen(), progress: p);
      for (final b in [PlanBlock.review, PlanBlock.lesson, PlanBlock.reading, PlanBlock.mistakes]) {
        expect(find.byKey(Key('block-${b.name}')), findsOneWidget);
      }
      expect(find.byKey(const Key('block-questions')), findsNothing);
      expect(find.byKey(const Key('week-steps')), findsOneWidget);
      expect(find.byKey(const Key('today-finish')), findsOneWidget);
      expect(find.textContaining('kaçırdığın gün birikmez'), findsOneWidget);
    });

    testWidgets('Nasıl öğretiyoruz: ten cards, each with Ne / Neden / Nerede', (tester) async {
      await pumpApp(tester, const MethodsScreen(focus: 'habit'));
      expect(studyMethods, hasLength(10));
      for (final m in studyMethods) {
        expect(find.byKey(Key('method-${m.id}')), findsOneWidget);
      }
      expect(find.textContaining('Ne? ', findRichText: true), findsNWidgets(10));
      expect(find.textContaining('Lally', findRichText: true), findsOneWidget);
      // No overclaiming.
      for (final m in studyMethods) {
        expect('${m.what} ${m.why} ${m.where}'.toLowerCase(), isNot(contains('kanıtlanmış en iyi')));
      }
    });
  });
}
