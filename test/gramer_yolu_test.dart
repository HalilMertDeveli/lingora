import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/grammar_lesson.dart';
import 'package:lingora/models/notes.dart';
import 'package:lingora/screens/grammar_path_screen.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _real = (jsonDecode(File('assets/notes/lessons.json').readAsStringSync()) as List)
    .map((l) => GrammarLesson.fromJson(l as Map<String, dynamic>))
    .toList();

GrammarLesson _lesson(String id, String level, {String? unit}) => GrammarLesson.fromJson({
  'id': id,
  'unit': unit ?? '$level · Bölüm',
  'level': level,
  'title': 'Konu $id',
  'summary': 'Özet $id',
  'compare': 'Karşılaştırma',
});

/// Out of order on purpose: a late A1 lesson and an unknown-free mix.
final _lessons = [
  _lesson('a1', 'A1'),
  _lesson('a2', 'A1'),
  _lesson('b1', 'A2'),
  _lesson('c1', 'B1'),
  _lesson('t1', 'B1', unit: 'Çeviri Atölyesi'),
  _lesson('a3', 'A1'),
];

const _noNotes = NotesBundle(words: [], topics: [], diaryPrompts: []);

Progress _done(Iterable<String> ids) => Progress(completed: {for (final id in ids) 'gl_$id': 1});

void main() {
  group('order', () {
    test('lessons are ordered by level, file order inside a level', () {
      expect(orderedLessons(_lessons).map((l) => l.id), ['a1', 'a2', 'a3', 'b1', 'c1', 't1']);
    });

    test('real lessons: every level groups together, A1 to C1', () {
      final groups = grammarLevelGroups(orderedLessons(_real));
      expect(groups.map((g) => g.level), grammarLevels);
      expect(groups.fold(0, (n, g) => n + g.lessons.length), _real.length);
      for (final g in groups) {
        expect(g.lessons.every((l) => l.level == g.level), isTrue);
        expect(g.title, startsWith(g.level));
      }
      // The A1 lesson at the end of the file belongs to the A1 section.
      expect(groups.first.lessons.map((l) => l.id), contains(_real.last.id));
    });

    test('next step and the step after a finished lesson', () {
      final ordered = orderedLessons(_lessons);
      expect(nextGrammarLesson(ordered, _done([]))!.id, 'a1');
      expect(nextGrammarLesson(ordered, _done(['a1', 'a2']))!.id, 'a3');
      expect(nextGrammarLesson(ordered, _done(ordered.map((l) => l.id))), isNull);
      // After a3 comes b1; a skipped earlier step is suggested only at the end.
      final p = _done(['a1', 'a3']);
      expect(lessonAfter(ordered, ordered[2], p)!.id, 'b1');
      expect(lessonAfter(ordered, ordered.last, _done(['a1', 'a3', 'b1', 'c1', 't1']))!.id, 'a2');
    });

    test('level progress counts finished lessons', () {
      final groups = grammarLevelGroups(orderedLessons(_lessons));
      final p = _done(['a1', 'a3', 'c1']);
      expect(
        {for (final g in groups) g.level: '${g.doneCount(p)}/${g.lessons.length}'},
        {'A1': '2/3', 'A2': '0/1', 'B1': '1/2'},
      );
    });
  });

  group('path screen', () {
    Future<ProviderContainer> pump(WidgetTester tester, {List<String> done = const []}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          grammarLessonsProvider.overrideWith((ref) async => _lessons),
        ],
      );
      addTearDown(c.dispose);
      c.read(progressProvider.notifier).markKnown([for (final id in done) 'gl_$id']);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildTheme(mode: AppMode.adult),
            home: const GrammarPathScreen(notes: _noNotes),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    String progress(WidgetTester tester, String level) =>
        tester.widget<Text>(find.byKey(ValueKey('grammar-level-progress-$level'))).data!;

    testWidgets('one section per level with its progress, in order', (tester) async {
      await pump(tester, done: ['a1', 'a3']);
      final tops = [
        for (final level in ['A1', 'A2', 'B1'])
          tester.getTopLeft(find.byKey(ValueKey('grammar-level-$level'))).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(progress(tester, 'A1'), '2/3');
      expect(progress(tester, 'A2'), '0/1');
      expect(progress(tester, 'B1'), '0/2');
      expect(find.text('2 / 6 ders'), findsOneWidget);
      // The other unit of a level is labelled on the lane.
      expect(find.text('Çeviri Atölyesi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the next step is highlighted and offered to continue', (tester) async {
      await pump(tester, done: ['a1', 'a3']);
      // a2 is step 2: the first unfinished one in order.
      expect(find.text('SIRADAKİ'), findsOneWidget);
      final card = find.byKey(const ValueKey('grammar-continue'));
      expect(find.descendant(of: card, matching: find.text('SIRADAKİ KONU · ADIM 2')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Konu a2')), findsOneWidget);
      final tag = tester.getCenter(find.text('SIRADAKİ'));
      final node = tester.getCenter(find.byKey(const ValueKey('grammar-step-a2')));
      expect((tag.dx - node.dx).abs(), lessThan(1));
      expect(tag.dy, lessThan(node.dy));
      // Done steps show a check, open ones their number.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('grammar-step-a1')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const ValueKey('grammar-step-c1')), matching: find.text('5')),
        findsOneWidget,
      );
    });

    testWidgets('later steps stay open', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('grammar-step-t1')));
      await tester.pumpAndSettle();
      expect(find.byType(GrammarLessonScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('finishing a step suggests the next one', (tester) async {
      final c = await pump(tester, done: ['a2']);
      await tester.tap(find.byKey(const ValueKey('grammar-step-a1')));
      await tester.pumpAndSettle();
      // The lesson is finished and closed.
      c.read(progressProvider.notifier).markKnown(['gl_a1']);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('grammar-just-done'))).data, 'Konu a1 tamam!');
      // a2 is already done: the suggestion is step 3.
      final card = find.byKey(const ValueKey('grammar-continue'));
      expect(find.descendant(of: card, matching: find.text('SIRADAKİ KONU · ADIM 3')), findsOneWidget);
      expect(progress(tester, 'A1'), '2/3');
    });

    testWidgets('all done: no next step', (tester) async {
      await pump(tester, done: _lessons.map((l) => l.id).toList());
      expect(find.text('SIRADAKİ'), findsNothing);
      expect(find.byKey(const ValueKey('grammar-continue')), findsNothing);
      expect(progress(tester, 'A1'), '3/3');
    });
  });
}
