// Exam study paths (_cikti/sinav_yolu_plan.md): the `choice` exercise, the
// unit guide and its "Önce konuyu oku" suggestion, section mocks, progress
// kept per exam track and the fallback when a path is not shipped.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/catalog.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/exam_path.dart';
import 'package:lingora/data/practice.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/sections.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/models/exam.dart';
import 'package:lingora/screens/exam_screen.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/screens/path_screen.dart';
import 'package:lingora/screens/topic_guide.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/ui/markdown_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sections_test.dart' show FakeBundle;
import 'widget_test.dart' show FakeNotifications, FakeSpeech;

Course _readCourse(String id) {
  final top = Course.fromJson(
    jsonDecode(File('assets/courses/$id.json').readAsStringSync()) as Map<String, dynamic>,
  );
  final dir = Directory('assets/courses/$id');
  final files = dir.existsSync()
      ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];
  return top.withSections([
    for (final f in files) Section.fromFile(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>),
  ]);
}

final _lgs = _readCourse('exam_lgs');
final _general = Course.fromJson(
  jsonDecode(File('assets/courses/tr_en.json').readAsStringSync()) as Map<String, dynamic>,
);
final _bank = Exam.fromJson(
  jsonDecode(File('assets/exams/lgs.json').readAsStringSync()) as Map<String, dynamic>,
);

const _choice = Exercise(
  type: ExerciseType.choice,
  passage: 'Ece: Would you like to come to my party on Saturday?\nMert: ----. I have a swimming course.',
  question: 'Which option completes the dialogue?',
  options: ['Sure, I would love to', "Sorry, I can't make it", 'Yes, see you there', 'Of course, great idea'],
  answerIndex: 1,
  explanation: 'Mert yüzme kursu olduğu için daveti reddediyor.',
);

