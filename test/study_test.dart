// Study methods, phase 1 (docs/sinav/yds-faz1-yontem.md §1–2): longer Leitner
// boxes, the error notebook's 1-3-7-21 days, YDS word cards, side paths
// (parallel sections), fixed mock questions, section order and the answer
// log with question types.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/exam_path.dart';
import 'package:lingora/data/practice.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/sections.dart';
import 'package:lingora/data/vocab_practice.dart' show knownBox;
import 'package:lingora/models/course.dart';
import 'package:lingora/models/exam_pack.dart';
import 'package:lingora/models/vocab.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/screens/study/srs_review_screen.dart';
import 'package:lingora/services/firebase/progress_merge.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/study/question_types.dart';
import 'package:lingora/study/review_queue.dart';
import 'package:lingora/study/study_state.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeNotifications, FakeSpeech;

Course readCourse(String id) {
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

final yds = readCourse('exam_yds');
final now = DateTime(2026, 11, 12, 9);
final today = dayKey(now);
String inDays(int d) => dayKey(now.add(Duration(days: d)));

Future<ProviderContainer> container(Progress progress) async {
  SharedPreferences.setMockInitialValues({'progress_v1': jsonEncode(progress.toJson())});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [prefsProvider.overrideWithValue(prefs), clockProvider.overrideWithValue(() => now)],
  );
  addTearDown(c.dispose);
  return c;
}

Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  Widget child, {
  Progress progress = const Progress(onboarded: true, remindersEnabled: false),
  Course? course,
}) async {
  SharedPreferences.setMockInitialValues({'progress_v1': jsonEncode(progress.toJson())});
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 900));
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
      courseProvider.overrideWith((ref) async => course ?? yds),
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

/// The first [n] vocabulary lessons of the YDS path, done.
Progress vocabDone(int n) {
  final ids = yds.allNodes.where((n) => n.vocab).take(n).map((n) => n.id);
  return Progress(onboarded: true, remindersEnabled: false, completed: {for (final id in ids) id: 1});
}

Section section(String id, int index, {bool parallel = false, List<String> nodes = const ['l', 't']}) =>
    Section.fromJson(
      {'id': id, 'index': index, 'title': id, if (parallel) 'parallel': true},
      units: [
        Unit.fromJson({
          'id': '${id}u1',
          'title': 'U',
          'description': '',
          'color': '0xFF58CC02',
          'nodes': [
            for (final n in nodes)
              {'id': '${id}u1$n', 'type': n == 't' ? 'test' : 'lesson', 'title': n, 'rewardXp': 10},
          ],
        }),
      ],
    );

Course course(List<Section> sections) =>
    Course(id: 'exam_x', title: 'X', fromLang: 'tr', learningLang: 'en', sections: sections);

