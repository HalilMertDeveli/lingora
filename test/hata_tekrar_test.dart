// Hata tekrarı: a wrong answer comes back later in the lesson; the same
// question missed [mistakeSaveMisses] times is saved to the notebook, and at
// most once a day a lesson ends with "Bunlar senin hataların".
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/mistake_nudge.dart';
import 'package:lingora/data/practice.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/screens/mistake_nudge_screen.dart';
import 'package:lingora/services/firebase/progress_merge.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeNotifications, FakeSpeech;

final _now = DateTime(2026, 11, 17, 9);
const _today = '2026-11-17';

/// "kedi" → "cat" questions: the right answer is always "cat".
Map<String, dynamic> _select(String prompt) => {
  'type': 'select',
  'prompt': prompt,
  'answer': 'cat',
  'choices': [
    {'text': 'cat', 'emoji': '🐱'},
    {'text': 'dog', 'emoji': '🐶'},
  ],
};

final _unit = Unit.fromJson({
  'id': 'a',
  'title': 'Ünite a',
  'description': '',
  'color': '0xFF1E88E5',
  'nodes': [
    for (var l = 1; l <= 2; l++)
      {
        'id': 'al$l',
        'type': 'lesson',
        'title': 'Ders $l',
        'description': '',
        'exercises': [for (var i = 0; i < 3; i++) _select('kedi $l-$i')],
      },
  ],
});

final _course = Course(
  id: 'tr_en',
  title: 'İngilizce',
  fromLang: 'tr',
  learningLang: 'en',
  sections: [
    Section.fromJson({'id': 's1', 'index': 1, 'title': 'Bölüm 1', 'cefr': 'A1'}, units: [_unit]),
  ],
);

PathNode _node(String id) => _unit.nodes.firstWhere((n) => n.id == id);

