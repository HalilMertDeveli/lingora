// YDS hata defteri: the notebook keeps the learner's own option, says what
// kind of mistake it was and why (rule-based for everyone, the option's own
// reason and the AI "İncele" with Premium), and a server that does not see
// Premium never shows up as a server error.
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/option_glosses.dart';
import 'package:lingora/data/practice.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/screens/study/notebook_screen.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/explain_more.dart';
import 'package:lingora/services/firebase/progress_merge.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/study/mistake_diagnosis.dart';
import 'package:lingora/study/question_types.dart';
import 'package:lingora/study/review_queue.dart' show ydsVocabProvider;
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'premium_test.dart' show FakeBilling;
import 'study_test.dart' show readCourse;
import 'widget_test.dart' show FakeNotifications, FakeSpeech;

final yds = readCourse('exam_yds');
final now = DateTime(2026, 11, 20, 9);

const _choice = Exercise(
  type: ExerciseType.choice,
  question: 'Farmers depend on an ancient ---- system that carries water to their fields.',
  options: ['emission', 'archive', 'irrigation', 'expedition', 'pottery'],
  answerIndex: 2,
  explanation: 'Su taşıyan sistem sulama sistemidir.',
  qtype: 'vocabulary',
);

/// A vocabulary choice question of the YDS course and its key.
LessonItem vocabItem() {
  final unit = yds.units.firstWhere((u) => u.id == 'ys2u1');
  final lesson = unit.nodes.firstWhere((n) => n.type == NodeType.lesson);
  final i = lesson.exercises.indexWhere((e) => e.type == ExerciseType.choice);
  return (key: itemKey(lesson.id, i), ex: lesson.exercises[i]);
}

Map<String, Object?> glossFor(Exercise ex) => {
  'why': [
    for (var i = 0; i < ex.options.length; i++)
      i == ex.answerIndex
          ? 'Doğru: cümleye bu kelime uyuyor.'
          : 'Olmaz: şık $i bu cümlenin anlamına uymuyor.',
  ],
};

/// Answers like the server; [error] makes every call fail with that code.
class FakeExplain implements ExplainMoreService {
  FakeExplain({this.error});
  final String? error;
  final asked = <(ExplainMode, int?)>[];
  @override
  Future<ExplainAnswer> ask(
    ExplainQuestion q,
    ExplainMode mode, {
    String text = '',
    List<ExplainTurn> history = const [],
  }) async {
    asked.add((mode, q.picked));
    if (error case final code?) {
      throw ExplainMoreException(CallableExplainMoreService.messageForCode(code), code: code);
    }
    return const ExplainAnswer('Kelime: seçtiğin şık su taşımaz; sulama taşır.', remaining: 29);
  }
}

