// Help on retrying a failed unit test: attempts, the lower pass mark from the
// third attempt, greyed-out options, hints and "Hatalarının özeti".
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/practice.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/test_retry.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/lesson_result_screen.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/study/question_types.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeNotifications, FakeSpeech;

Map<String, dynamic> _choice(String q, String right, List<String> wrong, {String? explanation}) => {
  'type': 'choice',
  'question': q,
  'options': [right, ...wrong],
  'answer': 0,
  'explanation': ?explanation,
};

const _careful = {
  'type': 'choice',
  'question': 'Please be ---- when you cross this road; cars drive very fast here.',
  'options': ['noisy', 'cheap', 'careful', 'crowded', 'useful'],
  'answer': 2,
  'explanation':
      "Doğru cevap 'careful' (dikkatli). Arabaların hızlı gittiği bir yolda karşıya geçerken dikkatli "
      "olmak gerekir. 'noisy' (gürültülü) ve 'crowded' (kalabalık) bir kişinin karşıdan karşıya "
      'geçerken nasıl olması gerektiğini anlatmaz.',
};

const _guide =
    '## Kural\nFiil cümlenin **kalbidir**.\n\n## Sınav ipucu\n- Boşluğun **arkasına** bak: nesne mi, '
    '*that* mi?\n\nİkinci paragraf.';

Unit _unit() => Unit.fromJson({
  'id': 'ys1u1',
  'title': 'Zamanlar',
  'description': '',
  'color': '0xFF1E88E5',
  'guide': _guide,
  'nodes': [
    {
      'id': 'ys1u1t',
      'type': 'test',
      'title': 'Mini YDS',
      'description': '',
      'exercises': [
        for (var i = 0; i < 5; i++)
          _choice('Question $i ---- here.', 'right$i', [
            'wrongA$i',
            'wrongB$i',
            'wrongC$i',
            'wrongD$i',
          ], explanation: "Doğru cevap 'right$i'. 'wrongA$i' burada anlam vermez."),
      ],
    },
  ],
});

final _course = Course(
  id: 'exam_yds',
  title: 'YDS',
  fromLang: 'tr',
  learningLang: 'en',
  sections: [
    Section.fromJson({'id': 's1', 'index': 1, 'title': 'Bölüm 1', 'cefr': 'B2'}, units: [_unit()]),
  ],
);

LessonItem _item(String key, Map<String, dynamic> json) => (key: key, ex: Exercise.fromJson(json));

