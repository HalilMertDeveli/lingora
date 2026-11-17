// Detaylı hata analizi v2: the numbers (weak topics and types, the weekly
// trend, what got better, the LGS net estimate), the hata dedektörü history,
// the targeted drill's question choice, and the free / Premium screen.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/tr_errors.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/practice.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/error_analysis_screen.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/screens/paywall_screen.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/study/error_insights.dart';
import 'package:lingora/study/question_types.dart';
import 'package:lingora/study/study_state.dart';
import 'package:lingora/study/tr_error_log.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/ui/mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'premium_test.dart' show FakeBilling;
import 'study_test.dart' show readCourse;
import 'widget_test.dart' show FakeNotifications, FakeSpeech;

final yds = readCourse('exam_yds');
final now = DateTime(2026, 11, 17, 9);
final today = dayKey(now);
String ago(int days) => daysBefore(today, days);

AnswerLog ans(String unit, String type, bool ok, {String day = '', String? key}) => AnswerLog(
  key: key ?? '$unit#${type.hashCode}',
  day: day.isEmpty ? today : day,
  correct: ok,
  seconds: 30,
  type: type,
  unitId: unit,
);

/// [right] right and [wrong] wrong answers of [unit] / [type] on [day].
List<AnswerLog> many(String unit, String type, int right, int wrong, {String day = ''}) => [
  for (var i = 0; i < right; i++) ans(unit, type, true, day: day),
  for (var i = 0; i < wrong; i++) ans(unit, type, false, day: day),
];

const titles = {'u1': 'Present Simple', 'u2': 'Articles', 'u3': 'Past Simple', 'u4': 'Modals'};

TrError err(TrErrorCategory c, String wrong, String fixed) =>
    TrError(ruleId: 'r', category: c, wrong: wrong, corrected: fixed, explanation: 'neden');