Future<(ProviderContainer, SharedPreferences)> _pump(
  WidgetTester tester,
  Progress progress, {
  String? nudgeDay,
}) async {
  SharedPreferences.setMockInitialValues({
    'progress_v1': jsonEncode(progress.toJson()),
    mistakeNudgeDayKey: ?nudgeDay,
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final container = ProviderContainer(
    overrides: [
      courseProvider.overrideWith((ref) async => _course),
      courseOutlineProvider.overrideWith((ref) async => _course),
      prefsProvider.overrideWithValue(prefs),
      speechProvider.overrideWithValue(FakeSpeech()),
      notificationServiceProvider.overrideWithValue(FakeNotifications()),
      clockProvider.overrideWithValue(() => _now),
    ],
  );
  addTearDown(container.dispose);
  await container.read(courseProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('open'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => LessonScreen.forNode(_node('al1'), Brand.primary)),
                ),
                child: const Text('Aç'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return (container, prefs);
}

Future<void> _answer(WidgetTester tester, {required bool right}) async {
  await tester.tap(find.text(right ? 'cat' : 'dog').last);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('check')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('feedback-continue')));
  await tester.pumpAndSettle();
}

/// Taps "Devam" through the end screens until [key] shows or none is left.
Future<bool> _continueUntil(WidgetTester tester, Key key) async {
  for (var i = 0; i < 6; i++) {
    if (find.byKey(key).evaluate().isNotEmpty) return true;
    final next = find.text('Devam');
    if (next.evaluate().isEmpty) return false;
    await tester.tap(next.first);
    await tester.pumpAndSettle();
  }
  return find.byKey(key).evaluate().isNotEmpty;
}

void main() {
  group('saving to the notebook', () {
    late ProviderContainer c;
    ProgressNotifier n() => c.read(progressProvider.notifier);
    Progress p() => c.read(progressProvider);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      c = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs), clockProvider.overrideWithValue(() => _now)],
      );
    });
    tearDown(() => c.dispose());

    test('one or two misses only count; the third saves the question', () {
      expect(mistakeSaveMisses, 3);
      expect(n().recordWrong('al1#0'), isFalse);
      expect(n().recordWrong('al1#0'), isFalse);
      expect(p().mistakes, isEmpty);
      expect(p().mistakeMisses, {'al1#0': 2});
      expect(n().recordWrong('al1#0'), isTrue);
      expect(p().mistakes, ['al1#0']);
      expect(p().mistakeMisses, isEmpty);
      // The usual 1 → 3 → 7 → 21 days: first back tomorrow.
      expect(p().mistakeDue['al1#0'], '2026-11-18');
      expect(p().mistakeStage['al1#0'], 0);
    });

    test('a notebook question missed again starts its run again at once', () {
      for (var i = 0; i < mistakeSaveMisses; i++) {
        n().recordWrong('al1#1');
      }
      n().answerMistakeRight('al1#1');
      expect((p().mistakeRun['al1#1'], p().mistakeStage['al1#1']), (1, 1));
      expect(n().recordWrong('al1#1'), isTrue);
      expect((p().mistakeRun['al1#1'], p().mistakeStage['al1#1']), (0, 1));
      expect(p().mistakeMisses, isEmpty);
    });

    test('counts survive a restart and stay capped', () {
      n().recordWrong('al1#2');
      expect(Progress.fromJson(p().toJson()).mistakeMisses, {'al1#2': 1});
      for (var i = 0; i < maxMissCounts + 3; i++) {
        n().recordWrong('x#$i');
      }
      expect(p().mistakeMisses, hasLength(maxMissCounts));
      expect(p().mistakeMisses.containsKey('al1#2'), isFalse); // oldest dropped
      expect(p().mistakeMisses.containsKey('x#${maxMissCounts + 2}'), isTrue);
    });

    test('devices merge the larger count, dropping saved questions', () {
      const local = Progress(mistakeMisses: {'a#1': 2, 'a#2': 1});
      const remote = Progress(mistakeMisses: {'a#1': 1, 'a#3': 2}, mistakes: ['a#2']);
      final merged = mergeProgress(local, remote, localNewer: false);
      expect(merged.mistakeMisses, {'a#1': 2, 'a#3': 2});
    });
  });

  test('the reminder shows when something is due, once a day', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(mistakeNudgeDue(prefs, today: _today, due: 0), isFalse);
    expect(mistakeNudgeDue(prefs, today: _today, due: 2), isTrue);
    markMistakeNudge(prefs, _today);
    expect(mistakeNudgeDue(prefs, today: _today, due: 2), isFalse);
    expect(mistakeNudgeDue(prefs, today: '2026-11-18', due: 2), isTrue);
  });

  group('in a lesson', () {
    testWidgets('a wrong question comes back; the third miss saves it', (tester) async {
      final (c, _) = await _pump(tester, const Progress(onboarded: true, remindersEnabled: false));
      await _answer(tester, right: false); // 1st miss of al1#0, asked again at the end
      expect(c.read(progressProvider).mistakes, isEmpty);
      await _answer(tester, right: true);
      await _answer(tester, right: true);
      expect(find.text('“kedi 1-0” hangisi?'), findsOneWidget); // back again
      await _answer(tester, right: false);
      expect(c.read(progressProvider).mistakes, isEmpty);
      expect(c.read(progressProvider).mistakeMisses, {'al1#0': 2});
      await _answer(tester, right: false);
      expect(c.read(progressProvider).mistakes, ['al1#0']);
      // The lesson still ends only once it is answered right.
      expect(find.text('“kedi 1-0” hangisi?'), findsOneWidget);
      await _answer(tester, right: true);
      expect(find.byKey(const Key('lesson-result')), findsOneWidget);
    });

    testWidgets('a lesson ends with "Bunlar senin hataların" and opens the review', (tester) async {
      const progress = Progress(
        onboarded: true,
        remindersEnabled: false,
        mistakes: ['al2#1', 'al2#0'],
        mistakeDue: {'al2#1': '2026-11-17', 'al2#0': '2026-11-20'},
      );
      final (c, prefs) = await _pump(tester, progress);
      for (var i = 0; i < 3; i++) {
        await _answer(tester, right: true);
      }
      expect(await _continueUntil(tester, const Key('mistake-nudge')), isTrue);
      expect(find.text('Bunlar senin hataların'), findsOneWidget);
      expect(find.text('kedi 2-1'), findsOneWidget); // due today
      expect(find.text('kedi 2-0'), findsNothing); // not yet
      expect(prefs.getString(mistakeNudgeDayKey), _today);
      await tester.tap(find.byKey(const Key('mistake-nudge-solve')));
      await tester.pumpAndSettle();
      expect(find.text('“kedi 2-1” hangisi?'), findsOneWidget);
      await _answer(tester, right: true);
      // A right answer moves it to its next interval (3 days).
      expect(c.read(progressProvider).mistakeDue['al2#1'], '2026-11-20');
      expect(find.byKey(const Key('lesson-result')), findsOneWidget);
    });

    testWidgets('no reminder when it already showed today', (tester) async {
      const progress = Progress(
        onboarded: true,
        remindersEnabled: false,
        mistakes: ['al2#1'],
        mistakeDue: {'al2#1': '2026-11-17'},
      );
      await _pump(tester, progress, nudgeDay: _today);
      for (var i = 0; i < 3; i++) {
        await _answer(tester, right: true);
      }
      expect(await _continueUntil(tester, const Key('mistake-nudge')), isFalse);
    });
  });

  testWidgets('the card names at most three questions and "Sonra" moves on', (tester) async {
    var later = 0;
    final items = [...lessonItems(_node('al1')), ...lessonItems(_node('al2'))];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: MistakeNudgeScreen(items: items, onSolve: () {}, onLater: () => later++),
      ),
    );
    expect(find.textContaining('6 soru'), findsOneWidget);
    expect(find.byIcon(Icons.replay_rounded), findsNWidgets(mistakeNudgePreview));
    await tester.tap(find.byKey(const Key('mistake-nudge-later')));
    expect(later, 1);
  });
}