Future<ProviderContainer> pump(
  WidgetTester tester,
  Widget home, {
  Progress progress = const Progress(onboarded: true, remindersEnabled: false),
  bool premium = false,
  Map<String, Object?> glosses = const {},
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({'progress_v1': jsonEncode(progress.toJson())});
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 2400));
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
      optionGlossesProvider.overrideWith((ref) async => OptionGlosses(glosses)),
      premiumDevOverrideProvider.overrideWithValue(premium),
      billingServiceProvider.overrideWithValue(FakeBilling()),
      ...overrides,
    ],
  );
  addTearDown(c.dispose);
  await c.read(courseProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildTheme(), home: home),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  group('diagnosis', () {
    test('kind of mistake by question type; cloze by its options', () {
      expect(MistakeKind.of(QType.vocabulary), MistakeKind.vocabulary);
      expect(MistakeKind.of(QType.grammar, options: ['has gone', 'went', 'goes', 'go']), MistakeKind.grammar);
      // Seen on the emulator: a grammar unit's word lesson (bridge / storm /
      // neighbour...) was called a grammar-rule mistake.
      expect(
        MistakeKind.of(QType.grammar, options: ['bridge', 'storm', 'library', 'neighbour', 'weather']),
        MistakeKind.vocabulary,
      );
      expect(MistakeKind.of(QType.sentenceCompletion), MistakeKind.grammar);
      expect(MistakeKind.of(QType.reading), MistakeKind.reading);
      expect(MistakeKind.of(QType.irrelevantSentence), MistakeKind.reading);
      expect(MistakeKind.of(QType.translation), MistakeKind.meaning);
      expect(
        MistakeKind.of(QType.cloze, options: ['benefit', 'harm', 'cost', 'gain']),
        MistakeKind.vocabulary,
      );
      expect(
        MistakeKind.of(QType.cloze, options: ['although', 'because', 'unless', 'despite']),
        MistakeKind.grammar,
      );
      expect(
        MistakeKind.of(QType.cloze, options: ['has been', 'was', 'will be', 'had']),
        MistakeKind.grammar,
      );
    });

    test('the learner option, its own reason without "Olmaz:", and why the right one fits', () {
      final d = diagnoseMistake(_choice, picked: 0, gloss: OptionGloss.parse(glossFor(_choice), 5))!;
      expect(d.kind, MistakeKind.vocabulary);
      expect(d.picked, 'A) emission');
      expect(d.answer, 'C) irrigation');
      expect(d.pickedWhy, 'şık 0 bu cümlenin anlamına uymuyor.');
      expect(d.reason, d.pickedWhy);
      expect(d.rightWhy, startsWith('Doğru'));
    });

    test('no gloss: the rule for the kind and the explanation\'s first sentence', () {
      final d = diagnoseMistake(_choice, picked: 3)!;
      expect(d.pickedWhy, isNull);
      expect(d.reason, MistakeKind.vocabulary.rule);
      expect(d.rightWhy, 'Su taşıyan sistem sulama sistemidir.');
      // Not kept, the right option or out of range: no "Senin cevabın".
      expect(diagnoseMistake(_choice)!.picked, isNull);
      expect(diagnoseMistake(_choice, picked: 2)!.picked, isNull);
      expect(diagnoseMistake(_choice, picked: 9)!.picked, isNull);
    });

    test('non-choice exercises have no diagnosis and no AI request', () {
      const select = Exercise(type: ExerciseType.select, prompt: 'x', answer: 'y');
      expect(diagnoseMistake(select), isNull);
      expect(explainQuestionOf(select), isNull);
      final q = explainQuestionOf(_choice, picked: 0)!;
      expect((q.answer, q.picked, q.options.length), (2, 0, 5));
      expect(explainQuestionOf(_choice, picked: 7)!.picked, isNull);
    });
  });

  group('progress keeps the picked option', () {
    test('saved with the mistake, travels in JSON and the merge, gone when cleared', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs), clockProvider.overrideWithValue(() => now)],
      );
      addTearDown(c.dispose);
      {
        final n = c.read(progressProvider.notifier);
        for (var i = 0; i < mistakeSaveMisses; i++) {
          n.recordWrong('ys2u1l1#0', picked: i);
        }
        var p = c.read(progressProvider);
        expect(p.mistakes, ['ys2u1l1#0']);
        expect(p.mistakePicked['ys2u1l1#0'], mistakeSaveMisses - 1);
        // Wrong again with another option: the last one is kept.
        n.recordWrong('ys2u1l1#0', picked: 4);
        p = c.read(progressProvider);
        expect(p.mistakePicked['ys2u1l1#0'], 4);
        final back = Progress.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
        expect(back.mistakePicked, {'ys2u1l1#0': 4});
        final merged = mergeProgress(const Progress(), back, localNewer: false);
        expect(merged.mistakePicked, {'ys2u1l1#0': 4});
        n.clearMistake('ys2u1l1#0');
        expect(c.read(progressProvider).mistakePicked, isEmpty);
      }
    });
  });

  group('explainMore service', () {
    test('"why" is sent as its own mode without text', () async {
      Object? sent;
      final s = CallableExplainMoreService((name, data) async {
        sent = data;
        return {'answer_tr': 'Kelime: ...', 'remaining': 3};
      });
      final a = await s.ask(explainQuestionOf(_choice, picked: 0)!, ExplainMode.why);
      expect(a.text, 'Kelime: ...');
      final m = sent! as Map;
      expect((m['mode'], m['picked'], m.containsKey('text')), ('why', 0, false));
    });

    test('a server that does not see Premium is "not verified", not a server error', () async {
      final s = CallableExplainMoreService(
        (name, data) async =>
            throw FirebaseFunctionsException(code: 'permission-denied', message: 'premium_required'),
      );
      try {
        await s.ask(explainQuestionOf(_choice, picked: 0)!, ExplainMode.why);
        fail('should throw');
      } on ExplainMoreException catch (e) {
        expect(e.notPremium, isTrue);
        expect(e.message, contains('doğrulanamadı'));
        expect(e.message.toLowerCase(), isNot(contains('sunucu')));
      }
    });

    test('the follow-up chips do not offer the notebook mode', () {
      expect(ExplainMode.followUps, isNot(contains(ExplainMode.why)));
    });
  });

  group('notebook card', () {
    final item = vocabItem();
    final wrong = item.ex.answerIndex == 0 ? 1 : 0;
    Progress withMistake() => Progress(
      onboarded: true,
      remindersEnabled: false,
      mistakes: [item.key],
      mistakeDue: {item.key: dayKey(now)},
      mistakePicked: {item.key: wrong},
    );

    testWidgets('free: your answer, the right one, the kind and the rule; İncele offers Premium', (
      tester,
    ) async {
      final fake = FakeExplain();
      await pump(
        tester,
        const NotebookScreen(),
        progress: withMistake(),
        glosses: {item.key: glossFor(item.ex)},
        overrides: [explainMoreServiceProvider.overrideWithValue(fake)],
      );
      expect(find.textContaining('Senin cevabın: ${'ABCDE'[wrong]})'), findsOneWidget);
      expect(find.textContaining('Doğrusu: ${'ABCDE'[item.ex.answerIndex!]})'), findsOneWidget);
      expect(find.byKey(const Key('mistake-kind')), findsOneWidget);
      expect(find.text(MistakeKind.vocabulary.rule), findsOneWidget);
      // The option's own reason is Premium.
      expect(find.textContaining('bu cümlenin anlamına uymuyor'), findsNothing);
      if (item.ex.explanation?.isNotEmpty ?? false) {
        expect(find.byKey(const Key('mistake-explanation')), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('mistake-inspect-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('premium-offer-explain_more')), findsOneWidget);
      expect(fake.asked, isEmpty);
    });

    testWidgets('Premium: the option\'s own reason and the AI analysis of the mistake', (tester) async {
      final fake = FakeExplain();
      await pump(
        tester,
        const NotebookScreen(),
        progress: withMistake(),
        premium: true,
        glosses: {item.key: glossFor(item.ex)},
        overrides: [explainMoreServiceProvider.overrideWithValue(fake)],
      );
      expect(find.text('şık $wrong bu cümlenin anlamına uymuyor.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('mistake-inspect-button')));
      await tester.pumpAndSettle();
      expect(fake.asked, [(ExplainMode.why, wrong)]);
      expect(find.byKey(const Key('mistake-inspect-answer')), findsOneWidget);
      expect(find.textContaining('sulama taşır'), findsOneWidget);
    });

    testWidgets('Premium on the device, not on the server: the local reason stays, calm note', (
      tester,
    ) async {
      final fake = FakeExplain(error: 'permission-denied');
      await pump(
        tester,
        const NotebookScreen(),
        progress: withMistake(),
        premium: true,
        overrides: [explainMoreServiceProvider.overrideWithValue(fake)],
      );
      await tester.tap(find.byKey(const Key('mistake-inspect-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mistake-inspect-error')), findsOneWidget);
      expect(find.textContaining('doğrulanamadı'), findsOneWidget);
      expect(find.textContaining('Sunucu'), findsNothing);
      // The app's own reason is still there and no retry loop is offered.
      expect(find.byKey(const Key('mistake-reason')), findsOneWidget);
      expect(find.byKey(const Key('mistake-inspect-button')), findsNothing);
    });

    testWidgets('other errors keep a retry', (tester) async {
      await pump(
        tester,
        const NotebookScreen(),
        progress: withMistake(),
        premium: true,
        overrides: [explainMoreServiceProvider.overrideWithValue(FakeExplain(error: 'unavailable'))],
      );
      await tester.tap(find.byKey(const Key('mistake-inspect-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mistake-inspect-error')), findsOneWidget);
      expect(find.text('Tekrar dene'), findsOneWidget);
    });

    testWidgets('an old mistake without a kept option still explains itself', (tester) async {
      await pump(tester, const NotebookScreen(), progress: withMistake().copyWith(mistakePicked: const {}));
      expect(find.byKey(const Key('mistake-picked')), findsNothing);
      expect(find.byKey(const Key('mistake-answer')), findsOneWidget);
      expect(find.byKey(const Key('mistake-why')), findsOneWidget);
    });
  });

  group('lesson, wrong answer', () {
    LessonScreen lesson() => LessonScreen(
      nodeId: 'ys2u1l1',
      title: 'Test',
      items: [(key: 'ys2u1l1#0', ex: _choice)],
      color: Brand.primary,
    );

    Future<void> answer(WidgetTester tester, int option) async {
      await tester.tap(find.byKey(Key('choice-option-$option')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('check')));
      await tester.pumpAndSettle();
    }

    testWidgets('Premium: the explanation and "Hâlâ takıldın mı?" with the picked option', (tester) async {
      final fake = FakeExplain();
      await pump(
        tester,
        lesson(),
        premium: true,
        overrides: [explainMoreServiceProvider.overrideWithValue(fake)],
      );
      await answer(tester, 0);
      expect(find.byKey(const Key('choice-explanation')), findsOneWidget);
      expect(find.byKey(const Key('explain-more')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('explain-confused')));
      await tester.tap(find.byKey(const Key('explain-confused')));
      await tester.pumpAndSettle();
      expect(fake.asked, [(ExplainMode.confused, 0)]);
    });

    testWidgets('free: the explanation only, no AI box', (tester) async {
      await pump(tester, lesson());
      await answer(tester, 0);
      expect(find.byKey(const Key('choice-explanation')), findsOneWidget);
      expect(find.byKey(const Key('explain-more')), findsNothing);
    });

    testWidgets('the picked option is kept when the question reaches the notebook', (tester) async {
      final c = await pump(
        tester,
        lesson(),
        progress: const Progress(
          onboarded: true,
          remindersEnabled: false,
          mistakes: ['ys2u1l1#0'],
          mistakeDue: {'ys2u1l1#0': '2026-11-20'},
        ),
      );
      await answer(tester, 3);
      expect(c.read(progressProvider).mistakePicked['ys2u1l1#0'], 3);
    });
  });
}