void main() {
  group('weak points', () {
    test('per topic and type with percentages, weakest first', () {
      final log = [
        ...many('u1', 'grammar', 8, 2), // 80%
        ...many('u2', 'vocabulary', 3, 7), // 30%
        ...many('u3', 'grammar', 5, 5), // 50%
        ...many('u4', 'translate', 2, 1), // too few
        ...many('zz', 'grammar', 0, 9), // another course's unit
      ];
      final topics = topicBuckets(log, titles);
      expect(topics.keys.toSet(), {'u1', 'u2', 'u3', 'u4'});
      expect(topics['u2']!.percent, 30);
      expect(topics['u2']!.label, 'Articles');
      final weak = weakest(topics.values);
      expect(weak.map((b) => b.key), ['u2', 'u3', 'u1']);
      expect(weak.map((b) => b.percent), [30, 50, 80]);

      final types = typeBuckets(log);
      expect(types['grammar']!.answered, 29);
      expect(types['translate']!.label, 'Çeviri yazma');
      expect(types['vocabulary']!.label, QType.vocabulary.label);
      expect(weakest(types.values).first.key, 'vocabulary');
    });

    test('a perfect or barely answered topic is never weak', () {
      final log = [...many('u1', 'grammar', 10, 0), ...many('u2', 'grammar', 1, 2)];
      expect(weakest(topicBuckets(log, titles).values), isEmpty);
    });

    test('heat map: busiest topics, the types answered in them, accuracy per cell', () {
      final log = [
        ...many('u1', 'grammar', 6, 2),
        ...many('u1', 'translate', 1, 3),
        ...many('u2', 'grammar', 2, 2),
        ...many('zz', 'reading', 50, 0), // another course: neither row nor column
      ];
      final h = heatMap(log, titles);
      expect(h.rows.map((b) => b.key), ['u1', 'u2']);
      expect(h.cols.map((b) => b.key), ['grammar', 'translate']);
      expect(h.cell('u1', 'grammar')!.percent, 75);
      expect(h.cell('u1', 'translate')!.percent, 25);
      expect(h.cell('u2', 'translate'), isNull);
    });

    test('lessons until the analysis opens', () {
      expect(lessonsUntilInsights(0), 3);
      expect(lessonsUntilInsights(12), 2);
      expect(lessonsUntilInsights(29), 1);
      expect(lessonsUntilInsights(30), 0);
    });
  });

  group('trend', () {
    test('this week against last week, in points', () {
      final log = [
        ...many('u1', 'grammar', 5, 5, day: ago(10)), // last week 50%
        ...many('u1', 'grammar', 8, 2, day: ago(2)), // this week 80%
        ...many('u1', 'grammar', 0, 10, day: ago(20)), // older: ignored
      ];
      final w = weekCompare(log, today);
      expect(w.thisWeek.answered, 10);
      expect(w.lastWeek.percent, 50);
      expect(w.deltaPoints, 30);
      expect(weekCompare(log.sublist(10, 20), today).deltaPoints, isNull);
    });

    test('daily accuracy covers 14 days, oldest first', () {
      final d = dailyAccuracy([
        ...many('u1', 'grammar', 1, 1, day: ago(13)),
        ans('u1', 'grammar', true),
      ], today);
      expect(d.length, 14);
      expect(d.first!.percent, 50);
      expect(d.last!.percent, 100);
      expect(d[5], isNull);
    });

    test('a topic whose error rate fell by at least a fifth is "düzeldi"', () {
      final log = [
        ...many('u2', 'vocabulary', 4, 6, day: ago(20)), // 60% wrong before
        ...many('u2', 'vocabulary', 8, 2, day: ago(3)), // 20% wrong now
        ...many('u1', 'grammar', 5, 5, day: ago(20)), // 50% → 45%: too small
        ...many('u1', 'grammar', 11, 9, day: ago(3)),
        ...many('u3', 'grammar', 0, 3, day: ago(20)), // too few before
        ...many('u3', 'grammar', 5, 0, day: ago(3)),
      ];
      final list = improvements(log, titles, const TrErrorLog(), today);
      final articles = list.firstWhere((i) => i.label == 'Articles');
      expect(articles.dropPercent, 67);
      expect(list.where((i) => i.label == 'Present Simple'), isEmpty);
      expect(list.where((i) => i.label == 'Past Simple'), isEmpty);
      // Biggest drop first; at most three.
      expect(list.length, lessThanOrEqualTo(3));
      for (var i = 1; i < list.length; i++) {
        expect(list[i - 1].drop, greaterThanOrEqualTo(list[i].drop));
      }
    });

    test('hata dedektörü categories are compared per check, not per mistake', () {
      var tr = const TrErrorLog();
      // Before: 4 article mistakes in 10 checks. Recently: 1 in 10.
      for (var i = 0; i < 10; i++) {
        tr = tr.record(ago(20), [if (i < 4) err(TrErrorCategory.article, 'a apple', 'an apple')]);
        tr = tr.record(ago(2), [if (i < 1) err(TrErrorCategory.article, 'a apple', 'an apple')]);
      }
      final i = improvements(const [], titles, tr, today).single;
      expect(i.trCategory, TrErrorCategory.article);
      expect(i.label, contains('Artikel'));
      expect(i.dropPercent, 75);
    });
  });

  group('hata dedektörü history', () {
    test('keeps each category once per check, the sentence and the check count', () {
      final tr = const TrErrorLog().record(today, [
        err(TrErrorCategory.article, 'a apple', 'I ate an apple.'),
        err(TrErrorCategory.article, 'a egg', 'I ate an egg.'),
        err(TrErrorCategory.tense, 'eat', 'I ate an apple yesterday.'),
      ], text: 'I eat a apple yesterday. ');
      expect(tr.events.map((e) => e.category), [TrErrorCategory.article, TrErrorCategory.tense]);
      expect(tr.events.first.text, 'I eat a apple yesterday.');
      expect(tr.checks, {today: 1});
      final again = tr.record(today, const []);
      expect(again.checks, {today: 2});
      expect(again.events.length, 2);
      final back = TrErrorLog.fromJson(jsonDecode(jsonEncode(again.toJson())) as Map<String, dynamic>);
      expect(back.events.last.corrected, 'I ate an apple yesterday.');
      expect(back.checks, {today: 2});
    });

    test('is capped', () {
      var tr = const TrErrorLog();
      for (var i = 0; i < maxTrErrorEvents + 5; i++) {
        tr = tr.record(today, [err(TrErrorCategory.plural, 'w$i', 'f')]);
      }
      expect(tr.events.length, maxTrErrorEvents);
      expect(tr.events.last.wrong, 'w${maxTrErrorEvents + 4}');
    });

    test('patterns: most frequent first, each with the newest example', () {
      var tr = const TrErrorLog();
      tr = tr.record(ago(3), [err(TrErrorCategory.article, 'old', 'old fix')]);
      tr = tr.record(ago(1), [err(TrErrorCategory.article, 'new', 'new fix')], text: 'new sentence');
      final p = trPatterns({'article': 5, 'toBe': 9, 'nonsense': 3}, tr);
      expect(p.map((x) => x.category), [TrErrorCategory.toBe, TrErrorCategory.article]);
      expect(p.first.example, isNull);
      expect(p[1].example!.wrong, 'new');
      expect(p[1].example!.text, 'new sentence');
      // Every category has a rule and a habit.
      for (final c in TrErrorCategory.values) {
        expect(trRuleAndHabit[c], isNotNull, reason: c.name);
      }
    });

    test('recordTrErrors fills the history with the learner text', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs), clockProvider.overrideWithValue(() => now)],
      );
      addTearDown(c.dispose);
      c
          .read(progressProvider.notifier)
          .recordTrErrors(detectTrErrors('He go to school.'), text: 'He go to school.');
      final tr = c.read(trErrorLogProvider);
      expect(tr.checks[today], 1);
      expect(tr.events.single.text, 'He go to school.');
      expect(c.read(progressProvider).errorStats[tr.events.single.category.name], 1);
      expect(prefs.getString('tr_error_log_v1'), isNotNull);
    });
  });

  group('exam estimate', () {
    List<AnswerLog> lgs(int right, int wrong) => [
      for (var i = 0; i < right + wrong; i++)
        AnswerLog(
          key: 'lgs_vocab_$i',
          day: today,
          correct: i < right,
          seconds: 40,
          type: 'vocabulary',
          source: 'bank',
        ),
    ];

    test('LGS: nothing with too few answers', () {
      expect(estimateLgsNet(lgs(10, 9)), isNull);
      // Answers of other exams do not count.
      expect(estimateLgsNet([...lgs(10, 5), ...many('ys1u1', 'grammar', 20, 0)]), isNull);
    });

    test('LGS: a range around the net, inside 0–10, narrower with more answers', () {
      for (final (r, w) in [(20, 0), (0, 20), (15, 5), (60, 20), (10, 10)]) {
        final n = estimateLgsNet(lgs(r, w))!;
        expect(n.low, inInclusiveRange(0, 10));
        expect(n.high, inInclusiveRange(0, 10));
        expect(n.low, lessThanOrEqualTo(n.mid.floor()));
        expect(n.high, greaterThanOrEqualTo(n.mid.ceil()));
        expect(n.basis, r + w);
      }
      // 75% right: 10 × (0.75 − 0.25/3) = 6.67 net.
      expect(estimateLgsNet(lgs(15, 5))!.mid, closeTo(6.67, 0.01));
      final few = estimateLgsNet(lgs(15, 5))!, more = estimateLgsNet(lgs(150, 50))!;
      expect(more.high - more.low, lessThan(few.high - few.low));
      expect(estimateLgsNet(lgs(0, 30))!.low, 0);
      expect(estimateLgsNet(lgs(30, 0))!.high, 10);
    });

    test('answers are told apart by exam', () {
      const yd = AnswerLog(key: 'yds_g_1', day: '', correct: true, seconds: 1, source: 'mock:yds_m1@1');
      const lg = AnswerLog(key: 'lgs_1', day: '', correct: true, seconds: 1, source: 'mock:lgs@1');
      const path = AnswerLog(key: 'ls1u1l1#0', day: '', correct: true, seconds: 1, unitId: 'ls1u1');
      expect((isYdsAnswer(yd), isLgsAnswer(yd)), (true, false));
      expect((isYdsAnswer(lg), isLgsAnswer(lg)), (false, true));
      expect((isYdsAnswer(path), isLgsAnswer(path)), (false, true));
    });
  });

  group('targeted drill', () {
    final unit = yds.units.firstWhere((u) => u.nodes.where((n) => n.type == NodeType.lesson).length >= 2);
    final unitKeys = {
      for (final n in unit.nodes)
        for (final it in lessonItems(n)) it.key,
    };

    test('a topic drill: 5–10 questions of that topic, wrong ones first', () {
      final wrong = unitKeys
          .where((k) => !ungradedTypes.contains(lessonItems(unit.nodes.first).first.ex.type))
          .take(3)
          .toSet();
      final items = drillItems(yds, unitId: unit.id, wrongKeys: wrong, random: Random(1));
      expect(items.length, inInclusiveRange(5, 10));
      expect(items.every((it) => unitKeys.contains(it.key)), isTrue);
      expect(
        items.every((it) => !ungradedTypes.contains(it.ex.type) && it.ex.type != ExerciseType.match),
        isTrue,
      );
      final gradedWrong = items.where((it) => wrong.contains(it.key)).length;
      expect(items.take(gradedWrong).every((it) => wrong.contains(it.key)), isTrue);
      expect(items.map((it) => it.key).toSet().length, items.length);
    });

    test('a type drill: only that type, from studied units when they have enough', () {
      final items = drillItems(yds, typeKey: QType.cloze.name, seenUnits: {'ys3u1'}, random: Random(2));
      expect(items.length, inInclusiveRange(5, 10));
      for (final it in items) {
        final u = yds.units.firstWhere((u) => u.nodes.any((n) => it.key.startsWith('${n.id}#')));
        expect(itemTypeKey(it.ex, unitId: u.id), QType.cloze.name);
        expect(u.id, 'ys3u1');
      }
    });

    test('nothing when too few questions fit', () {
      expect(drillItems(yds, typeKey: 'no-such-type'), isEmpty);
      expect(drillItems(yds, unitId: unit.id, minCount: 10000), isEmpty);
    });

    test('the weekly plan drills topics and types, and names the top habit', () {
      final f = weeklyFocus(
        [
          const Bucket('u2', 'Articles', 10, 7),
          const Bucket('u3', 'Past', 10, 5),
          const Bucket('u1', 'X', 9, 2),
        ],
        [const Bucket('cloze', 'Cloze test', 10, 6)],
        [TrPattern(TrErrorCategory.toBe, 4, null)],
      );
      expect(f.map((x) => x.label), ['Articles', 'Past', 'Cloze test', TrErrorCategory.toBe.label]);
      expect(f.map((x) => x.drillable), [true, true, true, false]);
      expect(f.first.detail, startsWith('%30 doğru'));
    });
  });

  group('screen', () {
    // A log over the first units of the YDS path, two weeks.
    final units = yds.units.take(3).map((u) => u.id).toList();
    final log = [
      ...many(units[0], 'grammar', 3, 7, day: ago(20)),
      ...many(units[2], 'cloze', 6, 4, day: ago(9)),
      ...many(units[0], 'grammar', 7, 3, day: ago(1)),
      ...many(units[1], 'vocabulary', 4, 6),
      ...many(units[2], 'cloze', 9, 1),
    ];

    Future<void> pump(
      WidgetTester tester, {
      required bool premium,
      List<AnswerLog> answers = const [],
      Map<String, int> errorStats = const {},
      AppMode mode = AppMode.adult,
      Brightness brightness = Brightness.light,
      String track = 'yds',
    }) async {
      final tr = const TrErrorLog().record(today, [
        err(TrErrorCategory.article, 'a apple', 'I want an apple.'),
      ], text: 'I want a apple.');
      SharedPreferences.setMockInitialValues({
        'progress_v1': jsonEncode(
          Progress(onboarded: true, remindersEnabled: false, trackId: track, errorStats: errorStats).toJson(),
        ),
        'study_log_v1': jsonEncode(StudyLog(answers: answers).toJson()),
        if (errorStats.isNotEmpty) 'tr_error_log_v1': jsonEncode(tr.toJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 2600));
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
          premiumDevOverrideProvider.overrideWithValue(premium),
          billingServiceProvider.overrideWithValue(FakeBilling()),
        ],
      );
      addTearDown(c.dispose);
      await c.read(courseProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildTheme(mode: mode, brightness: brightness),
            home: const ErrorAnalysisScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('little data: a friendly empty state with what is left', (tester) async {
      await pump(tester, premium: true, answers: many(units[0], 'grammar', 5, 3));
      expect(find.byKey(const Key('analysis-empty')), findsOneWidget);
      expect(find.text('3 ders daha çöz, analizin açılsın'), findsOneWidget);
      expect(find.byKey(const Key('analysis-summary')), findsNothing);
    });

    testWidgets('free: summary and the top mistake, the rest blurred behind Premium ile aç', (tester) async {
      await pump(tester, premium: false, answers: log, errorStats: const {'article': 4});
      expect(find.byKey(const Key('analysis-summary')), findsOneWidget);
      expect(find.byKey(const Key('analysis-top-error')), findsOneWidget);
      // The free card shows the learner's own sentence.
      expect(find.textContaining('I want an apple.'), findsWidgets);
      expect(find.byKey(const Key('analysis-locked')), findsOneWidget);
      // The preview is built from their data, but cannot be touched.
      final weak = find.byKey(const Key('analysis-weak'));
      expect(weak, findsOneWidget);
      expect(find.ancestor(of: weak, matching: find.byType(ImageFiltered)), findsOneWidget);
      expect(find.ancestor(of: weak, matching: find.byType(IgnorePointer)), findsWidgets);
      expect(find.byKey(const Key('analysis-teaser')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('analysis-teaser'))).data,
        allOf(contains('zayıf nokta'), contains('çalışma planı')),
      );
      await tester.tap(find.byKey(const Key('analysis-unlock')));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(
        find.textContaining('“Detaylı hata analizi ve tahmini puan” Premium ile açılır'),
        findsOneWidget,
      );
    });

    testWidgets('Premium: every card, unblurred, and a plan item starts a drill', (tester) async {
      await pump(tester, premium: true, answers: log, errorStats: const {'article': 4});
      expect(find.byKey(const Key('analysis-locked')), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
      // Weakest topic first with its percentage.
      expect(find.text('%40'), findsWidgets);
      expect(find.textContaining('hatan %57 azald'), findsWidgets);
      for (final k in ['weak', 'trend', 'patterns', 'heatmap', 'estimate', 'plan']) {
        await tester.scrollUntilVisible(
          find.byKey(Key('analysis-$k')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byKey(Key('analysis-$k')), findsOneWidget, reason: k);
      }
      await tester.scrollUntilVisible(
        find.byKey(const Key('focus-drill-0')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('focus-drill-0')));
      await tester.pumpAndSettle();
      final lesson = tester.widget<LessonScreen>(find.byType(LessonScreen));
      expect(lesson.items.length, inInclusiveRange(5, 10));
      expect(lesson.logSource, 'targeted');
    });

    testWidgets('dark theme: every card draws without errors', (tester) async {
      await pump(
        tester,
        premium: true,
        answers: log,
        errorStats: const {'article': 4},
        brightness: Brightness.dark,
      );
      expect(find.byKey(const Key('analysis-summary')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no estimate outside YDS and LGS', (tester) async {
      await pump(tester, premium: true, answers: log, track: 'tr_en');
      expect(find.byKey(const Key('analysis-estimate')), findsNothing);
    });

    testWidgets('Çocuk modu: Pofuduk, never Çaycı Dayı', (tester) async {
      await pump(tester, premium: true, answers: many(units[0], 'grammar', 2, 2), mode: AppMode.kid);
      expect(find.byType(Pofuduk), findsOneWidget);
      expect(find.byType(Dayi), findsNothing);
    });
  });
}
