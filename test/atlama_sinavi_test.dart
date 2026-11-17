// "Atlama sınavı": unit and section skip exams with three hearts.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/practice.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/resume.dart';
import 'package:lingora/data/sections.dart';
import 'package:lingora/data/skip_exam.dart';
import 'package:lingora/main.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/lesson_result_screen.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/screens/session_resume.dart';
import 'package:lingora/screens/skip_exam_card.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/ui/hearts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeNotifications, FakeSpeech;

/// "kedi" → "cat" questions: the right answer is always "cat".
Map<String, dynamic> _select() => {
  'type': 'select',
  'prompt': 'kedi',
  'answer': 'cat',
  'choices': [
    {'text': 'cat', 'emoji': '🐱'},
    {'text': 'dog', 'emoji': '🐶'},
  ],
};

Unit _unit(String id) => Unit.fromJson({
  'id': id,
  'title': 'Ünite $id',
  'description': '',
  'color': '0xFF1E88E5',
  'nodes': [
    for (var l = 1; l <= 2; l++)
      {
        'id': '${id}l$l',
        'type': 'lesson',
        'title': 'Ders $id-$l',
        'description': '',
        'exercises': [for (var i = 0; i < 4; i++) _select()],
      },
    {'id': '${id}c', 'type': 'chest', 'title': 'Sandık', 'description': ''},
    {'id': '${id}t', 'type': 'test', 'title': 'Ünite sınavı', 'description': ''},
  ],
});

Section _section(int index, List<String> units) => Section.fromJson(
  {
    'id': 's$index',
    'index': index,
    'title': 'Bölüm $index',
    'cefr': ['B1', 'B2', 'C1'][index - 1],
  },
  units: [for (final u in units) _unit(u)],
);

/// Three sections (B1, B2, C1), two units each, eight questions per unit.
final _course = Course(
  id: 'tr_en',
  title: 'İngilizce',
  fromLang: 'tr',
  learningLang: 'en',
  sections: [
    _section(1, ['a', 'b']),
    _section(2, ['c', 'd']),
    _section(3, ['e', 'f']),
  ],
);

Unit _u(String id) => _course.units.firstWhere((u) => u.id == id);

const _fresh = Progress(onboarded: true, remindersEnabled: false);

Future<void> _setUp(WidgetTester tester, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

List<Override> _overrides(SharedPreferences prefs) => [
  courseProvider.overrideWith((ref) async => _course),
  courseOutlineProvider.overrideWith((ref) async => _course),
  prefsProvider.overrideWithValue(prefs),
  speechProvider.overrideWithValue(FakeSpeech()),
  notificationServiceProvider.overrideWithValue(FakeNotifications()),
];

/// [screen] alone, over the mini course.
Future<ProviderContainer> _pumpScreen(WidgetTester tester, Widget screen) async {
  await _setUp(tester, {});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: _overrides(prefs));
  addTearDown(container.dispose);
  await container.read(courseProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildTheme(), home: screen),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _answer(WidgetTester tester, {required bool right}) async {
  await tester.tap(find.text(right ? 'cat' : 'dog').last);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('check')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('feedback-continue')));
  await tester.pumpAndSettle();
}

int _heartsLeft(WidgetTester tester) => tester.widget<HeartsBar>(find.byKey(const Key('skip-hearts'))).left;

