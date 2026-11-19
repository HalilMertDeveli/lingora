import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/app_settings.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/goals/learn_goal.dart';
import 'package:lingora/screens/daily_reading_screen.dart';
import 'package:lingora/screens/exam_season_card.dart';
import 'package:lingora/screens/growth_profile_section.dart';
import 'package:lingora/screens/invite_nudge.dart';
import 'package:lingora/screens/invite_screen.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/growth/analytics.dart';
import 'package:lingora/services/growth/daily_reading.dart';
import 'package:lingora/services/growth/exam_campaign.dart';
import 'package:lingora/services/growth/referral.dart';
import 'package:lingora/services/growth/remote_flags.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/services/talk_about.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'growth_test.dart' show FakeReferral;
import 'premium_test.dart' show FakeBilling, FakeSpeech;

/// 19 Nov 2026, noon in Türkiye.
final today = DateTime(2026, 11, 19, 12);

class FakeDailySource implements DailyReadingSource {
  FakeDailySource(this.readings, {this.offline = false});
  final Map<String, DailyReading> readings;
  bool offline;
  final calls = <String>[];

  @override
  Future<DailyReading?> fetch(String date, String level) async {
    calls.add('$date/$level');
    if (offline) throw StateError('offline');
    return readings['${date}_$level'];
  }
}

DailyReading reading(String date, String level, {String title = 'The Lost Umbrella'}) => DailyReading(
  date: date,
  level: level,
  title: title,
  text: 'One rainy morning a quiet neighbour found an umbrella.\n\nShe gave it back with a smile.',
  summaryTr: 'Bir şemsiye hikâyesi.',
  glossary: const [
    DailyGloss(word: 'rainy', meaningTr: 'yağmurlu'),
    DailyGloss(word: 'quiet', meaningTr: 'sessiz'),
    DailyGloss(word: 'neighbour', meaningTr: 'komşu'),
    DailyGloss(word: 'umbrella', meaningTr: 'şemsiye'),
    DailyGloss(word: 'smile', meaningTr: 'gülümseme'),
  ],
  questions: const [
    DailyQuestion(
      question: 'What did she find?',
      options: ['A cat', 'An umbrella', 'A key', 'A book'],
      answer: 1,
    ),
    DailyQuestion(question: 'Was it sunny?', options: ['Yes', 'No', 'Snowy', 'Windy'], answer: 1),
    DailyQuestion(
      question: 'Who found it?',
      options: ['A neighbour', 'A teacher', 'A child', 'A dog'],
      answer: 0,
    ),
  ],
  talkPrompt: 'Have you ever lost something?',
);

Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

const kidSettings = {'settings_v1': '{"mode":"kid"}'};

