// Audit item 8: a mock exam's clock runs to a fixed end time.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/option_glosses.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/exam.dart';
import 'package:lingora/screens/exam_screen.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/study/mock_attempt.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeNotifications, FakeSpeech;

const _qs = [
  ExamQuestion(id: 'q1', text: 'One ----.', options: ['a', 'b', 'c', 'd', 'e'], answer: 0, explanation: ''),
  ExamQuestion(id: 'q2', text: 'Two ----.', options: ['a', 'b', 'c', 'd', 'e'], answer: 1, explanation: ''),
];
const _exam = Exam(
  id: 'yds',
  title: 'YDS',
  description: '',
  optionCount: 5,
  mockSize: 2,
  mockMinutes: 10,
  sections: [],
);

void main() {
  late DateTime now;
  late SharedPreferences prefs;

  Future<ProviderContainer> pump(WidgetTester tester, {bool fresh = true}) async {
    if (fresh) {
      SharedPreferences.setMockInitialValues({
        'progress_v1': jsonEncode(const Progress(onboarded: true, remindersEnabled: false).toJson()),
      });
      prefs = await SharedPreferences.getInstance();
    }
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        speechProvider.overrideWithValue(FakeSpeech()),
        notificationServiceProvider.overrideWithValue(FakeNotifications()),
        clockProvider.overrideWithValue(() => now),
        optionGlossesProvider.overrideWith((ref) async => const OptionGlosses({})),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildTheme(),
          home: const ExamSessionScreen(exam: _exam, questions: _qs, mock: true, title: 'Deneme', nodeId: 'm1'),
        ),
      ),
    );
    await tester.pump();
    return c;
  }

  setUp(() => now = DateTime(2026, 11, 19, 10));

  test('seconds left are counted from the end time', () {
    final end = DateTime(2026, 1, 1, 10, 10);
    expect(secondsLeft(end, DateTime(2026, 1, 1, 10)), 600);
    expect(secondsLeft(end, DateTime(2026, 1, 1, 10, 9, 59, 500)), 1);
    expect(secondsLeft(end, DateTime(2026, 1, 1, 11)), 0);
  });

  testWidgets('time away from the app (suspended) is not extra time', (tester) async {
    await pump(tester);
    expect(find.text('10:00'), findsOneWidget);
    // The phone slept for 4 minutes: no timer ticks ran meanwhile.
    now = now.add(const Duration(minutes: 4));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('06:00'), findsOneWidget);
    // Back past the end time: the mock is scored.
    now = now.add(const Duration(minutes: 7));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(ExamResultScreen), findsOneWidget);
  });

  testWidgets('reopened after the app was killed: same end time and answers', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('exam-option-0')));
    await tester.pump();
    // The process dies (the widget tree goes); 3 minutes later it is reopened.
    await tester.pumpWidget(const SizedBox());
    now = now.add(const Duration(minutes: 3));
    await pump(tester, fresh: false);
    expect(find.text('07:00'), findsOneWidget);
    expect(MockAttempts(prefs).load('m1', ['q1', 'q2'])!.answers, {0: 0});
  });

  testWidgets('reopened after the end time: scored with the saved answers', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('exam-option-0')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    now = now.add(const Duration(minutes: 30));
    final c = await pump(tester, fresh: false);
    await tester.pumpAndSettle();
    expect(find.byType(ExamResultScreen), findsOneWidget);
    expect(c.read(progressProvider).examBest['m1'], 50);
    expect(MockAttempts(prefs).load('m1', ['q1', 'q2']), isNull, reason: 'a finished attempt is cleared');
  });
}