void main() {
  group('§1.1 Leitner boxes', () {
    test('a box-5 word goes up to 60 days, or two boxes down when forgotten', () async {
      final p = Progress(wordBox: const {'w': 5}, wordDue: {'w': today});
      final c = await container(p);
      c.read(progressProvider.notifier).reviewWord('w', known: true);
      expect(c.read(progressProvider).wordBox['w'], 6);
      expect(c.read(progressProvider).wordDue['w'], inDays(60));
      expect(c.read(progressProvider).wordLast['w'], today);

      final c2 = await container(p);
      c2.read(progressProvider.notifier).reviewWord('w', known: false);
      expect(c2.read(progressProvider).wordBox['w'], 3);
      expect(c2.read(progressProvider).wordDue['w'], inDays(7));
    });

    test('low boxes still fall to 0 and the top box is 240 days', () async {
      final c = await container(const Progress(wordBox: {'a': 1, 'b': 2, 'c': 8}));
      final n = c.read(progressProvider.notifier)
        ..reviewWord('a', known: false)
        ..reviewWord('b', known: false)
        ..reviewWord('c', known: true);
      expect(n.state.wordBox, {'a': 0, 'b': 0, 'c': 8});
      expect(n.state.wordDue['a'], today);
      expect(n.state.wordDue['c'], inDays(240));
      expect(reviewIntervals, [0, 1, 3, 7, 14, 30, 60, 120, 240]);
      expect(knownBox, 3);
    });

    test('old saved progress (boxes 0–5, plain mistakes) still reads', () {
      final old = {
        'onboarded': true,
        'wordBox': {'sw_x': 5},
        'wordDue': {'sw_x': '2026-11-01'},
        'mistakes': ['ys1u1l1#2'],
      };
      final p = Progress.fromJson(old);
      expect(p.wordBox['sw_x'], 5);
      expect(p.mistakesDue(today), ['ys1u1l1#2']);
      expect(p.wordLast, isEmpty);
    });
  });

  group('§1.3 error notebook', () {
    test('a wrong question comes back after 1, then 3 days; two right in a row clear it', () async {
      final c = await container(const Progress());
      final n = c.read(progressProvider.notifier)..addMistake('q#1');
      expect(n.state.mistakeDue['q#1'], inDays(1));
      expect(n.state.mistakesDue(today), isEmpty);
      expect(n.state.mistakesDue(inDays(1)), ['q#1']);

      n.answerMistakeRight('q#1');
      expect((n.state.mistakeStage['q#1'], n.state.mistakeDue['q#1']), (1, inDays(3)));
      expect(n.state.mistakes, ['q#1']);
      n.answerMistakeRight('q#1');
      expect(n.state.mistakes, isEmpty);
      expect(n.state.mistakeStage, isEmpty);
    });

    test('a wrong answer between right ones keeps the stage, so 7 and 21 days follow', () async {
      final c = await container(const Progress());
      final n = c.read(progressProvider.notifier)
        ..addMistake('q#1')
        ..answerMistakeRight('q#1')
        ..addMistake('q#1');
      expect((n.state.mistakeStage['q#1'], n.state.mistakeRun['q#1']), (1, 0));
      n.answerMistakeRight('q#1');
      expect(n.state.mistakeDue['q#1'], inDays(7));
      n
        ..addMistake('q#1')
        ..answerMistakeRight('q#1');
      expect(n.state.mistakeDue['q#1'], inDays(21));
    });

    test('a saved mistake without a stage starts at stage 0', () async {
      final c = await container(const Progress(mistakes: ['old#0']));
      c.read(progressProvider.notifier).answerMistakeRight('old#0');
      expect(c.read(progressProvider).mistakeStage['old#0'], 1);
    });

    test('cloud merge keeps the new fields', () {
      final local = Progress(
        wordBox: const {'w': 6},
        wordDue: {'w': inDays(60)},
        wordLast: {'w': today},
        mistakes: const ['a#1'],
        mistakeStage: const {'a#1': 2},
        mistakeDue: {'a#1': inDays(7)},
        mistakeRun: const {'a#1': 1},
      );
      final merged = mergeProgress(local, const Progress(), localNewer: true);
      expect(merged.wordLast, {'w': today});
      expect(merged.mistakeStage, {'a#1': 2});
      expect(merged.mistakeDue, {'a#1': inDays(7)});
      expect(merged.mistakeRun, {'a#1': 1});
      final json = Progress.fromJson(jsonDecode(jsonEncode(merged.toJson())) as Map<String, dynamic>);
      expect(json.mistakeDue, merged.mistakeDue);
    });
  });

  group('§1.2 YDS word cards', () {
    test('cards come from finished vocab lessons only, as ydm_', () {
      expect(courseWordCards(yds, const Progress()), isEmpty);
      final cards = courseWordCards(yds, vocabDone(2));
      expect(cards, isNotEmpty);
      expect(cards.every((c) => c.id.startsWith('ydm_') && c.en.isNotEmpty && c.tr.isNotEmpty), isTrue);
      expect(cards.map((c) => c.id).toSet().length, cards.length);
    });

    test('new cards stop at the daily limit and are cut on a review day', () {
      final p = vocabDone(100);
      final q = reviewQueue(yds, p, today: today);
      expect(q.fresh.length, defaultNewWordsPerDay);
      expect(q.reviewDay, isFalse);

      final cards = courseWordCards(yds, p);
      final busy = p.copyWith(
        wordBox: {for (final c in cards.take(reviewBudgetCards + 1)) c.id: 1},
        wordDue: {for (final c in cards.take(reviewBudgetCards + 1)) c.id: today},
      );
      final q2 = reviewQueue(yds, busy, today: today);
      expect(q2.reviewDay, isTrue);
      expect(q2.due.length, reviewBudgetCards + 1);
      expect(q2.fresh.length, lessThan(defaultNewWordsPerDay ~/ 2));
    });

    test('yds.json cards join when their unit is started and replace the bridge card', () {
      final unit = yds.units.firstWhere((u) => u.nodes.any((n) => n.vocab));
      final lesson = unit.nodes.firstWhere((n) => n.vocab);
      final (_, en) = lesson.exercises.firstWhere((e) => e.type == ExerciseType.match).pairs.first;
      final entry = VocabEntry.fromJson({
        'id': 'yd_${en.toLowerCase()}',
        'word': en,
        'pos': 'verb',
        'topic': unit.id,
        'senses': [
          {'tr': 'anlam', 'def': 'meaning'},
        ],
        'examples': [
          {'en': 'An example.', 'tr': 'Bir örnek.', 'context': 'akademik', 'target': en},
        ],
        'family': ['x'],
      });
      expect(courseWordCards(yds, const Progress(), ydsCards: [entry]), isEmpty);
      final cards = courseWordCards(yds, Progress(completed: {lesson.id: 1}), ydsCards: [entry]);
      expect(cards.first.id, entry.id);
      expect(cards.first.example, 'An example.');
      expect(cards.where((c) => c.en.toLowerCase() == en.toLowerCase()), hasLength(1));
      expect(entry.family, ['x']);
    });

    test('words started today count against the limit', () {
      final p = vocabDone(6).copyWith(counters: {'$today:$newWordsMetric': 15});
      expect(reviewQueue(yds, p, today: today).fresh.length, 5);
    });
  });

  group('§2 side paths, mocks and section order', () {
    test('a parallel section is always open and does not pull the focus', () {
      final c = course([section('ys1', 1), section('ys2', 2), section('ys5', 5, parallel: true)]);
      const fresh = Progress();
      expect(sectionOpen(c, c.sections[2], fresh), isTrue);
      expect(sectionOpen(c, c.sections[1], fresh), isFalse);
      expect(activeNodes(c, fresh).keys, containsAll(['ys1', 'ys5']));
      expect(currentNode(c, fresh)!.id, 'ys1u1l');
      // Passing ys1 opens ys2, never skipped by the side path.
      final passed = Progress(completed: const {'ys1u1l': 1, 'ys1u1t': 1});
      expect(sectionOpen(c, c.sections[1], passed), isTrue);
      expect(currentNode(c, passed)!.id, 'ys2u1l');
    });

    test('sections follow their index, not the file order', () {
      final c = course([section('ys1', 1)])
          .withSections([section('ys3', 3), section('ys0', 0), section('ys2', 2)]);
      expect(c.sections.map((s) => s.index), [0, 1, 2, 3]);
      expect(sectionOpen(c, c.sections.first, const Progress()), isTrue);
      expect(sectionOpen(c, c.sections[1], const Progress()), isFalse);
    });

    test('an exam path has its own "Bölüme atla" keys', () {
      final c = course([section('ys1', 1), section('ys2', 2), section('ys3', 3)]);
      // The general course's "section 5" key must not open YDS sections.
      final general = Progress(completed: {sectionPassId(5): 1});
      expect(sectionOpen(c, c.sections[1], general), isFalse);
      expect(sectionPassKey(c.sections[2]), 'section_ys3');
      final skipped = Progress(completed: {sectionPassKey(c.sections[2]): 1});
      expect(sectionOpen(c, c.sections[1], skipped), isTrue);
      expect(sectionOpen(c, c.sections[2], skipped), isTrue);
      // General course keys keep working.
      final s = Section.fromJson({'id': 's3', 'index': 3, 'title': 'x'});
      expect(sectionPassKey(s), sectionPassId(3));
    });

    test('old records: an exam section with finished steps stays open without its old key', () {
      final c = course([section('ys1', 1), section('ys2', 2), section('ys3', 3)]);
      // Opened before by the shared key, with ys2 steps done: still open.
      final old = Progress(completed: {sectionPassId(5): 1, 'ys2u1l': 1});
      expect(sectionOpen(c, c.sections[1], old), isTrue);
      // Having started the path, the old shared key counts as it did before.
      expect(sectionOpen(c, c.sections[2], old), isTrue);
      // The shared key alone (no YDS steps) opens only the general course.
      final keyOnly = Progress(completed: {sectionPassId(5): 1});
      expect(sectionOpen(c, c.sections[1], keyOnly), isFalse);
      final general = Course(
        id: 'tr_en',
        title: 'G',
        fromLang: 'tr',
        learningLang: 'en',
        sections: [for (var i = 1; i <= 6; i++) section('s$i', i)],
      );
      expect(sectionOpen(general, general.sections[4], keyOnly), isTrue);
      expect(sectionOpen(general, general.sections[5], keyOnly), isFalse);
    });

    test(
      'old records: an exam-path "Bölüme atla" with the shared key still opens once the path is started',
      () {
        final c = course([section('ys1', 1), section('ys2', 2), section('ys3', 3)]);
        // Jumped to section 3 before the keys were split, nothing done there.
        final jumped = Progress(completed: {sectionPassId(3): 1, 'ys1u1l': 1});
        expect(sectionOpen(c, c.sections[2], jumped), isTrue);
        // No step on the exam path: the shared key opens nothing there.
        expect(sectionOpen(c, c.sections[1], Progress(completed: {sectionPassId(3): 1})), isFalse);
      },
    );

    test('a course built directly from sections is in path order too', () {
      final c = course([section('ys2', 2), section('ys1', 1)]);
      expect(c.sections.map((s) => s.id), ['ys1', 'ys2']);
      expect(c.units.first.id, 'ys1u1');
    });

    test('a mock with its own questions asks them in order', () {
      final exercises = [
        for (var i = 0; i < 5; i++)
          {
            'type': 'choice',
            'question': 'Q$i ----.',
            'options': ['a', 'b', 'c', 'd', 'e'],
            'answer': 1,
            'explanation': 'Çünkü b.',
          },
      ];
      final mock = PathNode.fromJson({
        'id': 'ys6m',
        'type': 'mock',
        'title': 'Yarım deneme 1',
        'examId': 'yds',
        'size': 40,
        'minutes': 90,
        'exercises': exercises,
      });
      final s = section('ys6', 6);
      final qs = mockQuestions(s, mock);
      expect(qs.map((q) => q.text), ['Q0 ----.', 'Q1 ----.', 'Q2 ----.', 'Q3 ----.', 'Q4 ----.']);
      expect(qs.first.id, 'ys6m#0');
    });

    test('vocab, parallel and qtype are read from content', () {
      expect(yds.allNodes.where((n) => n.vocab), isNotEmpty);
      final ex = Exercise.fromJson({
        'type': 'choice',
        'qtype': 'cloze',
        'question': 'x',
        'options': ['a', 'b'],
        'answer': 0,
        'explanation': 'y',
      });
      expect(exerciseType(ex), QType.cloze);
      expect(Section.fromJson({'id': 'ys5', 'index': 5, 'title': 'K', 'parallel': true}).parallel, isTrue);
    });
  });

  group('section order field and content extras', () {
    Section withOrder(Section s, int order) =>
        Section(id: s.id, index: s.index, title: s.title, units: s.units, order: order);

    test('a section with order 0 comes first and opens the path; the rest follow it', () {
      final c = course([section('ys1', 1), section('ys2', 2)])
          .withSections([withOrder(section('ys7', 7), 0)]);
      expect(c.sections.map((s) => s.id), ['ys7', 'ys1', 'ys2']);
      expect(sectionOpen(c, c.sections[0], const Progress()), isTrue);
      expect(sectionOpen(c, c.sections[1], const Progress()), isFalse);
      final passed = Progress(completed: const {'ys7u1l': 1, 'ys7u1t': 1});
      expect(sectionOpen(c, c.sections[1], passed), isTrue);
      expect(sectionOpen(c, c.sections[2], passed), isFalse);
      expect(currentNode(c, passed)!.id, 'ys1u1l');
    });

    test('the shipped YDS sections keep their order', () {
      expect(yds.sections.map((s) => s.id).take(4), ['ys1', 'ys2', 'ys3', 'ys4']);
      expect(yds.sections.every((s) => s.order == s.index), isTrue);
    });

    test('reading meta is read from a node', () {
      final n = PathNode.fromJson({
        'id': 'ys6u1l1',
        'type': 'lesson',
        'title': 'Metin',
        'reading': {'field': 'saglik', 'words': 240, 'cefr': 'B1'},
      });
      expect((n.reading!.field, n.reading!.words, n.reading!.cefr), ('saglik', 240, 'B1'));
    });

    test('YDS card contexts are known and unknown ones fall back', () {
      expect(VocabContext.byKey('akademik'), VocabContext.akademik);
      expect(VocabContext.byKey('haber'), VocabContext.haber);
      expect(VocabContext.byKey('yeni_bir_sey'), VocabContext.genel);
    });
  });

  group('question types', () {
    test('YDS teaching units decide the type', () {
      QType typeIn(String unitId) {
        final unit = yds.units.firstWhere((u) => u.id == unitId);
        final ex = unit.nodes.expand((n) => n.exercises).firstWhere((e) => e.type == ExerciseType.choice);
        return exerciseType(ex, unitId: unitId)!;
      }

      expect(typeIn('ys3u7'), QType.dialogue);
      expect(typeIn('ys2u1'), QType.vocabulary);
      expect(typeIn('ys3u1'), QType.cloze);
      expect(typeIn('ys1u2'), QType.grammar);
    });

    test('pack sections decide the type', () {
      final pack = ExamPackContent.fromJson(
        jsonDecode(File('assets/exam_packs/yds_full.json').readAsStringSync()) as Map<String, dynamic>,
      );
      final types = {for (final q in pack.mocks.first.questions) examQuestionType(q)};
      expect(types, containsAll([QType.vocabulary, QType.grammar, QType.reading, QType.cloze]));
      expect(types, isNot(contains(QType.other)));
    });

    test('the text decides in mixed units', () {
      expect(
        questionType(
          question: 'They decided to ---- the meeting.',
          options: ['postpone', 'attend', 'announce'],
        ),
        QType.vocabulary,
      );
      expect(
        questionType(question: 'Scarcely had it opened ---- it closed.', options: ['when', 'than']),
        QType.grammar,
      );
      expect(
        questionType(
          question: 'Although the drug reduced pain, ----.',
          options: ['it caused severe headaches in some', 'most patients felt much better soon'],
        ),
        QType.sentenceCompletion,
      );
      expect(questionType(question: 'Parçadaki (1) numaralı boşluğa?', passage: 'x (1)---- y'), QType.cloze);
      expect(
        questionType(question: 'Diyalogda boş bırakılan yere?', passage: 'A: hi\nB: ----'),
        QType.dialogue,
      );
      expect(
        questionType(
          question: 'Students who sleep less do worse.',
          options: ['Az uyuyan öğrenciler', 'Öğrenci çok'],
        ),
        QType.translation,
      );
      expect(questionType(question: 'According to the passage ----.', passage: 'Long text.'), QType.reading);
    });

    test('every YDS path question gets a real type, and all ten types occur', () {
      final types = <QType>{};
      for (final u in yds.units) {
        for (final ex in u.nodes.expand((n) => n.exercises)) {
          if (exerciseType(ex, unitId: u.id) case final t?) types.add(t);
        }
      }
      expect(types, isNot(contains(QType.other)));
      expect(types.length, QType.values.length - 1);
    });

    test('per-type targets add up to the real exam (80 questions, 72 right)', () {
      expect(QType.values.fold(0, (a, t) => a + t.inExam), 80);
      expect(QType.values.fold(0, (a, t) => a + t.target72), 72);
      final seconds = QType.values.fold(0, (a, t) => a + t.inExam * t.targetSeconds);
      expect(seconds, inInclusiveRange(140 * 60, 150 * 60));
    });
  });

  group('screens', () {
    testWidgets('a lesson answer is logged with type, topic and time; a wrong one joins the notebook', (
      tester,
    ) async {
      final unit = yds.units.firstWhere((u) => u.id == 'ys3u7');
      final lesson = unit.nodes.firstWhere((n) => n.type == NodeType.lesson);
      final i = lesson.exercises.indexWhere((e) => e.type == ExerciseType.choice);
      final ex = lesson.exercises[i];
      final c = await pumpApp(
        tester,
        LessonScreen(
          nodeId: lesson.id,
          title: 'T',
          items: [(key: itemKey(lesson.id, i), ex: ex)],
          color: Brand.primary,
        ),
      );
      final wrong = List.generate(ex.options.length, (k) => k).firstWhere((k) => k != ex.answerIndex);
      await tester.tap(find.byKey(Key('choice-option-$wrong')));
      await tester.pump();
      await tester.tap(find.text('Kontrol et'));
      await tester.pump();
      final log = c.read(studyLogProvider).answers.single;
      expect(
        (log.type, log.unitId, log.correct, log.source),
        (QType.dialogue.name, 'ys3u7', false, 'lesson'),
      );
      final p = c.read(progressProvider);
      expect(p.mistakes, [itemKey(lesson.id, i)]);
      expect(p.mistakeDue[itemKey(lesson.id, i)], inDays(1));
    });

    testWidgets('Tekrar kartları: recall, turn, grade; then the notebook questions due', (tester) async {
      final mistake = itemKey(yds.allNodes.firstWhere((n) => n.type == NodeType.lesson).id, 0);
      final progress = vocabDone(1).copyWith(mistakes: [mistake], mistakeDue: {mistake: today});
      final c = await pumpApp(tester, const SrsReviewScreen(newPerDay: 2), progress: progress);
      final first = tester.widget<Text>(find.byKey(const Key('srs-front'))).data!;
      expect(find.byKey(const Key('srs-hint')), findsOneWidget);
      await tester.tap(find.byKey(const Key('srs-show')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('srs-back')), findsOneWidget);
      expect(find.text('Hatırladın mı?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('srs-good')));
      await tester.pumpAndSettle();
      final id = wordCardId(ydsWordPrefix, first);
      expect(c.read(progressProvider).wordBox[id], 1);
      expect(c.read(progressProvider).counters['$today:$newWordsMetric'], 1);

      await tester.tap(find.byKey(const Key('srs-show')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('srs-again')));
      await tester.pumpAndSettle();
      // A forgotten card comes back once at the end.
      expect(find.byKey(const Key('srs-front')), findsOneWidget);
      await tester.tap(find.byKey(const Key('srs-show')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('srs-good')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('srs-done')), findsOneWidget);
      expect(find.byKey(const Key('srs-mistakes')), findsOneWidget);
    });

    testWidgets('a review day shows that new words were cut', (tester) async {
      final p = vocabDone(100);
      final cards = courseWordCards(yds, p).take(reviewBudgetCards + 1);
      await pumpApp(
        tester,
        const SrsReviewScreen(),
        progress: p.copyWith(
          wordBox: {for (final c in cards) c.id: 1},
          wordDue: {for (final c in cards) c.id: today},
        ),
      );
      expect(find.text('Bugün tekrar günü: yeni kelime azaltıldı'), findsOneWidget);
    });
  });
}
