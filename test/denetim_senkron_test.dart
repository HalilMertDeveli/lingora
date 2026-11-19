// Audit items 5, 6 and 7: progress merge across devices (additive counters,
// reset epoch, spaced repetition by the latest review).
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/progress_tally.dart';
import 'package:lingora/services/firebase/progress_merge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One lesson worth [xp], done on [device] (what ProgressNotifier saves).
Progress earn(Progress p, String device, {int xp = 10, String node = 'n1', String day = '2026-11-19'}) =>
    stampTally(
      p.copyWith(
        totalXp: p.totalXp + xp,
        lessonsDone: p.lessonsDone + 1,
        correct: p.correct + 4,
        answered: p.answered + 5,
        xpByDay: {...p.xpByDay, day: (p.xpByDay[day] ?? 0) + xp},
        completed: {...p.completed, node: (p.completed[node] ?? 0) + 1},
      ),
      device,
    );

Progress sync(Progress a, Progress b, String deviceOfA) =>
    stampTally(mergeProgress(a, b, localNewer: true), deviceOfA);

void main() {
  group('additive merge (item 5)', () {
    test('two offline devices each earning 10 XP add up to 20', () {
      const start = Progress(onboarded: true, tally: ProgressTally.empty);
      final a = earn(start, 'A');
      final b = earn(start, 'B');
      final m = mergeProgress(a, b, localNewer: true);
      expect(m.totalXp, 20);
      expect(m.lessonsDone, 2);
      expect(m.correct, 8);
      expect(m.answered, 10);
      expect(m.xpByDay['2026-11-19'], 20);
      expect(m.completed['n1'], 2);
    });

    test('merging again (echoes, both directions) never counts twice', () {
      const start = Progress(onboarded: true, tally: ProgressTally.empty);
      var a = earn(start, 'A');
      var b = earn(start, 'B');
      a = sync(a, b, 'A');
      b = sync(b, a, 'B');
      a = sync(a, b, 'A');
      b = sync(b, a, 'B');
      expect(a.totalXp, 20);
      expect(b.totalXp, 20);
      // More work after converging still adds up.
      a = earn(a, 'A', xp: 5);
      b = earn(b, 'B', xp: 7);
      a = sync(a, b, 'A');
      b = sync(b, a, 'B');
      expect(a.totalXp, 32);
      expect(b.totalXp, 32);
      expect(canonicalProgress(a), canonicalProgress(b));
    });

    test('an old synced document (no tally) is the base: nothing lost or doubled', () {
      const legacy = Progress(onboarded: true, totalXp: 100, lessonsDone: 9, completed: {'n0': 1});
      // Both phones start from the same legacy copy and earn offline.
      final a = earn(migrateTally(legacy), 'A');
      final b = earn(migrateTally(legacy), 'B');
      final m = mergeProgress(a, b, localNewer: false);
      expect(m.totalXp, 120);
      expect(m.lessonsDone, 11);
      // The legacy cloud copy against a migrated phone: the phone's 110.
      final withCloud = mergeProgress(a, legacy, localNewer: true);
      expect(withCloud.totalXp, 110);
      expect(withCloud.completed, {'n0': 1, 'n1': 1});
    });

    test('a document rewritten by an old app version falls back to the maximum', () {
      const start = Progress(onboarded: true, tally: ProgressTally.empty);
      final a = earn(start, 'A', xp: 30);
      // An old client merged A's 30 with its own 10 by max and dropped the tally.
      final old = Progress.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(a.toJson())) as Map)..remove('tally'),
      ).copyWith(totalXp: 30);
      expect(mergeProgress(a, old, localNewer: true).totalXp, 30);
      final bigger = old.copyWith(totalXp: 45);
      expect(mergeProgress(a, bigger, localNewer: true).totalXp, 45);
    });

    test('two legacy copies merge by maximum as before', () {
      const a = Progress(totalXp: 50, lessonsDone: 3);
      const b = Progress(totalXp: 40, lessonsDone: 5);
      final m = mergeProgress(a, b, localNewer: true);
      expect(m.totalXp, 50);
      expect(m.lessonsDone, 5);
    });

    test('the tally survives JSON (Firestore) round trips', () {
      final a = earn(const Progress(tally: ProgressTally.empty), 'A');
      final back = progressFromFirestore(a.toJson());
      expect(back.tally!.devices['A']!['xp'], 10);
      expect(canonicalProgress(back), canonicalProgress(a));
    });
  });

  group('reset epoch (item 6)', () {
    test('a copy from before the reset is discarded, in both directions', () {
      const old = Progress(onboarded: true, totalXp: 500, completed: {'a': 1, 'b': 1}, streak: 9);
      const reset = Progress(onboarded: true, tally: ProgressTally.empty, resetAt: 1000);
      for (final localNewer in [true, false]) {
        expect(mergeProgress(reset, old, localNewer: localNewer).totalXp, 0);
        expect(mergeProgress(old, reset, localNewer: localNewer).completed, isEmpty);
      }
      // Work after the reset is merged normally among up-to-date devices.
      final a = earn(reset, 'A');
      final b = earn(reset, 'B');
      expect(mergeProgress(a, b, localNewer: true).totalXp, 20);
      expect(mergeProgress(a, b, localNewer: true).resetAt, 1000);
    });

    test('ProgressNotifier.reset stamps the reset time', () async {
      SharedPreferences.setMockInitialValues({
        'progress_v1': jsonEncode(const Progress(onboarded: true, totalXp: 70).toJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => DateTime.fromMillisecondsSinceEpoch(5000)),
        ],
      );
      addTearDown(c.dispose);
      c.read(progressProvider.notifier).reset();
      expect(c.read(progressProvider).resetAt, 5000);
      expect(c.read(progressProvider).totalXp, 0);
      c.read(progressProvider.notifier).clearForAccountSwitch();
      expect(c.read(progressProvider).resetAt, 0, reason: 'an account switch is not a reset');
    });
  });

  group('spaced repetition merge (item 7)', () {
    test('a fresh lapse wins over an older review with a later due day', () {
      // Phone A: reviewed "w" on the 10th, known, due on the 24th.
      const a = Progress(
        wordBox: {'w': 4},
        wordDue: {'w': '2026-11-24'},
        wordLast: {'w': '2026-11-10'},
        wordAt: {'w': 100},
      );
      // Phone B: forgot it on the 12th, due again on the 13th.
      const b = Progress(
        wordBox: {'w': 1},
        wordDue: {'w': '2026-11-13'},
        wordLast: {'w': '2026-11-12'},
        wordAt: {'w': 200},
      );
      for (final localNewer in [true, false]) {
        final m = mergeProgress(a, b, localNewer: localNewer);
        expect(m.wordBox['w'], 1);
        expect(m.wordDue['w'], '2026-11-13');
        expect(m.wordAt['w'], 200);
      }
    });

    test('same day: the exact review time decides', () {
      const a = Progress(wordBox: {'w': 0}, wordDue: {'w': '2026-11-19'}, wordLast: {'w': '2026-11-19'}, wordAt: {'w': 900});
      const b = Progress(wordBox: {'w': 3}, wordDue: {'w': '2026-11-26'}, wordLast: {'w': '2026-11-19'}, wordAt: {'w': 100});
      expect(mergeProgress(a, b, localNewer: false).wordBox['w'], 0);
      expect(mergeProgress(b, a, localNewer: true).wordBox['w'], 0);
    });

    test('copies without review times fall back to the later due day', () {
      const a = Progress(wordBox: {'w': 2}, wordDue: {'w': '2026-11-20'});
      const b = Progress(wordBox: {'w': 3}, wordDue: {'w': '2026-11-30'});
      expect(mergeProgress(a, b, localNewer: true).wordBox['w'], 3);
    });

    test('grading a word records its review time', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => DateTime.fromMillisecondsSinceEpoch(1234567)),
        ],
      );
      addTearDown(c.dispose);
      c.read(progressProvider.notifier).gradeWord('w', ReviewGrade.again);
      expect(c.read(progressProvider).wordAt['w'], 1234567);
    });
  });
}