void main() {
  _coverageTests();

  group('skip exam data', () {
    test('a unit skip marks the unit and the units before it in its section', () {
      final ids = skipExamNodes(_course, unitSkipId(_u('b')));
      expect(ids, [
        for (final u in ['a', 'b']) ..._u(u).nodes.map((n) => n.id),
      ]);
      expect(skipExamNodes(_course, unitSkipId(_u('c'))), _u('c').nodes.map((n) => n.id));
      expect(skipExamNodes(_course, 'unit_skip_nope'), isEmpty);
      expect(skipExamNodes(_course, 'u1l1'), isEmpty);
      expect(isUnitSkipId(unitSkipId(_u('a'))), isTrue);
      expect(isUnitSkipId(sectionPassKey(_course.sections.first)), isFalse);
    });

    test('a section skip marks every step of the section', () {
      final s2 = _course.sections[1];
      expect(skipExamNodes(_course, sectionPassKey(s2)), s2.nodes.map((n) => n.id));
    });

    test('unit skip questions come from every lesson; offered until the unit is done', () {
      final items = unitSkipItems(_u('a'));
      expect(items.length, greaterThanOrEqualTo(skipMinQuestions));
      expect(items.map((it) => it.key.split('#').first).toSet(), {'al1', 'al2'});
      expect(unitSkipOffered(_u('a'), _fresh), isTrue);
      final done = _fresh.copyWith(completed: {for (final n in _u('a').nodes) n.id: 1});
      expect(unitSkipOffered(_u('a'), done), isFalse);
    });

    test('B1 → C1 in two section exams: each pass opens the next section', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      addTearDown(container.dispose);
      final notifier = container.read(progressProvider.notifier);
      final s = _course.sections;
      expect(sectionOpen(_course, s[1], container.read(progressProvider)), isFalse);

      expect(applySkipPass(notifier, _course, sectionPassKey(s[0])), s[0].nodes.length);
      var p = container.read(progressProvider);
      expect(sectionSkipFinished(s[0], p), isTrue);
      expect(sectionOpen(_course, s[1], p), isTrue);
      expect(sectionOpen(_course, s[2], p), isFalse);
      // No XP or lesson counts for marked steps (the exam itself gives XP).
      expect(p.totalXp, 0);

      applySkipPass(notifier, _course, sectionPassKey(s[1]));
      p = container.read(progressProvider);
      expect(sectionOpen(_course, s[2], p), isTrue);
      expect(currentNode(_course, p)!.id, 'el1');
    });

    test('a unit skip opens the next unit', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      addTearDown(container.dispose);
      applySkipPass(container.read(progressProvider.notifier), _course, unitSkipId(_u('a')));
      expect(activeNodes(_course, container.read(progressProvider))['s1']!.id, 'bl1');
    });

    test('hearts are saved with the session and checked on load', () {
      String record({int? hearts, int? left}) => ResumeRecord(
        trackId: 'tr_en',
        savedAt: DateTime(2026, 11, 16),
        lesson: LessonSnapshot(
          nodeId: unitSkipId(_u('a')),
          title: 'Ünite a',
          color: 1,
          mode: LessonMode.test,
          queue: const ['al1#0', 'al1#1'],
          total: 2,
          pos: 1,
          hearts: hearts,
          heartsLeft: left,
        ),
      ).encode();
      final saved = ResumeRecord.decode(record(hearts: 5, left: 3))!.lesson!;
      expect((saved.hearts, saved.heartsLeft), (5, 3));
      final lesson = ResumeRecord.decode(record())!.lesson!;
      expect((lesson.hearts, lesson.heartsLeft), (null, null));
      expect(ResumeRecord.decode(record(hearts: 5, left: 6)), isNull);
      expect(ResumeRecord.decode(record(hearts: 5)), isNull);
      expect(ResumeRecord.decode(record(hearts: 0, left: 0)), isNull);
    });
  });

  group('skip exam screen', () {
    testWidgets('every wrong answer takes a heart; none left ends the exam kindly', (tester) async {
      final container = await _pumpScreen(tester, unitSkipScreen(_u('a'))!);
      expect(find.text('ÜNİTEYİ ATLA'), findsOneWidget);
      expect(_heartsLeft(tester), 3);
      for (var lost = 1; lost <= 2; lost++) {
        await _answer(tester, right: false);
        expect(_heartsLeft(tester), 3 - lost);
      }
      await _answer(tester, right: false);
      expect(find.byType(SkipFailedScreen), findsOneWidget);
      expect(find.text('Canların bitti, hiç sorun değil'), findsOneWidget);
      expect(find.textContaining('3 sorunun 0 tanesini'), findsOneWidget);
      // The path is as it was.
      final p = container.read(progressProvider);
      expect(_u('a').nodes.where((n) => p.isDone(n.id)), isEmpty);
      expect(container.read(resumeStoreProvider).hasRecord, isFalse);

      await tester.tap(find.byKey(const Key('skip-retry')));
      await tester.pumpAndSettle();
      expect(_heartsLeft(tester), 3);
    });

    testWidgets('a wrong question comes back; passing needs every question right', (tester) async {
      final container = await _pumpScreen(tester, unitSkipScreen(_u('a'))!);
      final total = unitSkipItems(_u('a')).length;
      // Two mistakes (one heart left): both questions are asked again.
      await _answer(tester, right: false);
      await _answer(tester, right: false);
      var answers = 2;
      while (find.text('Üniteyi atladın!').evaluate().isEmpty) {
        expect(find.byType(SkipFailedScreen), findsNothing);
        await _answer(tester, right: true);
        answers++;
        expect(answers, lessThanOrEqualTo(total + 2), reason: 'two re-asked questions at most');
      }
      expect(answers, total + 2);
      final p = container.read(progressProvider);
      expect(_u('a').nodes.every((n) => p.isDone(n.id)), isTrue);
      expect(activeNodes(_course, p)['s1']!.id, 'bl1');
      expect(p.totalXp, greaterThanOrEqualTo(unitSkipXp));
    });

    testWidgets('normal lessons have no hearts', (tester) async {
      await _pumpScreen(tester, LessonScreen.forNode(_u('a').nodes.first, Brand.primary));
      expect(find.byType(HeartsBar), findsNothing);
      await _answer(tester, right: false);
      expect(find.byType(HeartsBar), findsNothing);
    });

    testWidgets('the hearts left are saved and come back after the app is killed', (tester) async {
      final container = await _pumpScreen(tester, unitSkipScreen(_u('a'))!);
      await _answer(tester, right: false);
      await _answer(tester, right: false);
      final record = container.read(resumeStoreProvider).load()!;
      expect(record.lesson!.hearts, skipHearts);
      expect(record.lesson!.heartsLeft, 1);
      // The two wrong questions wait at the end of the saved queue.
      expect(record.lesson!.queue, hasLength(record.lesson!.total + 2));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: buildTheme(), home: restoredScreen(record, _course)),
        ),
      );
      await tester.pumpAndSettle();
      expect(_heartsLeft(tester), 1);
      expect(find.text('ÜNİTEYİ ATLA'), findsOneWidget);
    });

    testWidgets('killed right after the last heart went: the friendly end opens', (tester) async {
      final record = ResumeRecord(
        trackId: 'tr_en',
        savedAt: DateTime.now(),
        lesson: LessonSnapshot(
          nodeId: unitSkipId(_u('a')),
          title: 'Ünite a',
          color: 0xFF1E88E5,
          mode: LessonMode.test,
          queue: [for (var i = 0; i < 4; i++) 'al1#$i', for (var i = 0; i < 4; i++) 'al2#$i'],
          total: 8,
          pos: 5,
          answered: 5,
          mistakes: 5,
          solved: 5,
          badge: 'ÜNİTEYİ ATLA',
          hearts: 5,
          heartsLeft: 0,
        ),
      );
      await _pumpScreen(tester, restoredScreen(record, _course)!);
      expect(find.byType(SkipFailedScreen), findsOneWidget);
    });
  });

  testWidgets('a lost heart pops off with a short animation', (tester) async {
    Widget bar(int left) => MaterialApp(
      home: Center(child: HeartsBar(left: left, total: 5)),
    );
    await tester.pumpWidget(bar(5));
    expect(find.byIcon(Icons.favorite_rounded), findsNWidgets(5));
    await tester.pumpWidget(bar(4));
    await tester.pump(const Duration(milliseconds: 200));
    // Four hearts plus the one floating away.
    expect(find.byIcon(Icons.favorite_rounded), findsNWidgets(5));
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_rounded), findsNWidgets(4));
    expect(find.bySemanticsLabel('5 candan 4 kaldı'), findsOneWidget);
  });

  group('on the path', () {
    Future<void> pumpApp(WidgetTester tester, Progress p) async {
      await _setUp(tester, {'progress_v1': jsonEncode(p.toJson())});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(overrides: _overrides(prefs), child: const LingoraApp()));
      await tester.pumpAndSettle();
    }

    testWidgets('each unfinished unit offers "Bu üniteyi atla" with its rules', (tester) async {
      await pumpApp(tester, _fresh);
      final card = find.byKey(const Key('unit-skip-a'));
      expect(card, findsOneWidget);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unit-skip-sheet')), findsOneWidget);
      expect(find.textContaining('her yanlış cevap bir can götürür'), findsOneWidget);
      await tester.tap(find.byKey(const Key('unit-skip-start')));
      await tester.pumpAndSettle();
      expect(find.text('ÜNİTEYİ ATLA'), findsOneWidget);
      expect(_heartsLeft(tester), skipHearts);
    });

    testWidgets('an open section can be skipped too, from its quick button', (tester) async {
      await pumpApp(tester, _fresh);
      await tester.tap(find.byKey(const Key('section-skip-quick-s1')));
      await tester.pumpAndSettle();
      expect(find.text('Bu bölümü atla'), findsOneWidget);
      await tester.tap(find.byKey(const Key('section-skip')));
      await tester.pumpAndSettle();
      expect(find.text('BÖLÜME ATLA'), findsOneWidget);
      expect(_heartsLeft(tester), skipHearts);
    });

    testWidgets('a finished unit offers no skip', (tester) async {
      await pumpApp(tester, _fresh.copyWith(completed: {for (final n in _u('a').nodes) n.id: 1}));
      expect(find.byKey(const Key('unit-skip-a')), findsNothing);
      expect(find.byKey(const Key('unit-skip-b')), findsOneWidget);
    });
  });
}

