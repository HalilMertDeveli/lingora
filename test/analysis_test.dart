// Error notebook and analysis (docs/sinav/yds-faz1-yontem.md §4–§5, F2
// infrastructure): "Neden yanıldın?" and its suggestions, type / unit / time
// statistics, the mock report, the score estimate, the reading library from
// several files and the Okuma evi list.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/practice.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/reading_repository.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/models/vocab.dart';
import 'package:lingora/screens/study/mock_report_screen.dart';
import 'package:lingora/screens/study/notebook_screen.dart';
import 'package:lingora/screens/study/reading_house.dart';
import 'package:lingora/services/firebase/progress_merge.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/study/analysis.dart';
import 'package:lingora/study/mistake_reasons.dart';
import 'package:lingora/study/question_types.dart';
import 'package:lingora/study/review_queue.dart';
import 'package:lingora/study/study_state.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sections_test.dart' show FakeBundle;
import 'study_test.dart' show readCourse;
import 'widget_test.dart' show FakeNotifications, FakeSpeech;

final yds = readCourse('exam_yds');
final now = DateTime(2026, 11, 12, 9);
final today = dayKey(now);

AnswerLog a(
  QType t,
  bool ok, {
  int sec = 40,
  String unit = 'ys3u1',
  String src = 'lesson',
  bool blank = false,
}) => AnswerLog(
  key: 'k',
  day: today,
  correct: ok,
  seconds: sec,
  type: t.name,
  unitId: unit,
  source: src,
  blank: blank,
);

Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  Widget child, {
  Progress progress = const Progress(onboarded: true, remindersEnabled: false),
  List<AnswerLog> log = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    'progress_v1': jsonEncode(progress.toJson()),
    'study_log_v1': jsonEncode(StudyLog(answers: log).toJson()),
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
      clockProvider.overrideWithValue(() => now),
      courseProvider.overrideWith((ref) async => yds),
      ydsVocabProvider.overrideWith((ref) async => null),
    ],
  );
  addTearDown(c.dispose);
  await c.read(courseProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildTheme(), home: child),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

Future<ProviderContainer> container(Progress p) async {
  SharedPreferences.setMockInitialValues({'progress_v1': jsonEncode(p.toJson())});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [prefsProvider.overrideWithValue(prefs), clockProvider.overrideWithValue(() => now)],
  );
  addTearDown(c.dispose);
  return c;
}

/// The first choice question of a YDS vocabulary unit, as a notebook key.
String vocabMistakeKey() {
  final unit = yds.units.firstWhere((u) => u.id == 'ys2u1');
  final lesson = unit.nodes.firstWhere((n) => n.type == NodeType.lesson);
  return itemKey(lesson.id, lesson.exercises.indexWhere((e) => e.type == ExerciseType.choice));
}