Future<List<Override>> overrides(
  WidgetTester? tester, {
  DateTime? at,
  bool premium = false,
  Map<String, Object> prefs = const {},
  DailyReadingSource? daily,
  ReferralService? referral,
  TalkAboutLauncher? talk,
}) async {
  if (tester != null) {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  final p = await prefsWith(prefs);
  return [
    prefsProvider.overrideWithValue(p),
    clockProvider.overrideWithValue(() => at ?? today),
    billingServiceProvider.overrideWithValue(FakeBilling()),
    premiumDevOverrideProvider.overrideWithValue(premium),
    analyticsSinkProvider.overrideWithValue(null),
    remoteConfigSourceProvider.overrideWithValue(null),
    referralServiceProvider.overrideWithValue(referral),
    speechProvider.overrideWithValue(FakeSpeech()),
    dailyReadingSourceProvider.overrideWithValue(daily),
    examCampaignScheduleProvider.overrideWith((ref) async => defaultExamCampaigns),
    talkAboutLauncherProvider.overrideWithValue(talk),
  ];
}

Widget host(List<Override> o, Widget child) => ProviderScope(
  overrides: o,
  child: MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

ProviderContainer containerOf(WidgetTester tester, Type t) =>
    ProviderScope.containerOf(tester.element(find.byType(t)));

void main() {
  group('exam season schedule', () {
    test('defaults carry the 2027 ÖSYM/MEB dates', () {
      expect(defaultExamCampaigns['yds']!.dates, ['2027-03-28', '2027-11-21']);
      expect(defaultExamCampaigns['yokdil']!.dates, ['2027-02-28', '2027-07-25']);
      expect(defaultExamCampaigns['lgs']!.dates, ['2027-06-13']);
    });

    test('the config doc overrides dates, weeks and the promo offer; bad values keep defaults', () {
      final s = parseExamCampaigns({
        'exams': {
          'yds': {
            'dates': ['2027-04-04', 'not a date'],
            'weeksBefore': 6,
            'promoOfferId': ' yds-2027 ',
          },
          'lgs': {'enabled': false},
          'toefl': {
            'dates': ['2027-01-01'],
          },
        },
      });
      expect(s['yds']!.dates, ['2027-04-04']);
      expect(s['yds']!.weeksBefore, 6);
      expect(s['yds']!.promoOfferId, 'yds-2027');
      expect(s['yds']!.label, 'YDS');
      expect(s['lgs']!.enabled, isFalse);
      expect(s['lgs']!.dates, ['2027-06-13']);
      expect(s['yokdil']!.dates, defaultExamCampaigns['yokdil']!.dates);
      expect(s.containsKey('toefl'), isFalse);
      expect(parseExamCampaigns(null), same(defaultExamCampaigns));
    });

    test('the window opens 8 weeks before and closes on exam day', () {
      final s = defaultExamCampaigns;
      // YDS on 28 Mar 2027: 8 weeks = 56 days before is 31 Jan.
      expect(examSeasonWindow(s, 'yds', DateTime(2027, 1, 30, 10)), isNull);
      final first = examSeasonWindow(s, 'yds', DateTime(2027, 1, 31, 10))!;
      expect(first.daysLeft, 56);
      expect(first.countdown, "YDS'ye 56 gün kaldı");
      expect(examSeasonWindow(s, 'yds', DateTime(2027, 3, 27, 23))!.daysLeft, 1);
      expect(examSeasonWindow(s, 'yds', DateTime(2027, 3, 28, 9)), isNull);
      expect(examSeasonWindow(s, 'yokdil', DateTime(2027, 2, 1))!.countdown, "YÖKDİL'e 27 gün kaldı");
      expect(examSeasonWindow(s, 'lgs', DateTime(2027, 5, 1))!.countdown, "LGS'ye 43 gün kaldı");
      // Not in a window today (19 Nov 2026), and no exam: nothing.
      expect(examSeasonWindow(s, 'yds', today), isNull);
      expect(examSeasonWindow(s, null, DateTime(2027, 3, 1)), isNull);
    });

    test('the goal decides the exam, else the exam track', () {
      expect(
        campaignExamFor(
          goal: const LearnGoal(kind: GoalKind.exam, exam: GoalExam.yokdil),
          trackId: 'lgs',
        ),
        'yokdil',
      );
      expect(
        campaignExamFor(
          goal: const LearnGoal(kind: GoalKind.speaking),
          trackId: 'lgs',
        ),
        'lgs',
      );
      expect(campaignExamFor(trackId: 'yds'), 'yds');
      expect(campaignExamFor(trackId: 'general'), isNull);
    });
  });

  group('exam season card', () {
    final inWindow = DateTime(2027, 2, 15, 12); // YDS 41 days away

    Future<ProviderContainer> pumpCard(
      WidgetTester tester, {
      bool premium = false,
      Map<String, Object> prefs = const {},
    }) async {
      await tester.pumpWidget(
        host(await overrides(tester, at: inWindow, premium: premium, prefs: prefs), const ExamSeasonCard()),
      );
      final c = containerOf(tester, ExamSeasonCard);
      c.read(progressProvider.notifier).setLearnGoal(const LearnGoal(kind: GoalKind.exam));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('free YDS learners see the countdown and the offer', (tester) async {
      await pumpCard(tester);
      expect(find.byKey(const ValueKey('exam-season-offer')), findsOneWidget);
      expect(find.text("YDS'ye 41 gün kaldı"), findsOneWidget);
      expect(find.textContaining('Sınava kadar Premium'), findsOneWidget);
    });

    testWidgets('closing the offer keeps only the countdown for a week', (tester) async {
      final c = await pumpCard(tester);
      await tester.tap(find.byKey(const ValueKey('exam-season-dismiss')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('exam-season-offer')), findsNothing);
      expect(find.byKey(const ValueKey('exam-season-countdown-only')), findsOneWidget);
      expect(c.read(prefsProvider).getInt(ExamSeasonCard.dismissedKey), inWindow.millisecondsSinceEpoch);
    });

    testWidgets('Premium sees just the countdown', (tester) async {
      await pumpCard(tester, premium: true);
      expect(find.byKey(const ValueKey('exam-season-offer')), findsNothing);
      expect(find.text("YDS'ye 41 gün kaldı"), findsOneWidget);
    });

    testWidgets('a recently closed paywall (PaywallPacer) means no offer', (tester) async {
      await pumpCard(
        tester,
        prefs: {'paywall.pace.closed_ms': inWindow.subtract(const Duration(days: 1)).millisecondsSinceEpoch},
      );
      expect(find.byKey(const ValueKey('exam-season-offer')), findsNothing);
      expect(find.byKey(const ValueKey('exam-season-countdown-only')), findsOneWidget);
    });

    testWidgets('nothing in Çocuk modu', (tester) async {
      await pumpCard(tester, prefs: kidSettings);
      expect(find.byKey(const ValueKey('exam-season-countdown')), findsNothing);
    });

    testWidgets('nothing for other goals or outside the window', (tester) async {
      await tester.pumpWidget(host(await overrides(tester), const ExamSeasonCard()));
      final c = containerOf(tester, ExamSeasonCard);
      c.read(progressProvider.notifier).setLearnGoal(const LearnGoal(kind: GoalKind.exam));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('exam-season-countdown')), findsNothing);
    });
  });

  group('daily reading data', () {
    test('Turkish day key: 22:30 UTC is already the next day', () {
      expect(trDayKey(DateTime.utc(2026, 11, 19, 22, 30)), '2026-11-20');
      expect(trDayKey(DateTime.utc(2026, 11, 19, 20, 30)), '2026-11-19');
    });

    test('the cache keeps the last 5 days', () async {
      final cache = DailyReadingCache(await prefsWith({}));
      for (var d = 10; d <= 19; d++) {
        cache.put(reading('2026-11-$d', 'B1'), '2026-11-19');
      }
      final days = [for (final r in cache.history('B1')) r.date];
      expect(days, ['2026-11-19', '2026-11-18', '2026-11-17', '2026-11-16', '2026-11-15']);
      expect(cache.latest('B1', '2026-11-17')!.date, '2026-11-17');
      expect(cache.latest('A1', '2026-11-19'), isNull);
    });

    test('round-trips through JSON', () {
      final r = reading('2026-11-19', 'B1');
      final back = DailyReading.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
      expect(back.toJson(), r.toJson());
      expect(back.valid, isTrue);
      expect(DailyReading.fromJson({'title': 'x'}).valid, isFalse);
    });

    Future<ProviderContainer> make({DailyReadingSource? source, Map<String, Object> prefs = const {}}) async {
      final c = ProviderContainer(
        overrides: await overrides(null, daily: source, prefs: prefs),
      );
      addTearDown(c.dispose);
      return c;
    }

    test("loads today's reading for the learner's band and caches it", () async {
      final src = FakeDailySource({'2026-11-19_A2': reading('2026-11-19', 'A2')});
      final c = await make(source: src);
      expect(c.read(dailyLevelProvider), 'A2'); // general course, no report yet
      final r = await c.read(dailyReadingProvider.future);
      expect(r!.date, '2026-11-19');
      expect(c.read(dailyReadingCacheProvider).latest('A2', '2026-11-19')!.date, '2026-11-19');
      // A second read comes from the phone.
      c.invalidate(dailyReadingProvider);
      await c.read(dailyReadingProvider.future);
      expect(src.calls, ['2026-11-19/A2']);
    });

    test("falls back to yesterday's before today's is written", () async {
      final src = FakeDailySource({'2026-11-18_A2': reading('2026-11-18', 'A2')});
      final c = await make(source: src);
      expect((await c.read(dailyReadingProvider.future))!.date, '2026-11-18');
      expect(src.calls, ['2026-11-19/A2', '2026-11-18/A2']);
    });

    test('offline: the newest copy on the phone', () async {
      final c0 = await make(source: FakeDailySource({'2026-11-17_A2': reading('2026-11-17', 'A2')}));
      // Seed the cache, then go offline (same prefs).
      c0.read(dailyReadingCacheProvider).put(reading('2026-11-17', 'A2'), '2026-11-19');
      final prefs = c0.read(prefsProvider);
      final c = ProviderContainer(
        overrides: [
          ...await overrides(null, daily: FakeDailySource({}, offline: true)),
          prefsProvider.overrideWithValue(prefs),
        ].skip(1).toList(),
      );
      addTearDown(c.dispose);
      expect((await c.read(dailyReadingProvider.future))!.date, '2026-11-17');
    });

    test('the picked band is remembered; the track suggests one', () async {
      final c = await make();
      c.read(dailyLevelProvider.notifier).pick('C1');
      expect(c.read(dailyLevelProvider), 'C1');
      expect(c.read(prefsProvider).getString(DailyLevelNotifier.key), 'C1');
      c.read(dailyLevelProvider.notifier).pick('Z9');
      expect(c.read(dailyLevelProvider), 'C1');
      expect(suggestedDailyLevel(const Progress(trackId: 'yds')), 'B2');
      expect(suggestedDailyLevel(const Progress(trackId: 'lgs')), 'A2');
    });
  });

  group('daily reading screen', () {
    final src = FakeDailySource({'2026-11-19_A2': reading('2026-11-19', 'A2')});

    testWidgets('shows the text, the glossary and the questions; answering all marks it read', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: await overrides(tester, daily: src),
          child: const MaterialApp(home: DailyReadingScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('The Lost Umbrella'), findsOneWidget);
      expect(find.text('Kelimeler'), findsOneWidget);
      expect(find.textContaining('What did she find?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('daily-q0-o1')));
      await tester.tap(find.byKey(const ValueKey('daily-q1-o0')));
      await tester.tap(find.byKey(const ValueKey('daily-q2-o0')));
      await tester.pumpAndSettle();
      expect(find.text('3 sorudan 2 doğru!'), findsOneWidget);
      final c = containerOf(tester, DailyReadingScreen);
      expect(c.read(dailyReadDoneProvider), contains('2026-11-19_A2'));
    });

    testWidgets('"Bunu konuşalım" is hidden until the voice chat registers a launcher', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: await overrides(tester, daily: src, premium: true),
          child: const MaterialApp(home: DailyReadingScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('daily-talk')), findsNothing);
    });

    testWidgets('Premium hands the text to the voice chat', (tester) async {
      TalkTopic? got;
      await tester.pumpWidget(
        ProviderScope(
          overrides: await overrides(tester, daily: src, premium: true, talk: (_, t) async => got = t),
          child: const MaterialApp(home: DailyReadingScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bunu konuşalım'));
      await tester.pumpAndSettle();
      expect(got!.topic, 'The Lost Umbrella');
      expect(got!.context, contains('umbrella'));
      expect(got!.opener, 'Have you ever lost something?');
      expect(got!.level, 'A2');
    });

    testWidgets('free users see a locked button that opens the paywall', (tester) async {
      var called = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: await overrides(tester, daily: src, talk: (_, _) async => called = true),
          child: const MaterialApp(home: DailyReadingScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bunu konuşalım · Premium'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('daily-talk')));
      await tester.pumpAndSettle();
      expect(called, isFalse);
    });

    testWidgets('offline without a copy explains it', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: await overrides(tester, daily: FakeDailySource({}, offline: true)),
          child: const MaterialApp(home: DailyReadingScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('daily-reading-empty')), findsOneWidget);
    });

    testWidgets('the Öğren card hides once today is read', (tester) async {
      await tester.pumpWidget(host(await overrides(tester, daily: src), const DailyReadingCard()));
      await tester.pumpAndSettle();
      expect(find.text('Günün okuması · A2'), findsOneWidget);
      containerOf(
        tester,
        DailyReadingCard,
      ).read(dailyReadDoneProvider.notifier).mark(reading('2026-11-19', 'A2'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('daily-reading-card')), findsNothing);
    });

    test('topics are clipped to the server limit on a word boundary', () {
      expect(TalkTopic.clip('  Short   title '), 'Short title');
      final long = TalkTopic.clip(
        'A very long title about a lost umbrella that travels all around the old city',
      );
      expect(long.length, lessThanOrEqualTo(TalkTopic.maxTopicChars));
      expect(long.endsWith(' '), isFalse);
      expect(long, 'A very long title about a lost umbrella that travels all');
    });
  });

  group('invite', () {
    test('the share message has the code, the rule and the Play link', () {
      final text = inviteShareText(const InviteInfo(code: 'K7M3QXA'));
      expect(text, contains('K7M3QXA'));
      expect(text, contains('ilk dersini bitir'));
      expect(text, contains('7 gün Premium'));
      expect(text, contains('$dilmacPlayStoreUrl&referrer=invite%3DK7M3QXA'));
    });

    testWidgets('the nudge shows at most once every 3 days', (tester) async {
      const nudge = InviteNudge(place: InviteNudgePlace.perfectLesson);
      await tester.pumpWidget(host(await overrides(tester), nudge));
      expect(find.byKey(const ValueKey('invite-nudge-perfectLesson')), findsOneWidget);
      final shown = containerOf(tester, InviteNudge).read(prefsProvider).getInt(InviteNudge.shownKey);
      expect(shown, today.millisecondsSinceEpoch);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host(await overrides(tester, prefs: {InviteNudge.shownKey: shown!}), nudge));
      expect(find.byKey(const ValueKey('invite-nudge-perfectLesson')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        host(
          await overrides(
            tester,
            at: today.add(const Duration(days: 3)),
            prefs: {InviteNudge.shownKey: shown},
          ),
          nudge,
        ),
      );
      expect(find.byKey(const ValueKey('invite-nudge-perfectLesson')), findsOneWidget);
    });

    testWidgets('no referral UI in Çocuk modu', (tester) async {
      await tester.pumpWidget(
        host(
          await overrides(tester, prefs: kidSettings),
          const Column(
            children: [
              InviteNudge(place: InviteNudgePlace.streak),
              GrowthProfileSection(),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('invite-nudge-streak')), findsNothing);
      expect(find.byKey(const ValueKey('profile-invite')), findsNothing);
      expect(containerOf(tester, GrowthProfileSection).read(appSettingsProvider).mode, AppMode.kid);
    });

    testWidgets('the Profile card is there for adults', (tester) async {
      await tester.pumpWidget(host(await overrides(tester), const GrowthProfileSection()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-invite')), findsOneWidget);
      expect(find.text('İkiniz de 1 hafta Premium kazanın'), findsOneWidget);
    });

    testWidgets('the nudge shares the invite with this phone\'s install id', (tester) async {
      final referral = FakeReferral();
      await tester.pumpWidget(
        host(await overrides(tester, referral: referral), const InviteNudge(place: InviteNudgePlace.streak)),
      );
      // The share sheet plugin is not available in tests; the code fetch is what matters.
      await tester.tap(find.byKey(const ValueKey('invite-nudge-share')));
      await tester.pump();
      expect(referral.inviteDevices.single, isNotNull);
    });

    testWidgets('a redeemed code waits for the first lesson', (tester) async {
      final referral = FakeReferral();
      await tester.pumpWidget(
        ProviderScope(
          overrides: await overrides(tester, referral: referral),
          child: const MaterialApp(home: InviteScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('invite-code-field')), 'ABCD234');
      await tester.tap(find.text('Kodu kullan'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('invite-pending')), findsOneWidget);
      expect(find.textContaining('İlk dersini bitirdiğinde'), findsOneWidget);
    });

    testWidgets('an already pending code is shown when the screen opens', (tester) async {
      final referral = FakeReferral()..status = InviteStatus.pending;
      await tester.pumpWidget(
        ProviderScope(
          overrides: await overrides(tester, referral: referral),
          child: const MaterialApp(home: InviteScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('invite-pending')), findsOneWidget);
      expect(find.byKey(const ValueKey('invite-code-field')), findsNothing);
    });
  });
}
