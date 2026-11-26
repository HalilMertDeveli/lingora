// "Bugün" sequence, "Gerçek ilerleme" metrics and the sync status line.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/app_version.dart';
import 'package:lingora/data/first_lesson.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/goals/learn_goal.dart';
import 'package:lingora/screens/sync_status_line.dart';
import 'package:lingora/screens/today_start_card.dart';
import 'package:lingora/services/firebase/progress_sync.dart';
import 'package:lingora/study/learning_evidence.dart';
import 'package:lingora/study/real_progress.dart';
import 'package:lingora/study/study_state.dart';
import 'package:lingora/study/today_sequence.dart';
import 'package:shared_preferences/shared_preferences.dart';

AnswerLog _a(String key, String day, bool ok) => AnswerLog(key: key, day: day, correct: ok, seconds: 5);

Future<ProviderContainer> _container(DateTime Function() clock, [Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(p), clockProvider.overrideWithValue(clock)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('Bugün sequence', () {
    test('review → lesson → listening from what is due', () {
      final s = buildTodaySequence(const TodayInputs(cardsDue: 12, nextLesson: 'Tanışma', listening: 'Kafede'));
      expect(s.summary, '5 dk tekrar → 1 ders → kısa dinleme');
      expect(s.steps.first.detail, '12 kart');
      expect(s.doneCount, 0);
      expect(s.next!.kind, TodayStepKind.review);
      expect(s.minutesLeft, 13);
    });

    test('nothing due: no review step; no listening piece open: reading', () {
      final s = buildTodaySequence(const TodayInputs(nextLesson: 'Selamlaşma'));
      expect(s.steps.map((x) => x.kind), [TodayStepKind.lesson, TodayStepKind.reading]);
    });

    test('an exam goal reads instead of listening', () {
      final s = buildTodaySequence(const TodayInputs(nextLesson: 'x', listening: 'y', goal: GoalKind.exam));
      expect(s.steps.last.kind, TodayStepKind.reading);
    });

    test('steps are done only by real work, and stay on the list', () {
      final s = buildTodaySequence(
        const TodayInputs(
          reviewedToday: 8,
          nextLesson: 'Tanışma',
          lessonsToday: 1,
          listening: 'Kafede',
          listenedToday: false,
        ),
      );
      expect(s.steps.map((x) => x.done), [true, true, false]);
      expect(s.doneCount, 2);
      expect(s.next!.kind, TodayStepKind.listening);
      // Opened but not finished: still due.
      final opened = buildTodaySequence(const TodayInputs(cardsDue: 3, reviewedToday: 2, nextLesson: 'a'));
      expect(opened.steps.first.done, isFalse);
    });

    test('all done', () {
      final s = buildTodaySequence(const TodayInputs(reviewedToday: 5, lessonsToday: 1, listenedToday: true));
      expect(s.allDone, isTrue);
      expect(s.next, isNull);
    });

    test("the onboarding first lesson counts as today's lesson", () {
      const types = {'u1l1': NodeType.lesson, 'u1c': NodeType.chest};
      expect(lessonsFinished({'u1c'}, types), 0);
      expect(lessonsFinished({firstLessonId}, types), 1);
      expect(lessonsFinished({firstLessonId, 'u1l1', 'u1c'}, types), 2);
    });

    test('nodes finished today come from the start-of-day baseline', () {
      const p = Progress(completed: {'u1l1': 2, 'u1l2': 1, 'u1c': 1});
      const base = DayBaseline('2026-11-19', {'u1l1': 1, 'u1c': 1});
      expect(finishedToday(p, base, '2026-11-19'), {'u1l1', 'u1l2'});
      expect(finishedToday(p, base, '2026-11-20'), isEmpty);
      expect(finishedToday(p, null, '2026-11-19'), isEmpty);
    });
  });

  group('Gerçek ilerleme', () {
    test('a spaced pass needs a later day than the last sighting', () {
      expect(isSpacedPass(known: true, lastSeen: '2026-11-18', today: '2026-11-19'), isTrue);
      expect(isSpacedPass(known: true, lastSeen: '2026-11-19', today: '2026-11-19'), isFalse);
      expect(isSpacedPass(known: true, lastSeen: null, today: '2026-11-19'), isFalse);
      expect(isSpacedPass(known: false, lastSeen: '2026-11-18', today: '2026-11-19'), isFalse);
    });

    test('grading words records passes only when spaced', () async {
      var now = DateTime(2026, 11, 18, 10);
      final c = await _container(() => now);
      final n = c.read(progressProvider.notifier);
      n.learnWord('w1', known: true); // first sight
      n.gradeWord('w1', ReviewGrade.good); // same day again
      expect(c.read(learningEvidenceProvider).wordsPassed, isEmpty);
      now = DateTime(2026, 11, 19, 9);
      n.gradeWord('w1', ReviewGrade.again);
      expect(c.read(learningEvidenceProvider).wordsPassed, isEmpty, reason: 'forgotten');
      now = DateTime(2026, 11, 20, 9);
      n.reviewWord('w1', known: true);
      expect(c.read(learningEvidenceProvider).wordsPassed, {'w1': '2026-11-20'});
    });

    test('a question that leaves the notebook is counted', () async {
      var now = DateTime(2026, 11, 10);
      final c = await _container(() => now);
      final n = c.read(progressProvider.notifier)..addMistake('u1l1#2');
      now = DateTime(2026, 11, 11);
      n.answerMistakeRight('u1l1#2');
      expect(c.read(learningEvidenceProvider).mistakesCleared, isEmpty);
      now = DateTime(2026, 11, 14);
      n.answerMistakeRight('u1l1#2');
      expect(c.read(learningEvidenceProvider).mistakesCleared, {'u1l1#2': '2026-11-14'});
      expect(c.read(progressProvider).mistakes, isEmpty);
      // Another account on the phone starts over.
      n.reset();
      expect(c.read(learningEvidenceProvider).mistakesCleared, isEmpty);
    });

    test('mistake turnaround: retried on a later day, right now', () {
      final log = [
        _a('q1', '2026-11-13', false), _a('q1', '2026-11-15', true), // fixed
        _a('q2', '2026-11-14', false), _a('q2', '2026-11-14', true), // same day only: not retried
        _a('q3', '2026-11-14', false), _a('q3', '2026-11-16', false), // still wrong
        _a('q4', '2026-11-15', false), _a('q4', '2026-11-17', true), _a('q4', '2026-11-18', false),
        _a('q4', '2026-11-18', true), // right after a miss that day: not "artık doğru"
        _a('q5', '2026-11-01', false), _a('q5', '2026-11-16', true), // missed before the window
        _a('q6', '2026-11-12', true), // never missed
      ];
      final t = mistakeTurnaround(log, today: '2026-11-19');
      expect(t.missed, 4);
      expect(t.retried, 3);
      expect(t.nowRight, 1);
      expect(
        turnaroundSentence(t),
        "Son 7 günde karıştırıp sonraki bir gün yeniden çözdüğün 3 sorunun 1'ini artık doğru yapıyorsun.",
      );
    });

    test('the sentence reads naturally and is absent without mistakes', () {
      expect(
        turnaroundSentence(const MistakeTurnaround(missed: 6, retried: 5, nowRight: 4)),
        contains("5 sorunun 4'ünü artık doğru"),
      );
      expect(
        turnaroundSentence(const MistakeTurnaround(missed: 3, retried: 0, nowRight: 0)),
        contains('henüz yeniden sorulmadı'),
      );
      expect(turnaroundSentence(const MistakeTurnaround(missed: 0, retried: 0, nowRight: 0)), isNull);
    });

    test('XP plays no part', () {
      final now = DateTime(2026, 11, 19);
      const e = LearningEvidence(wordsPassed: {'a': '2026-11-01', 'b': '2026-11-18'}, mistakesCleared: {'q': 'x'});
      final r = realProgress(e, const StudyLog(), now);
      expect(r.wordsPassed, 2);
      expect(r.wordsPassedThisWeek, 1);
      expect(r.mistakesCleared, 1);
      expect(realProgress(const LearningEvidence(), const StudyLog(), now).isEmpty, isTrue);
    });
  });

  group('sync status', () {
    final now = DateTime(2026, 11, 19, 12);
    test('one honest line per real state', () {
      expect(syncStatusText(const SyncStatus(SyncState.guest), now), 'Bu telefonda kayıtlı (giriş yapınca yedeklenir)');
      expect(syncStatusText(const SyncStatus(SyncState.off), now), 'Bu telefonda kayıtlı');
      expect(
        syncStatusText(SyncStatus(SyncState.synced, lastSyncedAt: now.subtract(const Duration(seconds: 20))), now),
        'Hesabına yedeklendi · az önce',
      );
      expect(
        syncStatusText(SyncStatus(SyncState.synced, lastSyncedAt: now.subtract(const Duration(minutes: 5))), now),
        'Hesabına yedeklendi · 5 dk önce',
      );
      expect(syncStatusText(const SyncStatus(SyncState.pending), now), 'İnternet gelince yedeklenecek');
      expect(syncStatusText(const SyncStatus(SyncState.error), now), 'İnternet gelince yedeklenecek');
    });
  });

  test('app version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(appVersion, version);
  });
}
