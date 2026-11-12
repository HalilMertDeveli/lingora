// Phase 2a skill exercise types (docs/genel-mufredat.md §3): write, shadow,
// listen-first stories, AI writing feedback and the "section completed" rule.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/tr_errors.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/practice.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/sections.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/screens/section_header.dart';
import 'package:lingora/screens/story_screen.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/services/writing.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'course_content_test.dart' show baseIds, validateExercise, validateSection;

class _Speech implements SpeechService {
  _Speech({this.heard});
  final String? heard;
  final said = <(String, double)>[];
  @override
  Future<void> say(String text, {String lang = 'en', bool slow = false, double rate = 1}) async =>
      said.add((text, rate));
  @override
  Future<bool> get canListen async => heard != null;
  @override
  Future<void> listen({required void Function(String) onWords, required void Function() onDone}) async {
    onWords(heard ?? '');
    onDone();
  }

  @override
  Future<void> stopListening() async {}
}

class _NoNotifications implements NotificationService {
  @override
  void Function(String? payload)? get onTap => null;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> apply(List<PlannedNotification> plan) async {}
}

class _FakeWriting implements WritingService {
  final calls = <(String, String)>[];
  @override
  Future<WritingFeedback> assess(String taskId, String text) async {
    calls.add((taskId, text));
    return WritingFeedback.fromJson({
      'scores': {'task': 3, 'accuracy': 2, 'range': 2, 'coherence': 3},
      'corrections': [
        {
          'from': 'I went to beach',
          'to': 'I went to the beach',
          'why_tr': 'Belli bir plaj: the.',
          'type': 'article',
        },
        {'from': 'I have went', 'to': 'I went', 'why_tr': 'Geçmiş zaman.', 'type': 'tense'},
        {'from': 'very much fun', 'to': 'a lot of fun', 'why_tr': 'Kalıp.', 'type': 'other'},
      ],
      'next_tr': 'Bir sonraki metinde artikellere dikkat et.',
      'remaining': 9,
    });
  }
}

const _write = Exercise(
  type: ExerciseType.write,
  prompt: "Sam'e hafta sonunu anlatan kısa bir e-posta yaz.",
  model: 'Hi Sam, last weekend I went to the beach with Elif. Then we had fish. It was great! Best, Kerem',
  minWords: 8,
  maxWords: 30,
  checklist: ['Selamlama ve kapanış var', 'En az iki geçmiş zaman fiili'],
  focus: ['article', 'tense'],
  taskId: 's5u13l4w',
);

const _shadow = Exercise(
  type: ExerciseType.shadow,
  text: 'Would you like to come with us?',
  translation: 'Bizimle gelmek ister misin?',
  rate: 0.9,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  SpeechService? speech,
  WritingService? writing,
  bool premium = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final p = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final scope = ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(p),
      speechProvider.overrideWithValue(speech ?? _Speech()),
      notificationServiceProvider.overrideWithValue(_NoNotifications()),
      writingServiceProvider.overrideWithValue(writing),
      premiumDevOverrideProvider.overrideWithValue(premium),
    ],
    child: MaterialApp(theme: buildTheme(), home: child),
  );
  await tester.pumpWidget(scope);
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

LessonScreen _lesson(Exercise ex) => LessonScreen(
  nodeId: 's5u13l4',
  title: 'Yazma',
  items: [(key: 's5u13l4#0', ex: ex)],
  color: Brand.primary,
);

Unit _unit(String id, List<PathNode> nodes) =>
    Unit(id: id, title: id, description: '', color: Brand.primary, nodes: nodes);

PathNode _node(String id, NodeType type, [List<Exercise> ex = const []]) =>
    PathNode(id: id, type: type, title: id, description: '', exercises: ex, rewardXp: 10);

Progress _done(Iterable<String> ids) => Progress(onboarded: true, completed: {for (final id in ids) id: 1});

