// Premium güçlendirmeleri: Telaffuz puanı kartı, "Neden yanlış?" sorusuna
// devam, haftalık koç mesajı (mantık, kart, bildirim) ve paylaşım kartı.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/pronunciation_feedback.dart';
import 'package:lingora/core/tr_errors.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/level_report.dart';
import 'package:lingora/data/placement.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/share_card.dart';
import 'package:lingora/screens/weekly_coach_card.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/explain_more.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/study/study_state.dart';
import 'package:lingora/study/tr_error_log.dart';
import 'package:lingora/study/weekly_coach.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/ui/explain_more.dart';
import 'package:lingora/ui/mascot.dart' show Dayi;
import 'package:lingora/ui/pronunciation_score.dart';
import 'package:lingora/ui/share_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'premium_test.dart' show FakeBilling;
import 'study_test.dart' show readCourse;
import 'widget_test.dart' show FakeNotifications, FakeSpeech;

final yds = readCourse('exam_yds');

/// A Monday: the coach looks at 9–15 Nov, and compares with 2–8 Nov.
final monday = DateTime(2026, 11, 16, 9);

AnswerLog ans(String unit, String type, bool ok, String day, [int i = 0]) =>
    AnswerLog(key: '$unit#$type#$i', day: day, correct: ok, seconds: 20, type: type, unitId: unit);

List<AnswerLog> many(String unit, String type, String day, int total, int wrong) => [
  for (var i = 0; i < total; i++) ans(unit, type, i >= wrong, day, i),
];

