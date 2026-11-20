// Mülakat Provası: the grammar tag → existing lesson mapping, the question
// bank's no-repeat rule, unaided-task tracking, the first-vs-latest facts,
// and the first rehearsal flow (typed, with the offline demo analysis).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/goals/goal_paywall_copy.dart';
import 'package:lingora/goals/learn_goal.dart';
import 'package:lingora/data/rehearsal.dart';
import 'package:lingora/screens/paywall_screen.dart';
import 'package:lingora/screens/rehearsal/rehearsal_screen.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/rehearsal_service.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/services/voice_recorder.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'premium_test.dart' show FakeBilling;
import 'widget_test.dart' show FakeSpeech;

final now = DateTime(2026, 11, 18, 10);

/// The server's tag list, read from functions/src/rehearsal.ts.
List<String> serverTags() {
  final src = File('functions/src/rehearsal.ts').readAsStringSync();
  final block = RegExp(r'GRAMMAR_TAGS = \[([^\]]*)\]').firstMatch(src)!.group(1)!;
  return [for (final m in RegExp(r'"([a-z_]+)"').allMatches(block)) m.group(1)!];
}

RehearsalAnalysis analysis({List<GrammarError> errors = const [], int gaps = 0}) => RehearsalAnalysis(
  summaryTr: 's',
  gaps: [for (var i = 0; i < gaps; i++) const ContentGap(type: 'impact', quote: '', messageTr: 'm')],
  errors: errors,
  exercises: const [],
  retellPromptTr: 'r',
  retellChecklistTr: const [],
);

GrammarError err(String tag, int n) => GrammarError(
  tag: tag,
  explanationTr: '',
  examples: [for (var i = 0; i < n; i++) GrammarExample('a$i', 'b$i')],
);

RehearsalSession session(String id, DateTime at, RehearsalAnalysis a, {String answer = 'I built the app.'}) =>
    RehearsalSession(
      id: id,
      kind: id == 'first' ? RehearsalKind.first : RehearsalKind.interview,
      at: at,
      answers: [RehearsalAnswer(questionId: 'q_$id', question: 'Q?', answer: answer)],
      analysis: a,
    );

