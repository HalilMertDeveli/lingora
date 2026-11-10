import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/text.dart';
import 'package:lingora/data/league.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/quests.dart';
import 'package:lingora/models/course.dart';
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

  group('course content', () {
    final course = Course.fromJson(
      jsonDecode(File('assets/courses/tr_en.json').readAsStringSync()) as Map<String, dynamic>,
    );

    test('ids are unique', () {
      final ids = course.allNodes.map((n) => n.id).toList();
      expect(ids.toSet().length, ids.length);
    });

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
  });

  group('progress', () {
    late DateTime now;
    late ProviderContainer c;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      now = DateTime(2026, 11, 10, 9);
      c = ProviderContainer(overrides: [
        prefsProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => now),
      ]);
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

    test('hearts are lost and refill over time', () {
      expect(n().loseHeart(), 4);
      expect(n().loseHeart(), 3);
      now = now.add(heartRefill);
      expect(p().heartsAt(now), 4);
      // Losing a heart mid-refill keeps the timer running.
      now = now.add(const Duration(minutes: 10));
      expect(n().loseHeart(), 3);
      expect(p().nextHeartIn(now), const Duration(minutes: 20));
      now = now.add(heartRefill * 10);
      expect(p().heartsAt(now), maxHearts);
      expect(p().nextHeartIn(now), isNull);
    });

    test('daily quests are stable per day and claimable once', () {
      final quests = questsForDay(now);
      expect(quests, hasLength(3));
      expect(quests.map((q) => q.id).toSet(), hasLength(3));
      expect(quests.first.metric, QuestMetric.xp);
      expect(questsForDay(now.add(const Duration(hours: 5))).map((q) => q.id),
          quests.map((q) => q.id));

      final xpQuest = quests.first;
      expect(n().claimQuest(xpQuest), isFalse);
      n().completeNode('a', xp: 15, answered: 8, correct: 8, perfect: true,
          stats: {QuestMetric.listen: 1, QuestMetric.translate: 2, QuestMetric.match: 1});
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
      final reminders = plan.where((x) => x.id < heartsFullId).toList();
      expect(reminders, hasLength(reminderDays));
      expect(reminders.first.when, DateTime(2026, 11, 10, 19));
      expect(reminders.first.title, isNot(contains('serini')));

      n().completeNode('a', xp: 10, answered: 5, correct: 5);
      plan = planNotifications(p(), now);
      final next = plan.where((x) => x.id < heartsFullId).toList();
      expect(next, hasLength(reminderDays - 1));
      expect(next.first.when, DateTime(2026, 11, 11, 19));
      expect(next.first.title, contains('1 günlük serini koru'));
      // Two days out the streak would already be lost.
      expect(next[1].title, isNot(contains('serini')));

      // After 19:00, today's reminder is in the past and is not scheduled.
      final evening = DateTime(2026, 11, 12, 20);
      expect(planNotifications(p(), evening).first.when, DateTime(2026, 11, 13, 19));
    });

    test('hearts-full alert is planned only while hearts are refilling', () {
      n().setReminders(enabled: true);
      expect(planNotifications(p(), now).where((x) => x.id == heartsFullId), isEmpty);
      n().loseHeart();
      n().loseHeart();
      final alert = planNotifications(p(), now).singleWhere((x) => x.id == heartsFullId);
      expect(alert.when, now.add(heartRefill * 2));
      n().setReminders(heartAlerts: false);
      expect(planNotifications(p(), now).where((x) => x.id == heartsFullId), isEmpty);
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