Future<(SharedPreferences, ProviderContainer)> _pump(
  WidgetTester tester,
  Widget child, {
  Progress progress = const Progress(onboarded: true, remindersEnabled: false),
  AppMode mode = AppMode.adult,
  List overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({'progress_v1': jsonEncode(progress.toJson())});
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      speechProvider.overrideWithValue(FakeSpeech()),
      notificationServiceProvider.overrideWithValue(FakeNotifications()),
      clockProvider.overrideWithValue(() => DateTime(2026, 11, 11, 9)),
      ...overrides.cast(),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(mode: mode),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (prefs, container);
}

LessonScreen _lesson(List<Exercise> exercises) => LessonScreen(
  nodeId: 'ls1u1l1',
  title: 'Test',
  items: [for (final (i, ex) in exercises.indexed) (key: 'ls1u1l1#$i', ex: ex)],
  color: Brand.primary,
);

void main() {
  group('choice exercise', () {
    test('reads from JSON with the answer as an index', () {
      final ex = Exercise.fromJson({
        'type': 'choice',
        'passage': 'Text',
        'question': 'Q?',
        'options': ['a', 'b', 'c', 'd'],
        'answer': 2,
        'explanation': 'Çünkü c.',
      });
      expect((ex.type, ex.passage, ex.answerIndex, ex.answer), (ExerciseType.choice, 'Text', 2, null));
      expect(ex.displayAnswer, 'c');
      expect(ex.explanation, 'Çünkü c.');
    });

    testWidgets(
      'a wrong pick shows the right option and the Turkish explanation, and is saved as a mistake',
      (tester) async {
        final (_, c) = await _pump(tester, _lesson([_choice]));
        expect(find.byKey(const Key('choice-passage')), findsOneWidget);
        expect(find.byKey(const Key('choice-option-3')), findsOneWidget);
        await tester.tap(find.byKey(const Key('choice-option-0')));
        await tester.pump();
        await tester.tap(find.text('Kontrol et'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('feedback-wrong')), findsOneWidget);
        expect(find.text("B) Sorry, I can't make it"), findsOneWidget);
        expect(find.byKey(const Key('choice-explanation')), findsOneWidget);
        expect(find.text(_choice.explanation!), findsOneWidget);
        expect(c.read(progressProvider).mistakes, ['ls1u1l1#0']);
      },
    );

    testWidgets('a right pick also explains why', (tester) async {
      await _pump(tester, _lesson([_choice]));
      await tester.tap(find.byKey(const Key('choice-option-1')));
      await tester.pump();
      await tester.tap(find.text('Kontrol et'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('feedback-correct')), findsOneWidget);
      expect(find.text(_choice.explanation!), findsOneWidget);
    });

    testWidgets('a long passage scrolls in its own box, also in Çocuk modu', (tester) async {
      final long = Exercise(
        type: ExerciseType.choice,
        passage: List.filled(40, 'Lisa visits her grandmother in Bursa every summer.').join(' '),
        question: 'Where does Lisa go?',
        options: const ['Bursa', 'Izmir', 'Ankara', 'Rize'],
        answerIndex: 0,
        explanation: 'Metinde Bursa yazıyor.',
      );
      await _pump(tester, _lesson([long]), mode: AppMode.kid);
      final box = tester.getSize(find.byKey(const Key('choice-passage')));
      expect(box.height, lessThanOrEqualTo(900 * 0.34 + 1));
      // The options are still on screen without scrolling the page.
      expect(tester.getRect(find.byKey(const Key('choice-option-3'))).bottom, lessThan(900));
      expect(tester.takeException(), isNull);
    });

    testWidgets('mistakes come back in "Hatalarını çalış" from the exam path', (tester) async {
      final key = '${_lgs.units.first.nodes.first.id}#0';
      final items = mistakeItems(_lgs, [key]);
      expect(items.single.key, key);
    });
  });

  group('topic guide', () {
    test('markdown subset: headings, bullets, tips and bold', () {
      final blocks = parseMarkdown(
        '## Başlık\nBir paragraf\ndevam.\n\n- **like** + -ing\n> İpucu\n> ikinci satır',
      );
      expect(blocks.map((b) => b.kind), [MdKind.h2, MdKind.paragraph, MdKind.bullet, MdKind.tip]);
      // A paragraph keeps its line breaks (dialogues in reading texts).
      expect(blocks[1].text, 'Bir paragraf\ndevam.');
      expect(blocks[3].text, 'İpucu ikinci satır');
    });

    test('markdown tables, numbered items and one tip per "Sınav ipucu"', () {
      final blocks = parseMarkdown(
        '| Kalıp | Örnek |\n|---|---|\n| **Would you like to …?** | Would you like to come? |\n'
        '1. *bir*\n'
        '> **Sınav ipucu 1:** a\n> **Sınav ipucu 2:** b',
      );
      expect(blocks.map((b) => b.kind), [MdKind.table, MdKind.numbered, MdKind.tip, MdKind.tip]);
      expect(blocks.first.rows, [
        ['Kalıp', 'Örnek'],
        ['**Would you like to …?**', 'Would you like to come?'],
      ]);
      expect(blocks[1].number, 1);
    });

    testWidgets('a reading text with a table is drawn as a table', (tester) async {
      const survey = Exercise(
        type: ExerciseType.choice,
        passage: 'Survey: free time (20 students)\n| Activity | Students |\n|---|---|\n| reading | 8 |\n| sports | 12 |',
        question: 'Which activity is the most popular?',
        options: ['reading', 'sports', 'music', 'chess'],
        answerIndex: 1,
        explanation: 'Sports 12 öğrenciyle en çok seçilen etkinlik.',
      );
      await _pump(tester, _lesson([survey]));
      expect(find.byKey(const Key('md-table')), findsOneWidget);
      expect(find.text('sports'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    test('every LGS unit has a guide with a summary table, patterns, words and 3 exam tips', () {
      for (final u in _lgs.units) {
        expect(u.hasGuide, isTrue, reason: u.id);
        final blocks = parseMarkdown(u.guide!);
        expect(blocks.where((b) => b.kind == MdKind.table), hasLength(1), reason: u.id);
        expect(blocks.where((b) => b.kind == MdKind.tip && b.text.startsWith('**Sınav ipucu')), hasLength(3));
        for (final h in ['Özet tablo', 'Hedef kalıplar', 'Anahtar kelimeler', 'Sınav ipuçları']) {
          expect(u.guide, contains(h), reason: '${u.id} $h');
        }
      }
    });

    Future<ProviderContainer> pumpPath(
      WidgetTester tester, {
      Progress? progress,
      AppMode mode = AppMode.adult,
    }) async {
      final (_, c) = await _pump(
        tester,
        const Scaffold(body: PathScreen()),
        progress: progress ?? const Progress(onboarded: true, remindersEnabled: false, trackId: 'lgs'),
        mode: mode,
        overrides: [examPathProvider.overrideWith((ref, id) async => id == 'lgs' ? _lgs : null)],
      );
      return c;
    }

    Future<void> startFirst(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('tea-invite-ls1u1l1')));
      await tester.pumpAndSettle();
    }

    testWidgets('before the first lesson "Önce konuyu oku" is suggested once and can be skipped', (
      tester,
    ) async {
      final c = await pumpPath(tester);
      await startFirst(tester);
      expect(find.byKey(const Key('guide-suggestion')), findsOneWidget);
      await tester.tap(find.byKey(const Key('guide-suggestion-skip')));
      await tester.pumpAndSettle();
      expect(find.byType(LessonScreen), findsOneWidget);
      expect(c.read(progressProvider).guideSeen('ls1u1'), isTrue);

      // Leave the lesson and start again: no second suggestion.
      Navigator.of(tester.element(find.byType(LessonScreen))).pop();
      await tester.pumpAndSettle();
      await startFirst(tester);
      expect(find.byKey(const Key('guide-suggestion')), findsNothing);
      expect(find.byType(LessonScreen), findsOneWidget);
    });

    testWidgets('"Konuyu oku" opens the topic explanation, then the lesson', (tester) async {
      await pumpPath(tester, mode: AppMode.kid);
      await startFirst(tester);
      await tester.tap(find.byKey(const Key('guide-suggestion-read')));
      await tester.pumpAndSettle();
      expect(find.byType(TopicGuideScreen), findsOneWidget);
      expect(find.byKey(const Key('md-h2')), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('topic-guide-start')));
      await tester.pumpAndSettle();
      expect(find.byType(LessonScreen), findsOneWidget);
    });

    testWidgets('the unit "Rehber" button shows the topic explanation', (tester) async {
      final c = await pumpPath(tester);
      await tester.tap(find.byKey(const Key('unit-guide-ls1u1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unit-guide-text')), findsOneWidget);
      expect(c.read(progressProvider).guideSeen('ls1u1'), isTrue);
    });
  });

  group('section mock', () {
    final s1 = _lgs.sections.first;
    final mock = s1.nodes.firstWhere((n) => n.type == NodeType.mock);

    test('each section ends with a real-format mock: 2 mini-test questions from every unit', () {
      expect(_lgs.sections.map((s) => s.nodes.last.type), [NodeType.mock, NodeType.mock]);
      expect((mock.examId, mock.size, mock.minutes), ('lgs', 10, 15));
      final qs = mockQuestions(s1, mock, bank: _bank, random: Random(3));
      expect(qs, hasLength(10));
      final perUnit = <String, int>{};
      for (final q in qs) {
        perUnit.update(q.id.substring(0, 5), (n) => n + 1, ifAbsent: () => 1);
      }
      expect(perUnit, {for (final u in s1.units) u.id: 2});
      // Taken from the units' mini LGS tests ("ls1u3t#4").
      expect(qs.every((q) => q.id.contains('t#')), isTrue);
      expect(qs.every((q) => q.options.length == 4 && q.explanation.isNotEmpty), isTrue);
      // The section exam (which opens section 2) is still the last unit test.
      expect(s1.exam?.type, NodeType.test);
    });

    test('a mock covers the units up to its own and never holds the path up', () {
      final unit3 = s1.units[2];
      const mid = PathNode(id: 'mid', type: NodeType.mock, title: 'm', description: '', size: 10);
      final section = Section(
        id: s1.id,
        index: 1,
        title: 'x',
        units: [
          for (final u in s1.units)
            u == unit3
                ? Unit(id: u.id, title: u.title, description: '', color: u.color, nodes: [...u.nodes, mid])
                : u,
        ],
      );
      expect(mockUnits(section, mid).map((u) => u.id), [for (final u in s1.units.take(3)) u.id]);
      final course = Course(id: 'c', title: 'c', fromLang: 'tr', learningLang: 'en', sections: [section]);
      // Unit 3 finished: the mock is open, and so is unit 4 without it.
      final done = Progress(
        completed: {
          for (final u in section.units.take(3))
            for (final n in u.nodes)
              if (n != mid) n.id: 1,
        },
      );
      expect(mockOpen(course, mid, done), isTrue);
      expect(activeNodes(course, done)[s1.id]?.id, section.units[3].nodes.first.id);
      expect(mockOpen(course, mid, const Progress()), isFalse);
    });

    test('a pack mock names its pack and mock (YDS Bölüm 4)', () {
      final n = PathNode.fromJson({
        'id': 'ys4u2m',
        'type': 'mock',
        'title': 'Tam deneme 1',
        'examId': 'yds',
        'packId': 'yds_full',
        'mockId': 'yds_m1',
      });
      expect((n.type, n.packId, n.mockId), (NodeType.mock, 'yds_full', 'yds_m1'));
    });

    test('a unit test with its own questions uses them, in order', () {
      final unit = _lgs.units.first;
      final test = unit.nodes.firstWhere((n) => n.type == NodeType.test);
      expect(test.exercises, hasLength(10));
      expect(testItems(unit, test).map((i) => i.key), [for (var i = 0; i < 10; i++) '${test.id}#$i']);
      const bare = PathNode(id: 'x', type: NodeType.test, title: 't', description: '');
      expect(testItems(unit, bare, Random(1)), hasLength(testSize));
    });

    test('a section too small for its mock is topped up from the question bank', () {
      final tiny = Section(id: 'x', index: 1, title: 'x', units: [s1.units.first]);
      const big = PathNode(id: 'xm', type: NodeType.mock, title: 'm', description: '', size: 60);
      final qs = mockQuestions(tiny, big, bank: _bank, random: Random(1));
      expect(qs, hasLength(60));
      expect(qs.where((q) => q.id.startsWith('lgs_')), isNotEmpty);
      expect(mockExam(big, _bank, qs).mockMinutes, defaultMockMinutes);
    });

    testWidgets('finishing the mock completes the node and keeps its score and time', (tester) async {
      final qs = mockQuestions(s1, mock, bank: _bank, random: Random(2));
      final (_, c) = await _pump(
        tester,
        ExamSessionScreen(
          exam: mockExam(mock, _bank, qs),
          questions: qs,
          mock: true,
          title: mock.title,
          nodeId: mock.id,
        ),
      );
      expect(find.text('15:00'), findsOneWidget);
      // One right answer, the rest left blank. A long reading text can push
      // the options below the fold.
      final right = find.byKey(Key('exam-option-${qs[0].answer}'));
      await tester.scrollUntilVisible(right, 300, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(right);
      await tester.pump();
      for (var i = 0; i + 1 < qs.length; i++) {
        await tester.tap(find.text(i == 0 ? 'Sonraki' : 'Boş bırak'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Denemeyi bitir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bitir'));
      await tester.pumpAndSettle();
      expect(find.byType(ExamResultScreen), findsOneWidget);
      // LGS net: 1 right, no wrong (blanks cost nothing).
      expect(find.textContaining('İngilizce neti: 1 / 10'), findsOneWidget);
      final p = c.read(progressProvider);
      expect(p.isDone(mock.id), isTrue);
      expect(p.examBest[mock.id], 10);
      // The question bank's own best score is untouched.
      expect(p.examBest['lgs'], isNull);
      expect(p.examSeconds[mock.id], isNotNull);
      expect(mockSummary(mock.id, p.examBest, p.examSeconds), startsWith('En iyi sonuç %'));
    });
  });

  group('per-track progress', () {
    testWidgets('the LGS track opens its own path; its progress leaves the general course alone', (
      tester,
    ) async {
      final (_, c) = await _pump(
        tester,
        const SizedBox(),
        progress: const Progress(onboarded: true, remindersEnabled: false, trackId: 'lgs'),
      );
      final course = await tester.runAsync(() => c.read(courseProvider.future));
      expect(course!.id, examPathId('lgs'));
      expect(course.units, hasLength(10));

      c.read(progressProvider.notifier).completeNode('ls1u1l1', xp: 10, answered: 10, correct: 10);
      final p = c.read(progressProvider);
      expect(currentNode(_general, p)?.id, _general.allNodes.first.id);
      expect(currentNode(course, p)?.id, 'ls1u1l2');

      // Back to the general course and to LGS again: both kept.
      c.read(progressProvider.notifier).setTrack('tr_en');
      final general = await tester.runAsync(() => c.read(courseProvider.future));
      expect(general!.id, 'tr_en');
      c.read(progressProvider.notifier).setTrack('lgs');
      expect(currentNode(course, c.read(progressProvider))?.id, 'ls1u1l2');
    });
  });

  // Independent of whether exam_yds.json is shipped: a bundle without it
  // stands in for "not shipped yet".
  group('an exam track without a path', () {
    test('a missing exam path is not an error: loading it gives null', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(await loadExamPath(FakeBundle({}), 'yds'), isNull);
      expect(
        await loadExamPath(FakeBundle({}, extraManifest: ['assets/courses/exam_yds.json']), 'yds'),
        isNull,
      );
      expect(await loadExamPath(rootBundle, 'lgs'), isNotNull);
    });

    testWidgets('falls back to the general course for practice; a shipped path is used instead', (
      tester,
    ) async {
      Future<String?> courseId(Course? path) async {
        final (_, c) = await _pump(
          tester,
          const SizedBox(),
          progress: const Progress(onboarded: true, remindersEnabled: false, trackId: 'yds'),
          overrides: [examPathProvider.overrideWith((ref, id) async => path)],
        );
        return (await tester.runAsync(() => c.read(courseProvider.future)))?.id;
      }

      expect(await courseId(null), 'tr_en');
      expect(await courseId(_lgs), 'exam_lgs');
      expect(trackById('yds').kind, TrackKind.exam);
    });
  });
}