void main() {
  group('model', () {
    test('reads write, shadow and listen-first stories', () {
      final w = Exercise.fromJson({
        'type': 'write',
        'prompt': 'Görev',
        'model': 'Model',
        'minWords': 60,
        'maxWords': 100,
        'checklist': ['a', 'b'],
        'focus': ['article'],
        'taskId': 'x1w',
      });
      expect((w.minWords, w.maxWords, w.taskId), (60, 100, 'x1w'));
      expect(w.checklist, ['a', 'b']);
      expect(w.focus, ['article']);
      expect(w.displayAnswer, 'Model');
      final s = Exercise.fromJson({'type': 'shadow', 'text': 'Hi there.', 'translation': 'Selam.'});
      expect((s.rate, s.displayAnswer), (0.9, 'Hi there.'));
      final story = PathNode.fromJson({'id': 'n', 'type': 'story', 'title': 't', 'listenFirst': true});
      expect(story.listenFirst, isTrue);
      expect(PathNode.fromJson({'id': 'n', 'type': 'story', 'title': 't'}).listenFirst, isFalse);
    });

    test('unit tests and "Bölüme atla" leave practised-only types out', () {
      final lesson = _node('u1l1', NodeType.lesson, [
        _write,
        _shadow,
        const Exercise(type: ExerciseType.speak, text: 'Hi.'),
        const Exercise(type: ExerciseType.listen, text: 'Hi.', answers: ['Hi.']),
      ]);
      final unit = _unit('u1', [lesson, _node('u1t', NodeType.test)]);
      expect(unitTestItems(unit).map((it) => it.ex.type), [ExerciseType.listen]);
      final section = Section(id: 's1', index: 1, title: 'x', units: [unit]);
      expect(sectionSkipItems(section).map((it) => it.ex.type), [ExerciseType.listen]);
    });
  });

  group('contract', () {
    Map<String, Object?> writeJson([Map<String, Object?> change = const {}]) => {
      'type': 'write',
      'prompt': 'Görev',
      'model': 'Hi Sam, I went to the beach and had fish with Elif.',
      'minWords': 8,
      'maxWords': 20,
      'checklist': ['Selamlama'],
      'focus': ['article', 'tense'],
      'taskId': 's2u1l1w',
      ...change,
    };

    test('a write exercise needs a task, a model of the right length, a checklist and known focus types', () {
      expect(validateExercise(writeJson(), 'x'), isEmpty);
      expect(validateExercise(writeJson()..remove('model'), 'x'), anyElement(contains('model')));
      expect(
        validateExercise(writeJson({'minWords': 30, 'maxWords': 40}), 'x'),
        anyElement(contains('kelime')),
      );
      expect(validateExercise(writeJson({'maxWords': 4}), 'x'), anyElement(contains('maxWords')));
      expect(validateExercise(writeJson({'checklist': []}), 'x'), anyElement(contains('checklist')));
      expect(
        validateExercise(
          writeJson({
            'focus': ['spelling'],
          }),
          'x',
        ),
        anyElement(contains('focus')),
      );
      expect(
        validateExercise(
          writeJson({
            'focus': ['article', 'tense', 'be', 'preposition'],
          }),
          'x',
        ),
        anyElement(contains('focus')),
      );
    });

    test('a shadow exercise needs text, translation and a sane rate', () {
      final ok = {'type': 'shadow', 'text': 'Hi.', 'translation': 'Selam.'};
      expect(validateExercise(ok, 'x'), isEmpty);
      expect(validateExercise({...ok, 'rate': 2}, 'x'), anyElement(contains('rate')));
      expect(validateExercise({...ok}..remove('translation'), 'x'), anyElement(contains('translation')));
    });

    test('a write in a section file is named after its node and stories may be listen-first', () {
      final fixture = jsonDecode(File('test/fixtures/tr_en/02_gunluk_hayat.json').readAsStringSync()) as Map;
      final nodes = ((fixture['units'] as List).first as Map)['nodes'] as List;
      final lesson = nodes.first as Map;
      (lesson['exercises'] as List)[0] = writeJson({'taskId': 's9u9l9w'});
      final story = nodes.firstWhere((n) => (n as Map)['type'] == 'story') as Map;
      story['listenFirst'] = true;
      final wrongId = validateSection('02_ornek.json', fixture, baseIds());
      expect(wrongId, anyElement(contains('taskId "s2u1l1w" olmalı')));
      (lesson['exercises'] as List)[0] = writeJson({'taskId': '${lesson['id']}w'});
      expect(validateSection('02_ornek.json', fixture, baseIds()), isEmpty);
      story['listenFirst'] = 'yes';
      expect(validateSection('02_ornek.json', fixture, baseIds()), anyElement(contains('listenFirst')));
    });
  });

  group('section completed', () {
    final skillsTestNode = _node('s2u15t', NodeType.test, [
      const Exercise(type: ExerciseType.listen, text: 'Hi.', answers: ['Hi.']),
    ]);
    final writeLesson = _node('s2u15l4', NodeType.lesson, [_write]);

    test('S1–S4 style: only the skills test counts', () {
      final section = Section(
        id: 's2',
        index: 2,
        title: 'x',
        units: [
          _unit('s2u14', [_node('s2u14t', NodeType.test)]),
          _unit('s2u15', [_node('s2u15l4', NodeType.lesson), skillsTestNode]),
        ],
      );
      expect(skillsTest(section)?.id, 's2u15t');
      expect(sectionCompleted(section, _done(['s2u14t'])), isFalse);
      expect(sectionCompleted(section, _done(['s2u15t'])), isTrue);
    });

    test('with a writing task in the last unit, both are needed', () {
      final section = Section(
        id: 's5',
        index: 5,
        title: 'x',
        units: [
          _unit('s2u15', [writeLesson, skillsTestNode]),
        ],
      );
      expect(sectionCompleted(section, _done(['s2u15t'])), isFalse);
      expect(sectionCompleted(section, _done(['s2u15l4'])), isFalse);
      expect(sectionCompleted(section, _done(['s2u15t', 's2u15l4'])), isTrue);
    });

    testWidgets('the section header marks a completed section, read from the full course', (tester) async {
      final full = Section(
        id: 's2',
        index: 2,
        title: 'Günlük hayat',
        units: [
          _unit('s2u15', [_node('s2u15l4', NodeType.lesson), skillsTestNode]),
        ],
      );
      // What the path draws: the outline, without exercises.
      final outline = Section(
        id: 's2',
        index: 2,
        title: 'Günlük hayat',
        units: [
          _unit('s2u15', [_node('s2u15l4', NodeType.lesson), _node('s2u15t', NodeType.test)]),
        ],
      );
      SharedPreferences.setMockInitialValues({
        'progress_v1': jsonEncode(_done(['s2u15t']).toJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prefsProvider.overrideWithValue(prefs),
            courseProvider.overrideWith(
              (ref) async =>
                  Course(id: 'tr_en', title: 'x', fromLang: 'tr', learningLang: 'en', sections: [full]),
            ),
          ],
          child: MaterialApp(
            theme: buildTheme(),
            home: Scaffold(body: SectionHeader(section: outline, open: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('section-completed-s2')), findsOneWidget);
      expect(find.text('Tamamlandı'), findsOneWidget);
    });

    test('a section without a skills test is never "completed"', () {
      final section = Section(
        id: 's6',
        index: 6,
        title: 'x',
        units: [
          _unit('s6u1', [_node('s6u1t', NodeType.test)]),
        ],
      );
      expect(sectionCompleted(section, _done(['s6u1t'])), isFalse);
    });
  });

  group('writing feedback', () {
    test('local check: length and checklist', () {
      expect(wordCount("I'm here, it's 5 o'clock."), 5);
      expect(localWritingCheck(_write, 'Hi Sam', {0, 1}).done, isFalse);
      final text = 'Hi Sam, last weekend I went to the beach. Bye!';
      expect(localWritingCheck(_write, text, {0}).done, isFalse);
      final ok = localWritingCheck(_write, text, {0, 1});
      expect(ok.done, isTrue);
      expect(ok.notes, isEmpty);
    });

    test('server answers are clamped and error types map to the app\'s categories', () {
      final f = WritingFeedback.fromJson({
        'scores': {'task': 5, 'accuracy': -1, 'range': 2.4},
        'corrections': [
          {'from': 'a', 'to': 'b', 'type': 'be'},
        ],
      });
      expect(f.scores, {'task': 3, 'accuracy': 0, 'range': 2});
      expect(f.corrections.single.whyTr, '');
      expect(f.nextTr, '');
      expect(['article', 'tense', 'preposition', 'word_order', 'be', 'other'].map(errorCategoryOf), [
        TrErrorCategory.article,
        TrErrorCategory.tense,
        TrErrorCategory.preposition,
        TrErrorCategory.wordOrder,
        TrErrorCategory.toBe,
        null,
      ]);
    });

    test('the callable client sends taskId and text and reads the reply', () async {
      final sent = <(String, Map<String, Object?>)>[];
      final service = CallableWritingService((name, data) async {
        sent.add((name, data));
        return {
          'scores': {'task': 2},
          'corrections': [],
          'next_tr': 'Devam.',
          'remaining': 4,
        };
      });
      final f = await service.assess('s5u13l4w', 'Hello');
      expect(sent.single.$1, 'assessWriting');
      expect(sent.single.$2, {'taskId': 's5u13l4w', 'text': 'Hello'});
      expect(f.scores, {'task': 2});
      expect((f.nextTr, f.remaining), ('Devam.', 4));
      final broken = CallableWritingService((_, _) async => throw Exception('offline'));
      expect(() => broken.assess('x', 'y'), throwsA(isA<WritingException>()));
    });
  });

  group('write exercise', () {
    testWidgets('free: done with enough words and the checklist, then the model text', (tester) async {
      await _pump(tester, _lesson(_write));
      expect(find.text('Kontrol listesi'), findsOneWidget);
      expect(find.textContaining('internet ve hesap gerekir'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('write-text')),
        'Hi Sam, last weekend I went to the beach. Bye!',
      );
      await tester.pump();
      expect(find.text('10 kelime'), findsOneWidget);
      final check = find.text('Kontrol et');
      await tester.tap(check);
      await tester.pump();
      expect(find.byKey(const Key('write-model')), findsNothing, reason: 'checklist not ticked yet');
      await tester.tap(find.byKey(const Key('write-check-0')));
      await tester.tap(find.byKey(const Key('write-check-1')));
      await tester.pump();
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('write-model')), findsOneWidget);
      expect(find.textContaining('last weekend I went to the beach with Elif'), findsOneWidget);
    });

    testWidgets('signed in without Premium: the feedback button leads to Premium', (tester) async {
      await _pump(tester, _lesson(_write), writing: _FakeWriting());
      expect(find.byKey(const Key('write-feedback-premium')), findsOneWidget);
      expect(find.byKey(const Key('write-feedback')), findsNothing);
    });

    testWidgets('Premium: AI feedback shows scores and corrections and feeds the error analysis', (
      tester,
    ) async {
      final writing = _FakeWriting();
      final container = await _pump(tester, _lesson(_write), writing: writing, premium: true);
      final button = find.byKey(const Key('write-feedback'));
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull, reason: 'too short yet');
      await tester.enterText(
        find.byKey(const Key('write-text')),
        'Hi Sam, last weekend I went to beach. Bye!',
      );
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(writing.calls.single.$1, 's5u13l4w');
      expect(find.byKey(const Key('write-feedback-card')), findsOneWidget);
      expect(find.text('Görev: 3/3'), findsOneWidget);
      expect(find.textContaining('I went to the beach', findRichText: true), findsOneWidget);
      expect(find.textContaining('artikellere dikkat'), findsOneWidget);
      // "other" is not a category of the error analysis.
      expect(container.read(progressProvider).errorStats, {'article': 1, 'tense': 1});
      expect(find.text('Düzelttim, tekrar bak'), findsOneWidget);
      expect(find.byKey(const Key('write-rewrite-hint')), findsOneWidget);
    });
  });

  group('shadow exercise', () {
    testWidgets('listen hidden, then with text, then say it along', (tester) async {
      final speech = _Speech(heard: 'would you like to come with us');
      final container = await _pump(tester, _lesson(_shadow), speech: speech);
      expect(find.byKey(const Key('shadow-text')), findsNothing);
      await tester.tap(find.byKey(const Key('shadow-next')));
      await tester.pump();
      expect(find.byKey(const Key('shadow-text')), findsOneWidget);
      expect(speech.said.last, ('Would you like to come with us?', 0.9));
      await tester.tap(find.byKey(const Key('shadow-next')));
      await tester.pump();
      expect(find.text('3. Hemen ardından söyle'), findsOneWidget);
      final heard = speech.said.length;
      await tester.tap(find.byKey(const Key('shadow-replay')));
      expect(speech.said.length, heard + 1);
      await tester.tap(find.byKey(const Key('shadow-mic')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kontrol et'));
      await tester.pumpAndSettle();
      expect(find.text('Doğru cevap:'), findsNothing);
      expect(container.read(progressProvider).mistakes, isEmpty);
    });

    testWidgets('a poor try is not saved to the mistakes notebook', (tester) async {
      final container = await _pump(tester, _lesson(_shadow), speech: _Speech(heard: 'hello'));
      await tester.tap(find.byKey(const Key('shadow-next')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('shadow-next')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('shadow-mic')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kontrol et'));
      await tester.pumpAndSettle();
      expect(find.text('Doğru cevap:'), findsOneWidget);
      expect(container.read(progressProvider).mistakes, isEmpty);
    });

    testWidgets('without a microphone it can be skipped', (tester) async {
      await _pump(tester, _lesson(_shadow), speech: _Speech());
      expect(find.text('Şu an konuşamıyorum'), findsOneWidget);
    });
  });

  group('listen-first story', () {
    PathNode story({bool listenFirst = true}) => PathNode(
      id: 's5u13s',
      type: NodeType.story,
      title: 'Hikâye',
      description: '',
      rewardXp: 15,
      listenFirst: listenFirst,
      steps: const [
        StoryStep.line(
          speaker: 'Elif',
          avatar: '👩',
          text: 'The train leaves at nine.',
          translation: 'Tren dokuzda.',
        ),
        StoryStep.question(prompt: 'Tren kaçta?', choices: ['Sekizde', 'Dokuzda'], answer: 'Dokuzda'),
      ],
    );

    testWidgets('hides the text until the end, then "Metni gör" shows it', (tester) async {
      final speech = _Speech();
      await _pump(
        tester,
        StoryScreen(node: story(), color: Brand.primary),
        speech: speech,
      );
      expect(find.text('The train leaves at nine.'), findsNothing);
      expect(find.byKey(const Key('story-hidden-line-0')), findsOneWidget);
      expect(speech.said.single, ('The train leaves at nine.', 1.0));
      // Slower listening.
      await tester.tap(find.byKey(const Key('story-speed')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('story-hidden-line-0')));
      expect(speech.said.last.$2, 0.75);
      // Answer the question; the text opens only after the story ends.
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('story-reveal')), findsNothing);
      await tester.tap(find.text('Dokuzda'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('story-reveal')));
      await tester.pumpAndSettle();
      expect(find.text('The train leaves at nine.'), findsOneWidget);
    });

    testWidgets('an ordinary story shows its text and no speed toggle', (tester) async {
      await _pump(tester, StoryScreen(node: story(listenFirst: false), color: Brand.primary));
      expect(find.text('The train leaves at nine.'), findsOneWidget);
      expect(find.byKey(const Key('story-speed')), findsNothing);
    });
  });
}