/// Graded questions of [lessons] (what a skip exam can ask).
int _gradedCount(List<PathNode> lessons) =>
    lessons.expand(lessonItems).where((it) => !ungradedTypes.contains(it.ex.type)).length;

void _coverageTests() {
  group('coverage on the shipped course', () {
    late Course general;
    setUpAll(() async => general = await loadCourse(rootBundle, 'tr_en'));

    test('key words come from lesson descriptions and are found in the questions', () {
      final u1 = general.units.firstWhere((u) => u.id == 'u1');
      final ids = skipObjectives(skipLessons(u1)).map((o) => o.id).toSet();
      expect(
        ids,
        containsAll(['lesson:u1l1', 'word:u1l1:hello', 'word:u1l1:good morning', 'word:u1l1:thank you']),
      );
      // Whole words only.
      expect(lessonKeywords(u1.nodes.first), ['hello', 'good morning', 'thank you']);
    });

    test('every unit skip exam asks every learning goal, and more than a lesson', () {
      var units = 0;
      var words = 0;
      for (final unit in general.units) {
        final lessons = skipLessons(unit);
        if (lessons.isEmpty) continue;
        units++;
        final goals = skipObjectives(lessons);
        words += goals.where((g) => g.id.startsWith('word:')).length;
        final graded = _gradedCount(lessons);
        final biggestLesson = lessons.map((l) => l.exercises.length).reduce(max);
        for (var seed = 0; seed < 3; seed++) {
          final items = unitSkipItems(unit, Random(seed));
          for (final g in goals) {
            expect(items.any(g.coveredBy), isTrue, reason: '${unit.id}: ${g.id} not asked (seed $seed)');
          }
          expect(items.map((i) => i.key).toSet(), hasLength(items.length), reason: 'no question twice');
          expect(items.length, greaterThanOrEqualTo(min(graded, unitSkipTarget)), reason: unit.id);
          if (graded > biggestLesson) {
            expect(items.length, greaterThan(biggestLesson), reason: '${unit.id}: more than a lesson');
          }
        }
      }
      expect(units, greaterThan(50));
      expect(words, greaterThan(units), reason: 'key words are real goals');
    });

    test('a section skip exam covers every unit, at least five questions each', () {
      for (final section in general.sections.where((s) => !s.parallel)) {
        final items = sectionSkipQuestions(section, Random(1));
        expect(items.map((i) => i.key).toSet(), hasLength(items.length));
        for (final unit in section.units) {
          final lessons = skipLessons(unit);
          if (lessons.isEmpty) continue;
          final mine = items.where((it) => lessons.any((l) => it.key.startsWith('${l.id}#'))).toList();
          expect(
            mine.length,
            greaterThanOrEqualTo(min(sectionSkipPerUnit, _gradedCount(lessons))),
            reason: unit.id,
          );
          for (final g in skipObjectives(lessons)) {
            expect(mine.any(g.coveredBy), isTrue, reason: '${section.id}/${unit.id}: ${g.id}');
          }
        }
      }
    });
  });
}