class FakeExplain implements ExplainMoreService {
  final asked = <(ExplainMode, String, int)>[];
  @override
  Future<ExplainAnswer> ask(
    ExplainQuestion q,
    ExplainMode mode, {
    String text = '',
    List<ExplainTurn> history = const [],
  }) async {
    asked.add((mode, text, history.length));
    return ExplainAnswer('She tek kişi, o yüzden goes (${mode.name}).', remaining: 29);
  }
}

Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  Widget home, {
  bool premium = false,
  Map<String, Object> prefsValues = const {},
  AppMode mode = AppMode.adult,
  DateTime? now,
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    'progress_v1': jsonEncode(const Progress(onboarded: true, remindersEnabled: false).toJson()),
    ...prefsValues,
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 1600));
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
      clockProvider.overrideWithValue(() => now ?? monday),
      courseProvider.overrideWith((ref) async => yds),
      premiumDevOverrideProvider.overrideWithValue(premium),
      billingServiceProvider.overrideWithValue(FakeBilling()),
      ...overrides,
    ],
  );
  addTearDown(c.dispose);
  await c.read(courseProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildTheme(mode: mode),
        home: Scaffold(body: SingleChildScrollView(child: home)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  final u0 = yds.units[0].id, u1 = yds.units[1].id, u2 = yds.units[2].id;
  final titles = {for (final u in yds.units) u.id: u.title};

  group('Telaffuz puanı kartı', () {
    final feedback = pronunciationFeedback('I think three is enough', [
      (words: 'I tink tree is enough', confidence: 0.8),
    ]);

    testWidgets('Premium: every problem word with its sound tip and no percentage', (tester) async {
      await pumpApp(tester, PronunciationScoreCard(feedback: feedback, onOpenUnit: (_) {}), premium: true);
      expect(find.byKey(const Key('pron-score')), findsOneWidget);
      expect(find.byKey(const Key('pron-count-ok')), findsOneWidget);
      expect(find.text('3 doğru'), findsOneWidget);
      expect(find.text('2 şu ses zor'), findsOneWidget);
      expect(find.byKey(const Key('pron-word-think')), findsOneWidget);
      expect(find.byKey(const Key('pron-word-three')), findsOneWidget);
      expect(find.textContaining('th sesi (think)'), findsNWidgets(2));
      expect(find.byKey(const Key('pron-unit-think')), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.byKey(const ValueKey('premium-offer-pronunciation_score')), findsNothing);
    });

    testWidgets('free: the first problem word only, then the Premium card', (tester) async {
      await pumpApp(tester, PronunciationScoreCard(feedback: feedback));
      expect(find.byKey(const Key('pron-word-think')), findsOneWidget);
      expect(find.byKey(const Key('pron-word-three')), findsNothing);
      expect(find.textContaining('th sesi'), findsNothing);
      expect(find.byKey(const ValueKey('premium-offer-pronunciation_score')), findsOneWidget);
    });

    testWidgets('nothing heard draws nothing; all clear says so', (tester) async {
      await pumpApp(
        tester,
        Column(
          children: [
            PronunciationScoreCard(feedback: pronunciationFeedback('Hello', const [])),
            PronunciationScoreCard(
              feedback: pronunciationFeedback('Good morning', [(words: 'good morning', confidence: 0.3)]),
            ),
          ],
        ),
        premium: true,
      );
      expect(find.byKey(const Key('pron-score')), findsOneWidget);
      expect(find.textContaining('net anlaşıldı'), findsOneWidget);
      expect(find.byKey(const Key('pron-low-confidence')), findsOneWidget);
    });
  });

  group('"Neden yanlış?" sorusuna devam', () {
    const q = ExplainQuestion(
      question: 'She ---- to school every day.',
      options: ['go', 'goes', 'going', 'gone'],
      answer: 1,
      picked: 0,
      explanation: 'he/she/it ile -s.',
    );

    testWidgets('Premium asks, shows the answer and caps at three', (tester) async {
      final fake = FakeExplain();
      await pumpApp(
        tester,
        const ExplainMoreBox(question: q),
        premium: true,
        overrides: [explainMoreServiceProvider.overrideWithValue(fake)],
      );
      await tester.tap(find.byKey(const Key('explain-confused')));
      await tester.pumpAndSettle();
      expect(find.textContaining('(confused)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('explain-question')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('explain-input')), 'Neden going olmaz?');
      await tester.tap(find.byKey(const Key('explain-send')));
      await tester.pumpAndSettle();
      expect(fake.asked.last, (ExplainMode.question, 'Neden going olmaz?', 1));
      expect(find.text('Neden going olmaz?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('explain-simpler')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('explain-answer-2')), findsOneWidget);
      expect(find.byKey(const Key('explain-confused')), findsNothing);
      expect(find.textContaining('hakkı bitti'), findsOneWidget);
    });

    testWidgets('free users get the Premium card and no call', (tester) async {
      final fake = FakeExplain();
      await pumpApp(
        tester,
        const ExplainMoreBox(question: q),
        overrides: [explainMoreServiceProvider.overrideWithValue(fake)],
      );
      expect(find.byKey(const ValueKey('premium-offer-explain_more')), findsNothing);
      await tester.tap(find.byKey(const Key('explain-simpler')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('premium-offer-explain_more')), findsOneWidget);
      expect(fake.asked, isEmpty);
    });

    testWidgets('signed out: says why', (tester) async {
      await pumpApp(tester, const ExplainMoreBox(question: q), premium: true);
      await tester.tap(find.byKey(const Key('explain-confused')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('explain-error')), findsOneWidget);
    });

    testWidgets('Çocuk modu has no AI box', (tester) async {
      await pumpApp(tester, const ExplainMoreBox(question: q), premium: true, mode: AppMode.kid);
      expect(find.byKey(const Key('explain-more')), findsNothing);
    });

    test('a passage is shortened into the question', () {
      expect(explainQuestionText('Q?'), 'Q?');
      final t = explainQuestionText('Q?', passage: 'word ' * 300);
      expect(t.length, lessThan(700));
      expect(t, endsWith('…\n\nQ?'));
    });
  });

  group('haftalık koç mesajı', () {
    final lastWeek = [
      ...many(u0, 'grammar', '2026-11-10', 10, 5),
      ...many(u1, 'vocabulary', '2026-11-12', 8, 2),
      ...many(u2, 'reading', '2026-11-14', 6, 1),
    ];
    final weekBefore = [...many(u1, 'vocabulary', '2026-11-04', 8, 6)];
    final trLog = const TrErrorLog().record('2026-11-11', [
      TrError(
        ruleId: 'r',
        category: TrErrorCategory.article,
        wrong: 'a apple',
        corrected: 'an apple',
        explanation: 'neden',
      ),
    ], text: 'I want a apple.');

    test('mondayOf and the reviewed week', () {
      expect(mondayOf(DateTime(2026, 11, 19)), '2026-11-16');
      expect(mondayOf(DateTime(2026, 11, 16)), '2026-11-16');
      expect(mondayOf(DateTime(2026, 11, 22)), '2026-11-16');
    });

    test('top 3 mistakes, what improved and a drillable focus', () {
      final m = buildWeeklyCoach(
        log: [...weekBefore, ...lastWeek],
        titles: titles,
        trLog: trLog,
        now: monday,
      )!;
      expect(m.weekKey, '2026-11-16');
      expect((m.from, m.to), ('2026-11-09', '2026-11-15'));
      expect(m.answered, 24);
      expect(m.activeDays, 3);
      expect(m.top, hasLength(3));
      expect(m.top.first.label, titles[u0]);
      expect(m.top.first.wrong, 5);
      expect(m.top.where((t) => t.kind == CoachPatternKind.topic).length, lessThanOrEqualTo(2));
      expect(m.improved, contains('geçen hafta 8 soruda 6 yanlış, bu hafta 8 soruda 2 yanlış'));
      expect(m.focus?.drillable, isTrue);
      expect(m.focus?.unitId, u0);
    });

    test('too little practice gives no message', () {
      expect(
        buildWeeklyCoach(
          log: many(u0, 'grammar', '2026-11-10', 5, 2),
          titles: titles,
          trLog: const TrErrorLog(),
          now: monday,
        ),
        isNull,
      );
      // Answers from this week do not count for last week's message.
      expect(
        buildWeeklyCoach(
          log: many(u0, 'grammar', '2026-11-16', 20, 2),
          titles: titles,
          trLog: const TrErrorLog(),
          now: monday,
        ),
        isNull,
      );
    });

    Map<String, Object> seeded() => {
      'study_log_v1': jsonEncode(StudyLog(answers: [...weekBefore, ...lastWeek]).toJson()),
    };

    testWidgets('Premium: full card, one-tap start, closing hides it for the week', (tester) async {
      final c = await pumpApp(tester, const WeeklyCoachCard(), premium: true, prefsValues: seeded());
      expect(find.byKey(const Key('weekly-coach')), findsOneWidget);
      expect(find.byKey(const Key('coach-pattern-0')), findsOneWidget);
      expect(find.byKey(const Key('coach-pattern-2')), findsOneWidget);
      expect(find.byKey(const Key('coach-improved')), findsOneWidget);
      expect(find.byKey(const Key('coach-locked')), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const Key('coach-start'))).onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('coach-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('weekly-coach')), findsNothing);
      expect(c.read(prefsProvider).getString(WeeklyCoachSeen.key), '2026-11-16');
    });

    testWidgets('free: the numbers and the top mistake, the rest blurred', (tester) async {
      await pumpApp(tester, const WeeklyCoachCard(), prefsValues: seeded());
      expect(find.byKey(const Key('coach-stats')), findsOneWidget);
      expect(find.byKey(const Key('coach-pattern-0')), findsOneWidget);
      expect(find.byKey(const Key('coach-locked')), findsOneWidget);
      expect(find.byKey(const ValueKey('premium-offer-weekly_coach')), findsOneWidget);
    });

    testWidgets('Çocuk modu: Pofuduk, no Çaycı Dayı', (tester) async {
      await pumpApp(tester, const WeeklyCoachCard(), premium: true, prefsValues: seeded(), mode: AppMode.kid);
      expect(find.byKey(const Key('weekly-coach')), findsOneWidget);
      expect(find.byType(Dayi), findsNothing);
    });

    test('the Monday notification follows the switch and reminders', () {
      const p = Progress(onboarded: true, remindersEnabled: true, reminderMinutes: 19 * 60);
      final thursday = DateTime(2026, 11, 19, 12);
      final plan = planNotifications(p, thursday, weeklyCoach: true);
      final coach = plan.where((n) => n.id == weeklyCoachNotificationId).single;
      expect(coach.when, DateTime(2026, 11, 23, weeklyCoachHour));
      // Monday before 10:00: today's.
      expect(
        planNotifications(p, DateTime(2026, 11, 23, 8), weeklyCoach: true).last.when,
        DateTime(2026, 11, 23, weeklyCoachHour),
      );
      expect(planNotifications(p, thursday).where((n) => n.id == weeklyCoachNotificationId), isEmpty);
      expect(
        planNotifications(
          const Progress(onboarded: true, remindersEnabled: false),
          thursday,
          weeklyCoach: true,
        ),
        isEmpty,
      );
    });
  });

  group('paylaşım kartı', () {
    LevelReport report(String day, Cefr level) => LevelReport(
      day: day,
      overall: level,
      skills: {for (final s in LevelSkill.values) s: SkillScore(level: level, right: 3, total: 4)},
    );
    final progress = Progress(
      onboarded: true,
      streak: 12,
      lastActiveDay: '2026-11-16',
      wordBox: const {'w1': 3, 'w2': 5, 'w3': 1},
      xpByDay: const {'2026-11-02': 40, '2026-11-10': 25, '2026-10-30': 99},
      levelReports: [report('2026-10-16', Cefr.a2), report('2026-11-16', Cefr.b1)],
    );

    test('milestone: level up headline, streak and known words', () {
      final d = buildShareCard(progress, monday);
      expect(d.headline, "B1'e çıktım!");
      expect(d.streak, 12);
      expect(d.wordsLearned, 2);
      expect(d.monthly, isFalse);
      expect(levelDative(Cefr.a2), "A2'ye");
      expect(
        buildShareCard(
          const Progress(onboarded: true, streak: 5, lastActiveDay: '2026-11-16'),
          monday,
        ).headline,
        '5 günlük seri!',
      );
    });

    test('monthly: active days, XP and the daily bars of this month only', () {
      final d = buildShareCard(progress, monday, monthly: true);
      expect(d.month, 'Kasım 2026');
      expect(d.activeDays, 2);
      expect(d.monthXp, 65);
      expect(d.dailyXp, hasLength(16));
    });

    Map<String, Object> seeded() => {'progress_v1': jsonEncode(progress.toJson())};

    testWidgets('free: shares the milestone card; the monthly one is Premium', (tester) async {
      await pumpApp(tester, const SizedBox(height: 900, child: ShareCardScreen()), prefsValues: seeded());
      expect(find.byKey(const Key('share-card')), findsOneWidget);
      expect(find.text("B1'e çıktım!"), findsOneWidget);
      expect(find.text('Çenebaz'), findsOneWidget);
      expect(find.byKey(const Key('share-card-share')), findsOneWidget);
      await tester.tap(find.text('Aylık kart'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('premium-offer-share_card')), findsOneWidget);
      expect(find.byKey(const Key('share-card-share')), findsNothing);
    });

    testWidgets('Premium: the monthly card can be shared', (tester) async {
      await pumpApp(
        tester,
        const SizedBox(height: 900, child: ShareCardScreen()),
        premium: true,
        prefsValues: seeded(),
      );
      await tester.tap(find.text('Aylık kart'));
      await tester.pumpAndSettle();
      expect(find.text('KASIM 2026'), findsOneWidget);
      expect(find.text('Bu ay 65 XP'), findsOneWidget);
      expect(find.text('Aylık kartı paylaş'), findsOneWidget);
    });
  });
}