void main() {
  test('the interview goal sells the rehearsal first', () {
    final c = goalPaywallCopy(const LearnGoal(kind: GoalKind.interview), now);
    expect(c.focus.first, PremiumFeature.interviewRehearsal);
  });

  group('grammar tags → existing grammar-path lessons', () {
    final lessonIds = {
      for (final l in jsonDecode(File('assets/notes/lessons.json').readAsStringSync()) as List)
        (l as Map)['id'],
    };

    test('every server tag has a Turkish name and a mapping', () {
      final tags = serverTags();
      expect(tags, hasLength(grammarTagLessons.length));
      for (final t in tags) {
        expect(grammarTagLessons.containsKey(t), isTrue, reason: t);
        expect(grammarTagNames.containsKey(t), isTrue, reason: t);
      }
    });

    test('every mapped lesson exists in lessons.json (read-only)', () {
      for (final e in grammarTagLessons.entries) {
        for (final id in e.value) {
          expect(lessonIds, contains(id), reason: '${e.key} → $id');
        }
      }
      expect(grammarTagLessons['word_choice'], isEmpty);
    });

    test('lessonsForTags keeps order and drops duplicates', () {
      expect(lessonsForTags(['past_simple', 'to_be']), ['simple_past', 'to_be_past', 'to_be_present']);
      expect(lessonsForTags(['word_choice']), isEmpty);
      expect(lessonsForTags(['unknown']), isEmpty);
    });
  });

  group('question bank', () {
    test('at least 30 questions in three categories, unique ids and texts', () {
      expect(interviewQuestionBank.length, greaterThanOrEqualTo(30));
      final ids = {
        for (final q in [...firstRehearsalQuestions, ...interviewQuestionBank]) q.id,
      };
      expect(ids.length, firstRehearsalQuestions.length + interviewQuestionBank.length);
      expect({for (final q in interviewQuestionBank) q.text}.length, interviewQuestionBank.length);
      for (final c in QuestionCategory.values) {
        expect(interviewQuestionBank.where((q) => q.category == c).length, greaterThanOrEqualTo(8));
      }
    });

    test('never repeats an asked question and mixes categories', () {
      final asked = {for (final q in firstRehearsalQuestions) q.id};
      final seen = <String>{};
      for (var round = 0; round < 20; round++) {
        final picked = pickNewQuestions(asked, seed: round);
        if (picked.isEmpty) break;
        for (final q in picked) {
          expect(asked.contains(q.id), isFalse, reason: 'repeated ${q.id}');
          expect(seen.add(q.id), isTrue);
        }
        // While every category has questions left, one of each.
        if (round < 8) {
          expect({for (final q in picked) q.category}.length, QuestionCategory.values.length);
        }
        asked.addAll(picked.map((q) => q.id));
      }
      expect(seen.length, interviewQuestionBank.length, reason: 'every question is used once');
      expect(pickNewQuestions(asked), isEmpty);
    });

    test('a nearly empty bank returns fewer questions, never repeats', () {
      final all = {for (final q in interviewQuestionBank) q.id};
      final left = interviewQuestionBank.first;
      expect(pickNewQuestions(all..remove(left.id)).map((q) => q.id), [left.id]);
    });
  });

  group('unaided tasks', () {
    late ProviderContainer c;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      c = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs), clockProvider.overrideWithValue(() => now)],
      );
    });
    tearDown(() => c.dispose());

    test('a task is unaided only without hints and wrong tries; first result is kept', () {
      final store = c.read(rehearsalProvider.notifier);
      store.completeTask('s:ex0', 'clean', TaskAttempt());
      store.completeTask('s:ex1', 'wrong once', TaskAttempt()..wrong());
      store.completeTask('s:ex2', 'answer shown', TaskAttempt()..hint());
      store.completeTask('s:ex0', 'again, with help', TaskAttempt()..hint());
      final s = c.read(rehearsalProvider);
      expect(s.tasks, hasLength(3));
      expect([for (final t in s.unaidedTasks) t.title], ['clean']);
      expect(s.tasks.first.day, dayKey(now));
    });

    test('answers count as unaided only without retakes or hints', () {
      expect(const RehearsalAnswer(questionId: 'a', question: 'q', answer: 'x').unaided, isTrue);
      expect(const RehearsalAnswer(questionId: 'a', question: 'q', answer: 'x', retakes: 1).unaided, isFalse);
      expect(
        const RehearsalAnswer(questionId: 'a', question: 'q', answer: 'x', hintShown: true).unaided,
        isFalse,
      );
    });

    test('history survives a restart and the comparison only counts', () async {
      final store = c.read(rehearsalProvider.notifier);
      store.putSession(
        session('later', now, analysis(errors: [err('past_simple', 1), err('passive', 1)], gaps: 1)),
      );
      store.putSession(
        session(
          'first',
          now.subtract(const Duration(days: 3)),
          analysis(errors: [err('past_simple', 3), err('articles', 2)], gaps: 2),
          answer: 'We make app.',
        ),
      );
      final prefs = c.read(prefsProvider);
      final again = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      addTearDown(again.dispose);
      final s = again.read(rehearsalProvider);
      expect([for (final x in s.sessions) x.id], ['first', 'later'], reason: 'sorted by date');
      expect(s.askedQuestions, {'q_first', 'q_later'});
      expect(s.earlierTags, containsAll(['past_simple', 'articles', 'passive']));

      final cmp = RehearsalComparison(s.first!, s.latest!, const []);
      expect(
        [for (final e in cmp.errorCounts) '${e.tag}:${e.before}→${e.after}'],
        ['past_simple:3→1', 'articles:2→0'],
      );
      expect(cmp.newTags, ['passive']);
      expect((cmp.gapsBefore, cmp.gapsAfter), (2, 1));
      expect((cmp.first.wordCount, cmp.latest.wordCount), (3, 4));
    });
  });

  test('exercise answers ignore case, punctuation and spaces', () {
    const x = RehearsalExercise(
      kind: ExerciseKind.fixSentence,
      instructionTr: '',
      prompt: 'We make app',
      answer: 'We made a payment app.',
      tag: 'past_simple',
    );
    expect(x.accepts('we made a  payment app'), isTrue);
    expect(x.accepts('We make a payment app.'), isFalse);
  });

  test('the demo analysis finds the repeated past tense and the missing contribution', () async {
    final a = await DemoRehearsalService(delay: Duration.zero).analyze(
      const RehearsalRequest(
        id: 'r1',
        kind: RehearsalKind.first,
        answers: [
          RehearsalAnswer(
            questionId: 'project',
            question: 'Tell me about one of your projects.',
            answer: 'Last year we make a payment app. It was very big project and we use Kotlin.',
          ),
        ],
      ),
    );
    expect(a.tags, containsAll(['past_simple', 'articles']));
    expect(a.errorCount('past_simple'), 2);
    expect(a.gaps.map((g) => g.type), contains('contribution'));
    expect(a.exercises.length, inInclusiveRange(3, 5));
    expect(a.recurrenceNoteTr, isEmpty);
  });

  group('screens', () {
    Future<ProviderContainer> pump(WidgetTester tester, {bool premium = false}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => now),
          speechProvider.overrideWithValue(FakeSpeech()),
          voiceRecorderProvider.overrideWithValue(NoVoiceRecorder()),
          rehearsalServiceProvider.overrideWithValue(DemoRehearsalService(delay: Duration.zero)),
          billingServiceProvider.overrideWithValue(FakeBilling()),
          premiumDevOverrideProvider.overrideWithValue(premium),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(theme: buildTheme(), home: const RehearsalHomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('free: the first rehearsal is typed, analysed, and the next day is Premium', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      final c = await pump(tester);
      await tester.tap(find.byKey(const Key('prova-start')));
      await tester.pumpAndSettle();
      // No microphone in tests: typing is the fallback.
      await tester.tap(find.byKey(const Key('prova-mic')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('prova-answer-field')),
        'I am Mert, I am backend developer.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prova-next')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('prova-answer-field')),
        'Last year we make a payment app. It was very big project and we use Kotlin.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prova-next')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('prova-analysis')), findsOneWidget);
      expect(find.textContaining('senin katkın anlaşılmadı'), findsOneWidget);
      final saved = c.read(rehearsalProvider).sessions.single;
      expect(saved.answers.map((a) => a.typed), [true, true]);
      expect(saved.analysis!.tags, contains('past_simple'));

      await tester.scrollUntilVisible(find.byKey(const Key('prova-to-home')), 200);
      await tester.ensureVisible(find.byKey(const Key('prova-to-home')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prova-to-home')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('prova-today-card')), findsOneWidget);
      // Back on the same Prova home, not a second copy stacked on it.
      expect(find.byType(RehearsalHomeScreen, skipOffstage: false), findsOneWidget);
      expect(find.byKey(const Key('prova-analysis'), skipOffstage: false), findsNothing);
      await tester.tap(find.byKey(const Key('prova-today-card')));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
    });

    testWidgets('Premium: today\'s exercise done first try is listed as unaided', (tester) async {
      final c = await pump(tester, premium: true);
      c
          .read(rehearsalProvider.notifier)
          .putSession(
            session(
              'first',
              now,
              const RehearsalAnalysis(
                summaryTr: 's',
                gaps: [],
                errors: [],
                exercises: [
                  RehearsalExercise(
                    kind: ExerciseKind.fillBlank,
                    instructionTr: 'Boşluğu doldur.',
                    prompt: 'We ___ Kotlin.',
                    answer: 'used',
                    tag: 'past_simple',
                  ),
                ],
                retellPromptTr: 'r',
                retellChecklistTr: [],
              ),
            ),
          );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prova-today-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prova-ex-0')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('prova-ex-field')), 'used');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prova-check')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('prova-ex-right')), findsOneWidget);
      expect(c.read(rehearsalProvider).unaidedTasks, hasLength(1));
    });
  });
}
