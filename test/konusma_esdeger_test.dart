// The free learning loop always closes, and speaking never blocks a lesson:
// - after the day's free "Neden yanlış?" uses a wrong answer still gets one
//   basic Turkish line; the Premium card sits under the explanation and no
//   paywall opens by itself;
// - without a microphone a speaking item can be typed ("Yazarak cevapla") or
//   skipped ("Şu an konuşamıyorum"), with the same XP, perfect bonus and
//   streak as answering it.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/option_glosses.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/screens/paywall_screen.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/billing/premium_perks.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'premium_test.dart' show FakeBilling;
import 'widget_test.dart' show FakeNotifications, FakeSpeech;

const _choice = Exercise(
  type: ExerciseType.choice,
  question: 'She ---- to school every day.',
  options: ['go', 'goes', 'going', 'gone'],
  answerIndex: 1,
  explanation: 'Geniş zamanda he/she/it ile fiil -s alır. Bu yüzden goes.',
);

const _speak = Exercise(type: ExerciseType.speak, text: 'Good morning, teacher.');

const _gloss = {
  'l1#0': {
    'tr': ['gitmek', 'gider', 'gitmekte', 'gitmiş'],
    'why': [
      'Olmaz: she ile yalın fiil kullanılmaz.',
      'Doğru: geniş zaman, üçüncü tekil şahıs → goes.',
      'Olmaz: be olmadan -ing tek başına fiil olmaz.',
      'Olmaz: gone yardımcı fiil ister.',
    ],
  },
};

Future<ProviderContainer> _pump(WidgetTester tester, List<Exercise> exercises) async {
  SharedPreferences.setMockInitialValues({
    'progress_v1': jsonEncode(const Progress(onboarded: true, remindersEnabled: false).toJson()),
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      speechProvider.overrideWithValue(FakeSpeech()), // no microphone
      notificationServiceProvider.overrideWithValue(FakeNotifications()),
      clockProvider.overrideWithValue(() => DateTime(2026, 11, 19, 9)),
      billingServiceProvider.overrideWithValue(FakeBilling()),
      optionGlossesProvider.overrideWith((ref) async => const OptionGlosses(_gloss)),
    ],
  );
  addTearDown(c.dispose);
  await c.read(optionGlossesProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildTheme(),
        home: LessonScreen(
          nodeId: 'l1',
          title: 'Test',
          items: [for (final (i, ex) in exercises.indexed) (key: 'l1#$i', ex: ex)],
          color: Brand.primary,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

Future<void> _check(WidgetTester tester) async {
  await tester.tap(find.textContaining(RegExp(r'^kontrol et$', caseSensitive: false)));
  await tester.pumpAndSettle();
}

Future<void> _continue(WidgetTester tester) async {
  await tester.tap(find.textContaining(RegExp(r'^devam$', caseSensitive: false)));
  await tester.pumpAndSettle();
}

void main() {
  test('basicWhyLine: the right option\'s line, else the explanation\'s first sentence', () {
    final g = OptionGloss.parse(_gloss['l1#0'], 4);
    expect(basicWhyLine(g, 1), 'Doğru: geniş zaman, üçüncü tekil şahıs → goes.');
    expect(basicWhyLine(null, 1, explanation: 'Kural bu. Ayrıntı şu.'), 'Kural bu.');
    expect(basicWhyLine(null, 1), isNull);
  });

  testWidgets('free, after the day\'s explanations: a basic reason, a small card after it, no paywall', (
    tester,
  ) async {
    final c = await _pump(tester, [_choice]);
    final quota = c.read(whyWrongQuotaProvider.notifier);
    for (var i = 0; i < freeWhyWrongPerDay; i++) {
      expect(quota.claim('other$i'), isTrue);
    }
    await tester.tap(find.byKey(const Key('choice-option-0')));
    await tester.pump();
    await _check(tester);
    expect(find.byKey(const Key('choice-explanation')), findsOneWidget);
    expect(find.byKey(const Key('why-wrong-basic')), findsOneWidget);
    expect(find.text('Doğru: geniş zaman, üçüncü tekil şahıs → goes.'), findsOneWidget);
    // The card comes after the explanation, and the options' Turkish stays Premium.
    expect(
      tester.getTopLeft(find.byKey(const Key('why-wrong-locked'))).dy,
      greaterThan(tester.getTopLeft(find.byKey(const Key('choice-explanation'))).dy),
    );
    expect(find.text('gider'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsNothing, reason: 'never interrupts answering or reading');
  });

  group('speaking without a microphone', () {
    Future<Progress> finish(WidgetTester tester, Future<void> Function() speakStep) async {
      final c = await _pump(tester, [_choice, _speak]);
      await tester.tap(find.byKey(const Key('choice-option-1')));
      await tester.pump();
      await _check(tester);
      await _continue(tester);
      expect(find.text('Bu cümleyi sesli oku'), findsOneWidget);
      await speakStep();
      return c.read(progressProvider);
    }

    testWidgets('"Yazarak cevapla" and "Şu an konuşamıyorum" give the same XP, perfect bonus and streak', (
      tester,
    ) async {
      final typed = await finish(tester, () async {
        await tester.tap(find.byKey(const Key('speak-type')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('speak-type-field')), 'good morning teacher');
        await tester.pump();
        await _check(tester);
        expect(find.byKey(const Key('feedback-correct')), findsOneWidget);
        await _continue(tester);
      });
      await tester.pumpWidget(const SizedBox());

      final skipped = await finish(tester, () async {
        await tester.tap(find.text('Şu an konuşamıyorum'));
        await tester.pumpAndSettle();
      });

      for (final p in [typed, skipped]) {
        expect(p.lessonsDone, 1);
        expect(p.mistakes, isEmpty);
        expect(p.streak, 1);
        expect(p.completed['l1'], 1);
      }
      expect(skipped.totalXp, typed.totalXp, reason: 'no penalty for skipping');
      expect(typed.totalXp, greaterThan(0));
    });

    testWidgets('a wrongly typed sentence is an ordinary miss, and the skip still remains', (tester) async {
      await _pump(tester, [_speak]);
      await tester.tap(find.byKey(const Key('speak-type')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('speak-type-field')), 'see you later');
      await tester.pump();
      expect(find.text('Şu an konuşamıyorum'), findsOneWidget);
      await _check(tester);
      expect(find.byKey(const Key('feedback-wrong')), findsOneWidget);
    });
  });
}