void main() {
  group('attempts and pass mark', () {
    test('the pass mark drops from the third attempt and never goes away', () {
      expect(passPercentFor(1), testPassPercent);
      expect(passPercentFor(2), testPassPercent);
      expect(passPercentFor(eliminateFromAttempt), easedPassPercent);
      expect(passPercentFor(9), easedPassPercent);
      expect(easedPassPercent, greaterThan(0));
      expect(easedPassPercent, lessThan(testPassPercent));
    });

    test('a record adds up failed attempts, misses and picks', () {
      final r = TestRecord.empty.withFail(['t#0', 't#1'], {'t#0': 3}).withFail(['t#0'], {'t#0': 1});
      expect(r.failed, 2);
      expect(r.nextAttempt, 3);
      expect(r.missed, {'t#0': 2, 't#1': 1});
      expect(r.picked, {'t#0': 1});
      final back = TestRecord.fromJson(jsonDecode(jsonEncode(r.toJson())));
      expect(back.failed, 2);
      expect(back.missed, r.missed);
      expect(back.picked, r.picked);
      expect(TestRecord.fromJson('junk').failed, 0);
    });

    test('the store keeps attempts per test and forgets them when cleared', () async {
      SharedPreferences.setMockInitialValues({});
      final store = TestRetryStore(await SharedPreferences.getInstance());
      expect(store.load('t').nextAttempt, 1);
      store.recordFail('t', ['t#0'], const {});
      store.recordFail('t', ['t#1'], const {'t#1': 2});
      expect(store.load('t').nextAttempt, 3);
      expect(store.load('other').nextAttempt, 1);
      store.clear('t');
      expect(store.load('t').nextAttempt, 1);
    });
  });

  group('help per attempt', () {
    final missed = _item('t#0', _careful);
    final fresh = _item('t#1', _careful);
    RetryHelp help(int failed) =>
        RetryHelp(TestRecord(failed: failed, missed: const {'t#0': 1}, picked: const {'t#0': 4}));

    test('attempt 1: no hints, nothing greyed out', () {
      final h = help(0);
      expect(h.hintsFor(missed.key), isFalse);
      expect(h.eliminatedFor(missed), isEmpty);
      expect(h.passPercent, testPassPercent);
    });

    test('attempt 2: hints only on questions missed before', () {
      final h = help(1);
      expect(h.hintsFor(missed.key), isTrue);
      expect(h.hintsFor(fresh.key), isFalse);
      expect(h.eliminatedFor(missed), isEmpty);
      expect(h.eased, isFalse);
    });

    test('attempt 3: two wrong options greyed out, the last pick first', () {
      final h = help(2);
      final gone = h.eliminatedFor(missed);
      expect(gone, hasLength(maxEliminatedOptions));
      expect(gone, contains(4));
      expect(gone, isNot(contains(2)), reason: 'the right option is never greyed out');
      expect(h.eliminatedFor(fresh), isEmpty);
      expect(h.passPercent, easedPassPercent);
      expect(h.eliminatedFor(missed), gone, reason: 'the same options every time');
    });

    test('at least two options always stay', () {
      final three = Exercise.fromJson(_choice('q', 'a', ['b', 'c']));
      expect(eliminateOptions(three, seed: 'x'), hasLength(1));
      final two = Exercise.fromJson(_choice('q', 'a', ['b']));
      expect(eliminateOptions(two, seed: 'x'), isEmpty);
      final select = Exercise.fromJson({'type': 'select', 'prompt': 'kedi', 'answer': 'cat'});
      expect(eliminateOptions(select, seed: 'x'), isEmpty);
    });
  });

  group('hints', () {
    test('the explanation clue keeps notes on wrong options, never the answer', () {
      final clue = explanationClue(Exercise.fromJson(_careful))!;
      expect(clue, contains("'noisy'"));
      expect(clue.toLowerCase(), isNot(contains('careful')));
      expect(clue.toLowerCase(), isNot(contains('dikkatli')));
    });

    test('the guide rule comes from its tip section, as plain short text', () {
      expect(guideRule(_guide), 'Boşluğun arkasına bak: nesne mi, that mi?');
      expect(guideRule(null), isNull);
      final long = guideRule('## Kural\n${'Uzun bir cümle burada. ' * 30}')!;
      expect(long.length, lessThanOrEqualTo(hintRuleMaxChars));
    });

    test('a rule that names the answer falls back to the question type tip', () {
      final hint = hintFor(
        Exercise.fromJson(_careful),
        guide: '## Kural\nA careful driver is safe.',
        type: QType.vocabulary,
      )!;
      expect(hint.rule, qTypeTips[QType.vocabulary]);
    });

    test('no hint on the real YDS tests gives the right option away', () {
      final dir = Directory('assets/courses/exam_yds');
      final files = [
        File('assets/courses/exam_yds.json'),
        ...dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')),
      ];
      var checked = 0;
      for (final f in files) {
        final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        for (final u in (json['units'] as List).cast<Map<String, dynamic>>()) {
          final unit = Unit.fromJson(u);
          for (final node in unit.nodes.where((n) => n.type == NodeType.test)) {
            for (final ex in node.exercises.where((e) => e.type == ExerciseType.choice)) {
              final hint = hintFor(
                ex,
                guide: unit.guide,
                type: exerciseType(ex, unitId: unit.id),
              );
              final right = ex.correctOption.toLowerCase();
              if (hint == null || right.length < 3) continue;
              final text = '${hint.rule ?? ''} ${hint.clue ?? ''}'.toLowerCase();
              expect(text, isNot(contains(right)), reason: '${node.id}: ${ex.question}');
              checked++;
            }
          }
        }
      }
      expect(checked, greaterThan(100));
    });
  });

  test('the summary names the topics missed most', () {
    final course = _course;
    final test = course.units.first.nodes.first;
    final items = lessonItems(test);
    final vocab = Exercise.fromJson({
      ..._choice('Word ---- .', 'apple', ['run']),
      'qtype': 'vocabulary',
    });
    final topics = missSummary(
      [items[0], items[1], items[2], (key: 'ys1u1t#9', ex: vocab)],
      course: course,
      testNodeId: test.id,
    );
    expect(topics.first.count, 3);
    expect(topics.map((t) => '${t.label}: ${t.count}'), ['Zamanlar: 3', 'Kelime: 1']);
    expect(topics.last.tip, qTypeTips[QType.vocabulary]);
  });

  group('screens', () {
    Future<ProviderContainer> pump(WidgetTester tester, Widget Function() home) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 1000));
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
        ],
      );
      addTearDown(container.dispose);
      await container.read(courseProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: buildTheme(), home: home()),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('the failed screen shows the summary and retries with hints', (tester) async {
      var retried = false;
      await pump(
        tester,
        () => TestFailedScreen(
          accuracy: 40,
          onRetry: () => retried = true,
          topics: const [MissedTopic(label: 'Zamanlar', count: 3, tip: 'Zaman ifadelerine bak.')],
          rule: 'Fiil cümlenin kalbidir.',
          nextAttempt: 3,
        ),
      );
      expect(find.text('Hatalarının özeti'), findsOneWidget);
      expect(find.text('Zamanlar: 3 yanlış'), findsOneWidget);
      expect(find.text('Fiil cümlenin kalbidir.'), findsOneWidget);
      expect(find.textContaining('geçme sınırı %$easedPassPercent'), findsOneWidget);
      expect(find.text('Tekrar dene (ipuçlarıyla)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('test-retry')));
      expect(retried, isTrue);
    });

    testWidgets('a failed attempt is analysed and the retry shows hints', (tester) async {
      final unit = _course.units.first;
      final node = unit.nodes.first;
      LessonScreen build() => LessonScreen(
        nodeId: node.id,
        title: node.title,
        items: testItems(unit, node),
        color: Colors.blue,
        mode: LessonMode.test,
        retry: build,
      );
      final container = await pump(tester, build);

      Future<void> answer(int option) async {
        await tester.tap(find.byKey(Key('choice-option-$option')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('check')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('feedback-continue')));
        await tester.pumpAndSettle();
      }

      // Attempt 1: no help; every answer wrong (option B).
      expect(find.byKey(const Key('retry-banner')), findsNothing);
      expect(find.byKey(const Key('hint-button')), findsNothing);
      for (var i = 0; i < 5; i++) {
        await answer(1);
      }
      expect(find.text('Hatalarının özeti'), findsOneWidget);
      expect(find.text('Zamanlar: 5 yanlış'), findsOneWidget);
      expect(container.read(testRetryStoreProvider).load(node.id).failed, 1);

      // Attempt 2: banner and "İpucu", the pass mark unchanged.
      await tester.tap(find.byKey(const Key('test-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('retry-banner')), findsOneWidget);
      expect(find.textContaining('%$easedPassPercent'), findsNothing);
      expect(find.byKey(const Key('hint-card')), findsNothing);
      await tester.tap(find.byKey(const Key('hint-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hint-card')), findsOneWidget);
      expect(find.textContaining('Boşluğun arkasına bak'), findsOneWidget);
      expect(find.byKey(const Key('hint-eliminated')), findsNothing);
      for (var i = 0; i < 5; i++) {
        await answer(1);
      }

      // Attempt 3: the lower pass mark and greyed-out options.
      await tester.tap(find.byKey(const Key('test-retry')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Bu denemede geçme sınırı %$easedPassPercent'), findsOneWidget);
      expect(find.text('$maxEliminatedOptions şık elendi'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Elendi'),
        findsNWidgets(maxEliminatedOptions),
      );
      // All right: passed, and the attempts are forgotten.
      for (var i = 0; i < 5; i++) {
        await answer(0);
      }
      expect(container.read(testRetryStoreProvider).load(node.id).failed, 0);
    });
  });
}