void main() {
  group('statistics', () {
    test('per type: accuracy, blanks, time against the target', () {
      final s = typeStats([
        a(QType.cloze, true, sec: 60),
        a(QType.cloze, false, sec: 100),
        a(QType.cloze, false, sec: 80, blank: true),
        a(QType.reading, true, sec: 150),
        const AnswerLog(key: 'x', day: '2026-11-12', correct: true, seconds: 5, type: 'match'),
      ]);
      expect(s.keys, {QType.cloze, QType.reading});
      final cloze = s[QType.cloze]!;
      expect((cloze.answered, cloze.correct, cloze.wrong, cloze.blank), (3, 1, 1, 1));
      expect(cloze.avgSeconds, 80);
      expect(cloze.slow, isTrue);
      expect(s[QType.reading]!.slow, isFalse);
    });

    test('weak types and units', () {
      final log = [
        for (var i = 0; i < 6; i++) a(QType.grammar, i < 5, unit: 'ys1u1'),
        for (var i = 0; i < 6; i++) a(QType.translation, i < 2, unit: 'ys3u3'),
        for (var i = 0; i < 3; i++) a(QType.dialogue, false, unit: 'ys3u7'),
      ];
      expect(weakTypes(typeStats(log)).map((t) => t.type), [QType.translation, QType.grammar]);
      expect(weakUnits(log).first, ('ys3u3', 4, 6));
    });
  });

  group('score estimate', () {
    test('needs 20 answers', () {
      expect(estimateScore([for (var i = 0; i < 19; i++) a(QType.grammar, true)]), isNull);
    });

    test('from type accuracy, weighted by the exam mix', () {
      final log = [
        for (final t in QType.values.where((t) => t.inExam > 0))
          for (var i = 0; i < 10; i++) a(t, t == QType.reading ? i < 5 : true),
      ];
      final s = estimateScore(log)!;
      // 60 sure + 20 reading at 50 % = 70 right = 87.5 points.
      expect(s.fromMocks, isFalse);
      expect((s.low + s.high) / 2, closeTo(87.5, 1));
      expect(s.high - s.low, lessThanOrEqualTo(16));
    });

    test('from the last three mocks, the newest counting most', () {
      List<AnswerLog> mock(String src, int right) => [
        for (var i = 0; i < 80; i++) a(QType.grammar, i < right, src: src),
      ];
      final log = [
        ...mock('mock:yds_m1@1', 20),
        ...mock('mock:yds_m2@2', 48),
        ...mock('mock:yds_m3@3', 56),
        ...mock('mock:yds_m4@4', 64),
      ];
      final s = estimateScore(log)!;
      expect((s.fromMocks, s.halfMocksOnly), (true, false));
      expect(s.basis, 240);
      // Weighted 1:2:3 → (60 + 140 + 240) / 6 = 73.3 %.
      expect((s.low + s.high) / 2, closeTo(73, 1.5));
    });

    List<AnswerLog> attempt(String src, int size, int right) => [
      for (var i = 0; i < size; i++) a(QType.grammar, i < right, src: src),
    ];

    test('a retake of a mock does not count; only its first attempt does', () {
      final log = [...attempt('mock:yds_m1@1', 80, 40), ...attempt('mock:yds_m1@2', 80, 78)];
      final s = estimateScore(log)!;
      expect(s.basis, 80);
      expect((s.low + s.high) / 2, closeTo(50, 1));
      expect(mockIdOf('mock:yds_m1@1731000000'), 'yds_m1');
    });

    test('section mocks never count; half mocks only without a full one, with a wider range', () {
      final section = attempt('mock:ys3u10m@1', 40, 39);
      final half = attempt('mock:ys6u6m@2', 40, 24);
      // A section mock alone: practice accuracy, not mocks.
      expect(estimateScore(section, halfMocks: {'ys6u6m'})!.fromMocks, isFalse);
      final h = estimateScore([...section, ...half], halfMocks: {'ys6u6m'})!;
      expect((h.fromMocks, h.halfMocksOnly, h.basis), (true, true, 40));
      expect(h.high - h.low, greaterThanOrEqualTo(16));
      expect((h.low + h.high) / 2, closeTo(60, 1));
      // With a full mock the half one is left out.
      final f = estimateScore([...half, ...attempt('mock:yds_m9@3', 80, 48)], halfMocks: {'ys6u6m'})!;
      expect((f.halfMocksOnly, f.basis), (false, 80));
    });
  });

  group('mock report', () {
    test('gap to the 72-right plan scales with the mock size', () {
      final r = MockReport([
        for (var i = 0; i < 20; i++) a(QType.reading, i < 12, sec: 200),
        for (var i = 0; i < 10; i++) a(QType.grammar, i < 9, sec: 30),
      ]);
      final reading = r.rows.firstWhere((row) => row.stat.type == QType.reading);
      expect((reading.target, reading.gap), (17.0, 5));
      expect(r.focus.map((f) => f.stat.type), [QType.reading]);
      expect((r.correct, r.total), (21, 30));
    });

    test('two-minute rule leaves reading out', () {
      expect(overTwoMinutes([a(QType.grammar, true, sec: 130), a(QType.reading, true, sec: 400)]), 1);
    });
  });

  group('notebook data', () {
    test('reasons, notes, postponing and their merge', () async {
      final c = await container(const Progress(mistakes: ['q#1']));
      c.read(progressProvider.notifier)
        ..tagMistake('q#1', reason: MistakeReason.twoOptions.name, note: 'x' * 200)
        ..postponeMistake('q#1', 3);
      final p = c.read(progressProvider);
      expect(p.mistakeReason['q#1'], 'twoOptions');
      expect(p.mistakeNote['q#1'], hasLength(140));
      expect(p.mistakeDue['q#1'], dayKey(now.add(const Duration(days: 3))));
      final merged = mergeProgress(p, const Progress(), localNewer: true);
      expect(merged.mistakeReason, p.mistakeReason);
      expect(merged.mistakeNote.keys, ['q#1']);
      c.read(progressProvider.notifier).clearMistake('q#1');
      expect(c.read(progressProvider).mistakeReason, isEmpty);
    });

    test('"Kelimeyi bilmiyordum" finds the question\'s word cards and queues them for today', () async {
      final key = vocabMistakeKey();
      final ex = mistakeItems(yds, [key]).single.ex;
      final cards = wordsInQuestion(ex, yds);
      expect(cards, isNotEmpty);
      final c = await container(const Progress());
      expect(c.read(progressProvider.notifier).queueWords(cards.map((w) => w.id)), cards.length);
      expect(c.read(progressProvider).wordDue[cards.first.id], today);
      expect(c.read(progressProvider.notifier).queueWords(cards.map((w) => w.id)), 0);
    });

    test('a full card with a bridge card\'s id replaces it and keeps its progress key', () {
      final lesson = yds.allNodes.firstWhere((n) => n.vocab);
      final unit = yds.units.firstWhere((u) => u.nodes.contains(lesson));
      final (_, en) = lesson.exercises.firstWhere((e) => e.type == ExerciseType.match).pairs.first;
      final bridgeId = wordCardId(ydsWordPrefix, en);
      final full = VocabEntry.fromJson({
        'id': bridgeId,
        'word': en,
        'pos': 'noun',
        'topic': unit.id,
        'senses': [
          {'tr': 'tam anlam', 'def': 'meaning'},
        ],
        'examples': [
          {'en': 'Example.', 'tr': 'Örnek.', 'context': 'genel', 'target': en},
        ],
      });
      final cards = courseWordCards(yds, Progress(completed: {lesson.id: 1}), ydsCards: [full]);
      final card = cards.singleWhere((c) => c.id == bridgeId);
      expect((card.tr, card.example), ('tam anlam', 'Example.'));
    });
  });

  group('reading', () {
    test('stories.json plus yds_bol_okuma_* and genel_okuma_* files, in order, without repeats', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      String story(String id, String level) => jsonEncode([
        {
          'id': id,
          'level': level,
          'title': 'T $id',
          'titleTr': 'T',
          'text': 'One two three.',
          'glosses': <String, String>{},
          'questions': <Object>[],
        },
      ]);
      final bundle = FakeBundle({
        'assets/reading/stories.json': story('s1', 'A1'),
        'assets/reading/yds_bol_okuma_02.json': story('yb_2', 'B2'),
        'assets/reading/yds_bol_okuma_01.json': story('yb_1', 'B1+'),
        'assets/reading/yds_bol_okuma_03.json': 'bozuk',
        'assets/reading/yds_bol_okuma_04.json': story('s1', 'B2'),
        'assets/reading/genel_okuma_b.json': story('go_b', 'B2'),
        'assets/reading/genel_okuma_a.json': story('go_a', 'A2'),
        'assets/reading/notlar.json': story('x', 'A1'),
      });
      final stories = await loadStories(bundle);
      // File-name order: genel_okuma_* sorts before yds_bol_okuma_*; other files are not reading shelves.
      expect(stories.map((s) => (s.id, s.level)), [
        ('s1', 'A1'),
        ('go_a', 'A2'),
        ('go_b', 'B2'),
        ('yb_1', 'B1+'),
        ('yb_2', 'B2'),
      ]);
      expect(stories.map(readingSource), [null, 'Genel', 'Genel', 'YDS', 'YDS']);
    });

    test('Okuma evi lists nodes with a reading field', () {
      final node = PathNode.fromJson({
        'id': 'ys6u1l1',
        'type': 'lesson',
        'title': 'Metin 1',
        'reading': {'field': 'fen', 'words': 210, 'cefr': 'A2+'},
      });
      final c = Course(
        id: 'exam_yds',
        title: 'Y',
        fromLang: 'tr',
        learningLang: 'en',
        units: [
          Unit(id: 'ys6u1', title: 'U', description: '', color: Colors.blue, nodes: [node]),
        ],
      );
      expect(readingHouseTexts(c).single.$2.id, 'ys6u1l1');
      // The shipped Okuma evi sections (ys6, ys8 from Faz 2b, ys10 from Faz 3b): text lessons with field and length.
      final shipped = readingHouseTexts(yds);
      expect(shipped.where((e) => e.$1.id.startsWith('ys6')), hasLength(18));
      expect(shipped.length, greaterThanOrEqualTo(18));
      expect(
        shipped.every((e) => e.$2.reading!.words > 0 && RegExp(r'^ys(6|8|10)u').hasMatch(e.$1.id)),
        isTrue,
      );
    });
  });

  group('screens', () {
    testWidgets('notebook: pick a reason, see the advice; "iki şık" brings it back in 3 days', (
      tester,
    ) async {
      final key = vocabMistakeKey();
      final c = await pumpApp(
        tester,
        const NotebookScreen(),
        progress: Progress(
          onboarded: true,
          remindersEnabled: false,
          mistakes: [key],
          mistakeDue: {key: today},
        ),
        log: [for (var i = 0; i < 25; i++) a(QType.vocabulary, i.isEven, unit: 'ys2u1')],
      );
      expect(find.byKey(const Key('score-estimate')), findsOneWidget);
      expect(find.byKey(const Key('target-vocabulary')), findsOneWidget);
      expect(find.text('NEDEN YANILDIN? (1)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reason-twoOptions')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reason-advice')), findsOneWidget);
      final p = c.read(progressProvider);
      expect(p.mistakeReason[key], 'twoOptions');
      expect(p.mistakeDue[key], dayKey(now.add(const Duration(days: 3))));
      expect(find.text('ETİKETLENENLER (1)'), findsOneWidget);
    });

    testWidgets('mock report: per type, time against targets, the gap and the 2-minute rule', (tester) async {
      const src = 'mock:yds_m1@1';
      await pumpApp(
        tester,
        const MockReportScreen(source: src),
        log: [
          for (var i = 0; i < 20; i++) a(QType.reading, i < 10, sec: 200, src: src),
          for (var i = 0; i < 10; i++) a(QType.grammar, true, sec: 130, src: src),
          a(QType.grammar, false, src: 'lesson'),
        ],
      );
      expect(find.text('20 / 30 doğru · 0 boş'), findsOneWidget);
      expect(find.byKey(const Key('report-reading')), findsOneWidget);
      expect(find.byKey(const Key('report-grammar')), findsOneWidget);
      expect(find.byKey(const Key('report-slow')), findsOneWidget);
      expect(find.byKey(const Key('report-blank')), findsNothing);
      expect(find.textContaining('Okuma: 7 doğru eksik'), findsOneWidget);
    });
  });
}
