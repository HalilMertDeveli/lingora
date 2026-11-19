import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/goals/exam_countdown_plan.dart';
import 'package:lingora/goals/goal_paywall_copy.dart';
import 'package:lingora/goals/learn_goal.dart';
import 'package:lingora/screens/paywall_screen.dart';
import 'package:lingora/services/billing/products.dart';
import 'package:lingora/services/firebase/progress_merge.dart';
import 'package:lingora/study/question_types.dart';

import 'premium_test.dart' show FakeBilling, app, now, widgetOverrides;

LearnGoal examGoal({String? date, GoalExam exam = GoalExam.yds}) =>
    LearnGoal(kind: GoalKind.exam, exam: exam, examDate: date, at: 1);

void main() {
  group('score estimate', () {
    test('every question weighs the same, 100 in total', () {
      expect(estimatedYdsScore(correct: 60, total: 80), 75);
      expect(estimatedYdsScore(correct: 61, total: 80), 76.25);
      expect(estimatedYdsScore(correct: 80, total: 80), 100);
      expect(estimatedYdsScore(correct: 0, total: 80), 0);
      // A 40-question mock: 2,5 points each.
      expect(estimatedYdsScore(correct: 30, total: 40), 75);
      expect(estimatedYdsScore(correct: 3, total: 0), 0);
    });

    test('Turkish formatting', () {
      expect(formatScore(75), '75');
      expect(formatScore(76.25), '76,25');
      expect(formatScore(72.5), '72,5');
    });
  });

  group('countdown plan', () {
    final today = DateTime(2026, 11, 18, 9);
    const lessons = {
      QType.reading: [
        PlanLink(PlanItemKind.lesson, 'Okuma 1', ref: 'ys3u5'),
        PlanLink(PlanItemKind.lesson, 'Okuma 2', ref: 'ys3u6'),
      ],
      QType.cloze: [PlanLink(PlanItemKind.lesson, 'Cloze', ref: 'ys3u1')],
    };
    const practice = {
      QType.reading: [PlanLink(PlanItemKind.practice, 'Okuma: 10 soru', ref: 'yds_reading')],
      QType.cloze: [PlanLink(PlanItemKind.practice, 'Cloze: 10 soru', ref: 'yds_cloze')],
    };

    test('nothing to plan on or after the exam day', () {
      expect(buildCountdownPlan(today: today, daysLeft: 0, weak: const []).isEmpty, isTrue);
      expect(buildCountdownPlan(today: today, daysLeft: -3, weak: const []).isEmpty, isTrue);
    });

    test('one day per day left, dated from today, the eve last', () {
      final p = buildCountdownPlan(today: today, daysLeft: 20, weak: const [(QType.reading, 4)]);
      expect(p.days, hasLength(20));
      expect(p.days.first.date, DateTime(2026, 11, 18));
      expect(p.days.last.date, DateTime(2026, 12, 7));
      expect(p.days.last.kind, CountdownDayKind.eve);
      expect([for (final d in p.days) d.index], List.generate(20, (i) => i));
    });

    test('without a mock: day 1 is a mock and the exam mix sets the weights', () {
      final p = buildCountdownPlan(today: today, daysLeft: 30, weak: const []);
      expect(p.days.first.kind, CountdownDayKind.mock);
      expect(p.days[1].kind, CountdownDayKind.analysis);
      expect(p.weights.first.$1, QType.reading); // 20 of 80 questions
      expect(p.weights.map((w) => w.$1), isNot(contains(QType.other)));
    });

    test('YÖKDİL mix has no dialogue or restatement days', () {
      final p = buildCountdownPlan(today: today, daysLeft: 40, weak: const [], mix: ExamMix.yokdil);
      final types = p.focusDays.keys.toSet();
      expect(types, isNot(contains(QType.dialogue)));
      expect(types, isNot(contains(QType.restatement)));
    });

    test('weak types get days in proportion to their gap, interleaved', () {
      final p = buildCountdownPlan(
        today: today,
        daysLeft: 60,
        weak: const [(QType.reading, 6), (QType.cloze, 3), (QType.grammar, 0)],
        lessons: lessons,
        practice: practice,
      );
      final f = p.focusDays;
      expect(f.keys.toSet(), {QType.reading, QType.cloze});
      // 2:1 gap → about 2:1 days.
      expect(f[QType.reading]! / f[QType.cloze]!, closeTo(2, 0.35));
      // Never more than two of the same focus in a row.
      final seq = [for (final d in p.days) ?d.focus];
      for (var i = 2; i < seq.length; i++) {
        expect(seq[i] == seq[i - 1] && seq[i] == seq[i - 2], isFalse);
      }
    });

    test('a full mock every week, none in the last two days', () {
      final p = buildCountdownPlan(today: today, daysLeft: 30, weak: const [(QType.reading, 5)]);
      final mocks = [
        for (final d in p.days)
          if (d.kind == CountdownDayKind.mock) d.index,
      ];
      expect(mocks, [7, 14, 21]);
      for (final m in mocks) {
        expect(p.days[m + 1].kind, CountdownDayKind.analysis);
      }
      expect(p.days[28].kind, isNot(CountdownDayKind.mock));
    });

    test('study days link existing lessons and practice, cycling through them', () {
      final p = buildCountdownPlan(
        today: today,
        daysLeft: 12,
        weak: const [(QType.reading, 4)],
        lessons: lessons,
        practice: practice,
      );
      final study = p.days.where((d) => d.kind == CountdownDayKind.study).toList();
      expect(study.first.items.first, lessons[QType.reading]![0]);
      expect(study[1].items.first, lessons[QType.reading]![1]);
      expect(study.first.items, contains(practice[QType.reading]![0]));
      expect(study.first.items.last.kind, PlanItemKind.review);
    });

    test('a far exam is planned for the first $maxCountdownDays days', () {
      final p = buildCountdownPlan(today: today, daysLeft: 200, weak: const [(QType.reading, 2)]);
      expect(p.days, hasLength(maxCountdownDays));
      expect(p.daysLeft, 200);
      expect(p.days.any((d) => d.kind == CountdownDayKind.eve), isFalse);
    });

    test('one day left: only the eve-free study day', () {
      final p = buildCountdownPlan(today: today, daysLeft: 1, weak: const [(QType.reading, 2)]);
      expect(p.days, hasLength(1));
      expect(p.days.single.kind, isNot(CountdownDayKind.mock));
    });
  });

  group('paywall copy per goal', () {
    final at = DateTime(2026, 11, 18, 20);

    test('exam with a date counts the days', () {
      final c = goalPaywallCopy(examGoal(date: '2027-01-04'), at);
      expect(c.title, "YDS'ye 47 gün kaldı, planın hazır.");
      expect(c.focus.first, PremiumFeature.unlimitedMockExams);
      expect(c.outcomes, isNotEmpty);
    });

    test('YÖKDİL takes the right suffix', () {
      final c = goalPaywallCopy(examGoal(date: '2026-11-28', exam: GoalExam.yokdil), at);
      expect(c.title, "YÖKDİL'e 10 gün kaldı, planın hazır.");
    });

    test('exam without a date, on the day, after it', () {
      expect(goalPaywallCopy(examGoal(), at).title, "YDS'ye hazır gir, planın hazır.");
      expect(goalPaywallCopy(examGoal(date: '2026-11-18'), at).title, 'YDS günü geldi. Başarılar!');
      expect(goalPaywallCopy(examGoal(date: '2026-10-01'), at).title, 'Sıradaki YDS için planın hazır.');
    });

    test('interview: rehearsal and feedback, never a score', () {
      final c = goalPaywallCopy(const LearnGoal(kind: GoalKind.interview), at);
      expect(c.title, 'Mülakatına hazır gir: gerçek prova + kişisel geri bildirim');
      expect(c.focus, contains(PremiumFeature.aiConversation));
      for (final line in [c.title, c.subtitle, ...c.outcomes]) {
        expect(line.toLowerCase(), isNot(contains('puan')));
      }
    });

    test('speaking and general', () {
      expect(goalPaywallCopy(const LearnGoal(kind: GoalKind.speaking), at).focus, [
        PremiumFeature.aiConversation,
        PremiumFeature.pronunciationScore,
      ]);
      expect(goalPaywallCopy(null, at).title, 'Daha fazla konuş, daha çok deneme çöz');
      expect(goalPaywallCopy(null, at, variantB: true).title, 'Konuşarak öğren, sınırsız deneme çöz');
      expect(goalPaywallCopy(const LearnGoal(kind: GoalKind.general), at).focus, isEmpty);
    });
  });

  group('learn goal', () {
    test('days left, JSON round trip and Progress', () {
      final g = examGoal(date: '2027-01-04');
      expect(g.daysLeft(DateTime(2026, 11, 18, 23, 59)), 47);
      expect(const LearnGoal(kind: GoalKind.interview).daysLeft(DateTime(2026)), isNull);
      expect(LearnGoal.fromJson(g.toJson()), g);
      // The date is dropped for non-exam goals.
      expect(
        const LearnGoal(kind: GoalKind.speaking, examDate: '2027-01-01').toJson().containsKey('examDate'),
        isFalse,
      );
      final p = Progress.fromJson(jsonDecode(jsonEncode(const Progress().copyWith(learnGoal: g).toJson())));
      expect(p.learnGoal, g);
      expect(Progress.fromJson(const {}).learnGoal, isNull);
    });

    test('sync: the later choice wins, a missing one never erases', () {
      const older = LearnGoal(kind: GoalKind.general, at: 1);
      const newer = LearnGoal(kind: GoalKind.interview, at: 2);
      final a = const Progress().copyWith(learnGoal: older);
      final b = const Progress().copyWith(learnGoal: newer);
      expect(mergeProgress(a, b, localNewer: true).learnGoal, newer);
      expect(mergeProgress(b, a, localNewer: false).learnGoal, newer);
      expect(mergeProgress(const Progress(), b, localNewer: true).learnGoal, newer);
    });
  });

  group('paywall screen', () {
    Future<void> pumpWith(WidgetTester tester, LearnGoal? goal, {FakeBilling? billing}) async {
      final prefs = <String, Object>{
        if (goal != null)
          'progress_v1': jsonEncode(const Progress(onboarded: true).copyWith(learnGoal: goal).toJson()),
      };
      await tester.pumpWidget(
        app(await widgetOverrides(tester, billing ?? FakeBilling(), prefs: prefs), const PaywallScreen()),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('exam goal: countdown hero, value line, focus features first', (tester) async {
      // `now` in premium_test is 2026-11-10.
      expect(now, DateTime(2026, 11, 10, 12));
      await pumpWith(tester, examGoal(date: '2026-12-27'));
      expect(find.text("YDS'ye 47 gün kaldı, planın hazır."), findsOneWidget);
      expect(find.byKey(const ValueKey('paywall-value-line')), findsOneWidget);
      expect(find.text(paywallValueLine), findsOneWidget);
      final mocks = tester.getTopLeft(find.text(PremiumFeature.unlimitedMockExams.title)).dy;
      final chat = tester.getTopLeft(find.text(PremiumFeature.aiConversation.title)).dy;
      expect(mocks, lessThan(chat));
      for (final f in PremiumFeature.values) {
        expect(find.text(f.title), findsOneWidget);
      }
      for (final (_, title, _) in extraPremiumBullets) {
        expect(find.text(title), findsOneWidget);
      }
      // Store prices loaded: no anchor text.
      expect(find.byKey(const ValueKey('paywall-price-anchor')), findsNothing);
    });

    testWidgets('interview goal headline', (tester) async {
      await pumpWith(tester, const LearnGoal(kind: GoalKind.interview));
      expect(find.text('Mülakatına hazır gir: gerçek prova + kişisel geri bildirim'), findsOneWidget);
    });

    testWidgets('no store prices: the anchor and the trial, display only', (tester) async {
      await pumpWith(tester, null, billing: FakeBilling(available: false));
      expect(find.byKey(const ValueKey('paywall-price-anchor')), findsOneWidget);
      expect(find.text(paywallPriceAnchor), findsOneWidget);
      expect(find.textContaining('7 gün ücretsiz'), findsOneWidget);
    });
  });
}
