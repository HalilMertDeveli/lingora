// İlk deneyim: welcome → one goal → first lesson; later asks (account,
// reminders, daily goal) wait for a natural moment; the "Bugün" sequence.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/first_lesson.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/goals/learn_goal.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/screens/onboarding_screen.dart';
import 'package:lingora/screens/reminder_settings.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeNotifications, FakeSpeech, pumpApp;

Map<String, dynamic> _saved(SharedPreferences p) =>
    jsonDecode(p.getString('progress_v1') ?? '{}') as Map<String, dynamic>;

Future<void> _toGoalPage(WidgetTester tester) async {
  await pumpApp(tester, {});
  expect(find.text('Dilmaç'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('onboarding-next')));
  await tester.pumpAndSettle();
  expect(find.text('Ne için İngilizce?'), findsOneWidget);
}

Future<void> _quitLesson(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('session-close')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Çık'));
  await tester.pumpAndSettle();
}

void main() {
  group('first run', () {
    testWidgets('welcome → one goal → the first lesson at once', (tester) async {
      await _toGoalPage(tester);
      // Nothing else is asked first: no audience, course, daily goal or level page.
      expect(find.text('Kimin için?'), findsNothing);
      expect(find.text('Günlük hedefin ne olsun?'), findsNothing);
      final start = find.byKey(const ValueKey('onboarding-start'));
      expect(tester.widget<FilledButton>(start).onPressed, isNull, reason: 'a goal must be chosen');

      await tester.tap(find.byKey(const ValueKey('start-goal-general')));
      await tester.pump();
      await tester.tap(start);
      await tester.pumpAndSettle();

      // The first lesson is open; onboarding ends when it closes.
      expect(find.text('“merhaba” hangisi?'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(_saved(prefs)['onboarded'], isNot(true));

      await _quitLesson(tester);
      expect(_saved(prefs)['onboarded'], isTrue);
      expect(_saved(prefs)['learnGoal']?['kind'], 'general');
      expect(prefs.getBool(dailyGoalPendingKey), isTrue);
      // On the path now: no reminder or account card before any lesson.
      expect(find.text('Merhaba!'), findsWidgets);
      expect(find.text('Her gün hatırlatayım mı?'), findsNothing);
    });

    testWidgets('YDS goal: exam goal, beginner start towards YDS', (tester) async {
      await _toGoalPage(tester);
      await tester.tap(find.byKey(const ValueKey('start-goal-exam')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('onboarding-start')));
      await tester.pumpAndSettle();
      await _quitLesson(tester);
      final saved = _saved(await SharedPreferences.getInstance());
      expect(saved['learnGoal']?['kind'], GoalKind.exam.name);
    });

    testWidgets('LGS goal switches to Çocuk modu and the LGS course, with no adult goal', (tester) async {
      await _toGoalPage(tester);
      await tester.tap(find.byKey(const ValueKey('start-goal-lgs')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_v1'), contains('kid'));
      await tester.tap(find.byKey(const ValueKey('onboarding-start')));
      await tester.pumpAndSettle();
      await _quitLesson(tester);
      final saved = _saved(prefs);
      expect(saved['trackId'], 'lgs');
      expect(saved['learnGoal'], isNull);
    });

    testWidgets('choosing back an adult goal leaves Çocuk modu', (tester) async {
      await _toGoalPage(tester);
      await tester.tap(find.byKey(const ValueKey('start-goal-kid')));
      await tester.pumpAndSettle();
      expect(Brand.isKid, isTrue);
      await tester.tap(find.byKey(const ValueKey('start-goal-interview')));
      await tester.pumpAndSettle();
      expect(Brand.isKid, isFalse);
    });

    test('goal choices map to look, reason and goal', () {
      expect(StartGoal.kid.mode, AppMode.kid);
      expect(StartGoal.lgs.mode, AppMode.kid);
      expect(StartGoal.exam.mode, AppMode.adult);
      expect(StartGoal.exam.goalKind, GoalKind.exam);
      expect(StartGoal.interview.goalKind, GoalKind.interview);
      expect(StartGoal.kid.goalKind, isNull);
    });
  });

  group('first lesson', () {
    test('is short and has the Turkish-speaker mistake moment', () {
      final items = firstLessonItems();
      expect(items.length, inInclusiveRange(5, 8));
      expect(items.map((i) => i.key), everyElement(startsWith('$firstLessonId#')));
      final choice = items.firstWhere((i) => i.ex.options.contains('I am agree with you.'));
      expect(choice.ex.options[choice.ex.answerIndex!], 'I agree with you.');
      expect(choice.ex.explanation, contains('"agree" zaten bir fiil'));
      // The learner can build the mistake too, and gets "Neden yanlış?".
      expect(
        items.any((i) => i.ex.tokens.contains('am') && i.ex.answers.contains('I agree with you')),
        isTrue,
      );
    });

    testWidgets('"I am agree" shows why it is wrong, in Turkish', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final item = firstLessonItems().firstWhere((i) => i.ex.options.isNotEmpty);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prefsProvider.overrideWithValue(p),
            speechProvider.overrideWithValue(FakeSpeech()),
            notificationServiceProvider.overrideWithValue(FakeNotifications()),
          ],
          child: MaterialApp(
            theme: buildTheme(),
            home: LessonScreen(
              nodeId: firstLessonId,
              title: firstLessonTitle,
              items: [item],
              color: Colors.indigo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('I am agree with you.'));
      await tester.pump();
      await tester.tap(find.text('Kontrol et'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('choice-explanation')), findsOneWidget);
      expect(find.textContaining('"agree" zaten bir fiil'), findsOneWidget);
      // "Bildir" stays on the explanation.
      expect(find.byKey(const Key('report-question')), findsOneWidget);
    });
  });

  group('later asks', () {
    test('reminders: after a second lesson or on another day, not on the first run', () {
      final now = DateTime(2026, 11, 19, 10);
      expect(
        reminderPromptDue(const Progress(onboarded: true, lessonsDone: 1, xpByDay: {'2026-11-19': 10}), now),
        isFalse,
      );
      expect(reminderPromptDue(const Progress(onboarded: true, lessonsDone: 2), now), isTrue);
      expect(
        reminderPromptDue(const Progress(onboarded: true, lessonsDone: 1, xpByDay: {'2026-11-18': 10}), now),
        isTrue,
      );
      expect(
        reminderPromptDue(const Progress(onboarded: true, lessonsDone: 5, remindersEnabled: false), now),
        isFalse,
      );
    });

    testWidgets('the daily goal is asked on the path after a few lessons', (tester) async {
      await pumpApp(tester, {
        'progress_v1': '{"onboarded": true, "lessonsDone": 3, "remindersEnabled": false}',
        dailyGoalPendingKey: true,
      });
      expect(find.text('Günlük hedefini seç'), findsOneWidget);
      await tester.tap(find.byKey(const Key('daily-goal-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('daily-goal-30')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(_saved(prefs)['dailyGoal'], 30);
      expect(prefs.getBool(dailyGoalPendingKey), isNull);
      expect(find.text('Günlük hedefini seç'), findsNothing);
    });

    testWidgets('before that, the daily goal card just shows the goal', (tester) async {
      await pumpApp(tester, {
        'progress_v1': '{"onboarded": true, "lessonsDone": 1, "remindersEnabled": false}',
        dailyGoalPendingKey: true,
      });
      expect(find.text('Günlük hedefini seç'), findsNothing);
      expect(find.text('Günlük hedef'), findsOneWidget);
    });
  });

  group('Bugün on Öğren', () {
    testWidgets('one card with the sequence and a single BAŞLA; Pratik has no second "Bugün"', (
      tester,
    ) async {
      await pumpApp(tester, {'progress_v1': '{"onboarded": true, "remindersEnabled": false}'});
      expect(find.byKey(const Key('today-start-card')), findsOneWidget);
      expect(find.text('Bugün ne yapacağım?'), findsOneWidget);
      expect(find.byKey(const Key('today-step-lesson')), findsOneWidget);
      expect(find.byKey(const Key('today-progress')), findsOneWidget);
      expect(find.textContaining('BAŞLA'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tab-practice')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('today-card')), findsNothing);
    });

    testWidgets('BAŞLA opens the first step; leaving it pauses the run', (tester) async {
      await pumpApp(tester, {'progress_v1': '{"onboarded": true, "remindersEnabled": false}'});
      await tester.tap(find.textContaining('BAŞLA'));
      await tester.pumpAndSettle();
      // The lesson step (nothing to review yet): the path's next lesson.
      expect(find.text('“merhaba” hangisi?'), findsOneWidget);
      await _quitLesson(tester);
      expect(find.byKey(const Key('today-run-continue')), findsOneWidget);
      expect(find.textContaining('Yarıda kaldı'), findsOneWidget);
    });
  });
}
