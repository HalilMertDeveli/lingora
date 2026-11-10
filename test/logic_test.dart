import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/text.dart';
import 'package:lingora/data/catalog.dart';
import 'package:lingora/data/league.dart';
import 'package:lingora/data/notes_practice.dart';
import 'package:lingora/data/practice.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/scenarios.dart';
import 'package:lingora/data/quests.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/models/exam.dart';
import 'package:lingora/models/notes.dart';
import 'package:lingora/services/conversation.dart';
import 'package:lingora/services/notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('answer matching', () {
    test('ignores case, punctuation and spacing', () {
      expect(matchesAny('good  morning, THANKS!', ['Good morning, thanks']), isTrue);
      expect(matchesAny("I’m a student", ["I'm a student"]), isTrue);
      expect(matchesAny('Good night', ['Good morning']), isFalse);
      expect(matchesAny('   ', ['']), isFalse);
    });

    test('spoken similarity counts recognized words', () {
      expect(spokenSimilarity('The bill, please', 'the bill please'), 1.0);
      expect(spokenSimilarity('I eat an apple', 'I eat apple'), 0.75);
      expect(spokenSimilarity('Good morning', ''), 0.0);
    });
  });

  List<Map<String, dynamic>> readAll(String dir) {
    final files = Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return [for (final f in files) jsonDecode(f.readAsStringSync()) as Map<String, dynamic>];
  }

  final allCourses = [for (final j in readAll('assets/courses')) Course.fromJson(j)];
  final general = allCourses.singleWhere((c) => c.id == 'tr_en');

  test('every catalog course exists and node ids are unique across courses', () {
    expect(allCourses.map((c) => c.id).toSet(), containsAll(courseCatalog.map((t) => t.id)));
    final ids = [for (final c in allCourses) ...c.allNodes.map((n) => n.id)];
    expect(ids.toSet().length, ids.length);
  });

  test('mistakes and vocabulary resolve from the general course', () {
    final items = mistakeItems(general, ['u1l1#0', 'nope#1', 'u2l1#3']);
    expect(items.map((i) => i.key), ['u2l1#3', 'u1l1#0']);
    expect(vocabularyPool(general, const Progress()).length, greaterThanOrEqualTo(5));
    expect(general.units.length, greaterThanOrEqualTo(12));
  });

  group('exams', () {
    final exams = [for (final j in readAll('assets/exams')) Exam.fromJson(j)];

    test('every catalog exam exists', () {
      expect(exams.map((e) => e.id).toSet(), containsAll(examCatalog.map((t) => t.id)));
    });

    for (final exam in exams) {
      test('${exam.id} questions are well formed', () {
        final ids = exam.allQuestions.map((q) => q.id).toList();
        expect(ids.toSet().length, ids.length, reason: 'duplicate ids');
        expect(exam.allQuestions.length, greaterThanOrEqualTo(exam.mockSize * 2));
        for (final s in exam.sections) {
          expect(s.questions.length, greaterThanOrEqualTo(8), reason: s.id);
        }
        final answers = List.filled(exam.optionCount, 0);
        for (final q in exam.allQuestions) {
          expect(q.options, hasLength(exam.optionCount), reason: q.id);
          expect(q.options.toSet(), hasLength(exam.optionCount), reason: '${q.id} duplicate options');
          expect(q.answer, inInclusiveRange(0, exam.optionCount - 1), reason: q.id);
          expect(q.explanation.trim(), isNotEmpty, reason: q.id);
          answers[q.answer]++;
        }
        // Correct answers should be spread over the letters, not always "A".
        final most = answers.reduce(max);
        expect(most, lessThan(exam.allQuestions.length * 0.4), reason: 'answer letters $answers');
      });
    }
  });

  for (final course in allCourses) {
    group('course ${course.id}', () {
      test('every exercise is solvable', () {
        for (final node in course.allNodes.where((n) => n.type == NodeType.lesson)) {
          expect(node.exercises, isNotEmpty, reason: node.id);
          for (final ex in node.exercises) {
            final where = '${node.id} ${ex.type.name} ${ex.text ?? ex.prompt ?? ''}';
            switch (ex.type) {
              case ExerciseType.select:
                expect(ex.choices.map((c) => c.text), contains(ex.answer), reason: where);
              case ExerciseType.fillBlank:
                expect(ex.wordChoices, contains(ex.answer), reason: where);
                expect(ex.text, contains('___'), reason: where);
              case ExerciseType.translate:
                // At least one accepted answer must be buildable from the word bank.
                final buildable = ex.answers.any((a) {
                  final bank = ex.tokens.map((t) => t.toLowerCase()).toList();
                  for (final w in normalizeAnswer(a).split(' ')) {
                    if (!bank.remove(w)) return false;
                  }
                  return true;
                });
                expect(buildable, isTrue, reason: where);
              case ExerciseType.listen:
                expect(ex.answers, isNotEmpty, reason: where);
              case ExerciseType.match:
                expect(ex.pairs.length, greaterThanOrEqualTo(3), reason: where);
              case ExerciseType.speak:
                expect(ex.text, isNotEmpty, reason: where);
            }
          }
        }
      });

      test('unit tests can be built for every unit', () {
        for (final u in course.units) {
          final items = unitTestItems(u, Random(1));
          expect(items, hasLength(testSize), reason: u.id);
          expect(items.map((i) => i.key).toSet(), hasLength(testSize), reason: u.id);
          expect(items.where((i) => i.ex.type == ExerciseType.speak), isEmpty);
        }
        expect(vocabularyPool(course, const Progress()).length, greaterThanOrEqualTo(5));
      });

      test('stories are well formed', () {
        for (final node in course.allNodes.where((n) => n.type == NodeType.story)) {
          expect(node.steps.where((s) => !s.isQuestion).length, greaterThanOrEqualTo(6), reason: node.id);
          expect(node.steps.where((s) => s.isQuestion).length, greaterThanOrEqualTo(2), reason: node.id);
          expect(node.steps.first.isQuestion, isFalse, reason: node.id);
          for (final s in node.steps.where((s) => s.isQuestion)) {
            expect(s.choices, contains(s.answer), reason: '${node.id} ${s.prompt}');
          }
        }
      });

      test('every unit has lessons, a story, a test and a chest', () {
        for (final u in course.units) {
          final types = u.nodes.map((n) => n.type).toList();
          expect(types.where((t) => t == NodeType.lesson).length, greaterThanOrEqualTo(3), reason: u.id);
          expect(types, contains(NodeType.story), reason: u.id);
          expect(types, contains(NodeType.test), reason: u.id);
          expect(types.last, NodeType.chest, reason: u.id);
        }
      });
    });
  }

  group('notes from Notion', () {
    final words = (jsonDecode(File('assets/notes/words.json').readAsStringSync()) as List)
        .map((w) => NoteWord.fromJson(w as Map<String, dynamic>))
        .toList();
    final topics = (jsonDecode(File('assets/notes/grammar.json').readAsStringSync()) as List)
        .map((t) => GrammarTopic.fromJson(t as Map<String, dynamic>))
        .toList();
    final meta = jsonDecode(File('assets/notes/meta.json').readAsStringSync()) as Map<String, dynamic>;

    test('words and topics are imported and well formed', () {
      expect(words.length, greaterThan(500));
      expect(topics.length, greaterThan(40));
      expect(words.map((w) => w.id).toSet(), hasLength(words.length));
      expect(topics.map((t) => t.id).toSet(), hasLength(topics.length));
      for (final w in words) {
        expect(w.en.trim(), isNotEmpty, reason: w.id);
        expect(w.tr.trim(), isNotEmpty, reason: w.id);
      }
      expect(meta['goals'] as List, isNotEmpty);
      expect(meta['diaryPrompts'] as List, isNotEmpty);
    });

    test('practice from every topic is solvable', () {
      for (final t in topics) {
        for (final item in topicItems(t, topics, Random(1))) {
          final ex = item.ex;
          if (ex.type == ExerciseType.translate) {
            final bank = ex.tokens.map((x) => x.toLowerCase()).toList();
            final ok = normalizeAnswer(ex.answers.first).split(' ').every(bank.remove);
            expect(ok, isTrue, reason: '${t.id}: ${ex.answers.first}');
          }
        }
      }
    });

    test('spaced repetition picks due words, then new ones', () {
      const p = Progress(wordBox: {'a': 2}, wordDue: {'a': '2026-11-09'});
      const list = [
        NoteWord(id: 'a', en: 'a', tr: 'a', topic: 'x'),
        NoteWord(id: 'b', en: 'b', tr: 'b', topic: 'x'),
      ];
      expect(dueWordCount(list, p, DateTime(2026, 11, 10)), 1);
      expect(wordsToReview(list, p, DateTime(2026, 11, 10)).map((w) => w.id), ['a', 'b']);
      expect(wordQuizItems(words, Random(1)), isNotEmpty);
    });
  });

  group('conversation', () {
    test('app and server know the same scenarios', () {
      final server = File('server/supabase/functions/converse/scenarios.ts').readAsStringSync();
      final ids = RegExp(r'^  (\w+): \{', multiLine: true).allMatches(server).map((m) => m[1]).toSet();
      expect(ids, scenarios.map((s) => s.id).toSet());
    });

    test('demo corrects typical Turkish-speaker mistakes', () async {
      final demo = DemoConversationService();
      final cafe = scenarioById('cafe');
      Future<ChatTurn> say(String text) => demo.send(cafe, [
        ChatMessage(fromUser: false, text: cafe.opening),
        ChatMessage(fromUser: true, text: text),
      ]);
      expect((await say('I am agree with you')).correction, 'I agree with you');
      expect((await say('She like coffee')).correction, 'She likes coffee');
      expect((await say('I have 25 years')).correction, 'I am 25 years old');
      final fine = await say('A latte, please.');
      expect(fine.correction, isNull);
      expect(fine.reply, isNotEmpty);
    });
  });

  group('progress', () {
    late DateTime now;
    late ProviderContainer c;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      now = DateTime(2026, 11, 10, 9);
      c = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs), clockProvider.overrideWithValue(() => now)],
      );
    });
    tearDown(() => c.dispose());

    ProgressNotifier n() => c.read(progressProvider.notifier);
    Progress p() => c.read(progressProvider);

    test('streak grows on consecutive days and resets after a gap', () {
      expect(n().completeNode('a', xp: 10).streak, 1);
      expect(n().completeNode('b', xp: 10).streakExtended, isFalse);
      now = now.add(const Duration(days: 1));
      expect(n().completeNode('c', xp: 10).streak, 2);
      now = now.add(const Duration(days: 2));
      expect(p().streakAt(now), 0);
      expect(n().completeNode('d', xp: 10).streak, 1);
      expect(p().totalXp, 40);
    });

    test('daily quests are stable per day and claimable once', () {
      final quests = questsForDay(now);
      expect(quests, hasLength(3));
      expect(quests.map((q) => q.id).toSet(), hasLength(3));
      expect(quests.first.metric, QuestMetric.xp);
      expect(questsForDay(now.add(const Duration(hours: 5))).map((q) => q.id), quests.map((q) => q.id));

      final xpQuest = quests.first;
      expect(n().claimQuest(xpQuest), isFalse);
      n().completeNode(
        'a',
        xp: 15,
        answered: 8,
        correct: 8,
        perfect: true,
        stats: {QuestMetric.listen: 1, QuestMetric.translate: 2, QuestMetric.match: 1},
      );
      final r = n().completeNode('b', xp: 30, answered: 8, correct: 7);
      expect(r.questsCompleted.map((q) => q.id), contains(xpQuest.id));
      expect(p().counter(now, QuestMetric.lessons), 2);
      expect(p().counter(now, QuestMetric.perfectLessons), 1);
      expect(p().counter(now, QuestMetric.translate), 2);

      final before = p().totalXp;
      expect(n().claimQuest(xpQuest), isTrue);
      expect(n().claimQuest(xpQuest), isFalse);
      expect(p().totalXp, before + xpQuest.rewardXp);
      // Reward XP does not count toward XP quests.
      expect(p().counter(now, QuestMetric.xp), 45);

      // Next day: fresh quests, old counters pruned after a week.
      now = now.add(const Duration(days: 9));
      n().setDailyGoal(20);
      expect(p().counters, isEmpty);
      expect(p().claimed, isEmpty);
    });

    test('league week settles into promotion or demotion', () {
      n().settleLeague();
      expect(p().leagueWeek, dayKey(weekStart(now)));
      expect(p().leagueResult, isNull);

      // A huge week finishes first and promotes.
      n().completeNode('a', xp: 5000, answered: 1, correct: 1);
      now = now.add(const Duration(days: 7));
      n().settleLeague();
      expect(p().leagueResult!.rank, 1);
      expect(p().leagueTier, 1);
      n().dismissLeagueResult();
      expect(p().leagueResult, isNull);

      // A week with no XP finishes last and demotes.
      now = now.add(const Duration(days: 7));
      n().settleLeague();
      expect(p().leagueResult!.rank, leagueSize);
      expect(p().leagueTier, 0);

      // In the lowest league, a zero week never promotes or demotes.
      now = now.add(const Duration(days: 7));
      n().settleLeague();
      expect(p().leagueTier, 0);
    });

    test('rivals are deterministic and grow during the week', () {
      final start = weekStart(now);
      final early = rivals(tier: 2, weekStart: start, now: start.add(const Duration(days: 1)));
      final late = rivals(tier: 2, weekStart: start, now: start.add(const Duration(days: 6)));
      expect(early, hasLength(leagueSize - 1));
      expect([for (final r in early) r.name], [for (final r in late) r.name]);
      for (var i = 0; i < early.length; i++) {
        expect(late[i].xp, greaterThanOrEqualTo(early[i].xp));
      }
      expect(weekStart(DateTime(2026, 11, 15, 23)), DateTime(2026, 11, 9));
    });

    test('reminders skip today once practiced and mention the streak', () {
      expect(planNotifications(p(), now), isEmpty); // not enabled yet
      n().setReminders(enabled: true, minutes: 19 * 60);

      var plan = planNotifications(p(), now); // 09:00, nothing done today
      final reminders = plan;
      expect(reminders, hasLength(reminderDays));
      expect(reminders.first.when, DateTime(2026, 11, 10, 19));
      expect(reminders.first.title, isNot(contains('serini')));

      n().completeNode('a', xp: 10, answered: 5, correct: 5);
      plan = planNotifications(p(), now);
      final next = plan;
      expect(next, hasLength(reminderDays - 1));
      expect(next.first.when, DateTime(2026, 11, 11, 19));
      expect(next.first.title, contains('1 günlük serini koru'));
      // Two days out the streak would already be lost.
      expect(next[1].title, isNot(contains('serini')));

      // After 19:00, today's reminder is in the past and is not scheduled.
      final evening = DateTime(2026, 11, 12, 20);
      expect(planNotifications(p(), evening).first.when, DateTime(2026, 11, 13, 19));
    });

    test('track and best exam score persist', () {
      expect(p().trackId, defaultTrackId);
      n().setTrack('yds');
      n().recordExam('yds', 60);
      n().recordExam('yds', 45);
      expect(p().examBest['yds'], 60);
      expect(Progress.fromJson(p().toJson()).trackId, 'yds');
    });

    test('word reviews move between boxes; diary and goals persist', () {
      n().reviewWord('w1', known: true);
      n().reviewWord('w1', known: true);
      expect(p().wordBox['w1'], 2);
      expect(p().wordDue['w1'], '2026-11-13');
      n().reviewWord('w1', known: false);
      expect(p().wordBox['w1'], 0);
      n().saveDiary('2026-11-10', 'Today I studied.');
      n().toggleGoal('g');
      final restored = Progress.fromJson(p().toJson());
      expect(restored.diary['2026-11-10'], 'Today I studied.');
      expect(restored.goalsDone, ['g']);
    });

    test('mistakes are remembered, capped and cleared', () {
      n().addMistake('u1l1#0');
      n().addMistake('u1l1#2');
      n().addMistake('u1l1#0'); // moves to the end, no duplicate
      expect(p().mistakes, ['u1l1#2', 'u1l1#0']);
      n().clearMistake('u1l1#2');
      expect(p().mistakes, ['u1l1#0']);
      for (var i = 0; i < maxMistakes + 5; i++) {
        n().addMistake('x#$i');
      }
      expect(p().mistakes, hasLength(maxMistakes));
    });

    test('progress survives a restart', () async {
      n().finishOnboarding(30);
      n().completeNode('u1l1', xp: 15, correct: 8, answered: 9);
      final prefs = await SharedPreferences.getInstance();
      final c2 = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      addTearDown(c2.dispose);
      final restored = c2.read(progressProvider);
      expect(restored.onboarded, isTrue);
      expect(restored.dailyGoal, 30);
      expect(restored.isDone('u1l1'), isTrue);
      expect(restored.totalXp, 15);
    });
  });
}
