// Galaxy QA follow-up (feature/qa-takip): league XP above the total XP, the
// daily reading level of a beginner, the reading list tags and the reminder
// delivery window.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/catalog.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/progress_tally.dart';
import 'package:lingora/data/reading_repository.dart';
import 'package:lingora/data/sections.dart';
import 'package:lingora/models/reading.dart';
import 'package:lingora/services/firebase/progress_merge.dart';
import 'package:lingora/services/growth/daily_reading.dart';
import 'package:lingora/services/notifications.dart';

int dayXp(Progress p) => p.xpByDay.values.fold(0, (a, v) => a + v);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('league XP never above the total XP', () {
    // users/{uid} of the Galaxy account (2026-11-20): the base held every
    // day of the guest's and the account's copies but only the larger
    // copy's total, so the week (293, reported to the league) was 10 XP
    // above the top bar (283).
    const days = {'2026-11-16': 25, '2026-11-17': 228, '2026-11-18': 10};
    final stored = Progress(
      onboarded: true,
      totalXp: 283,
      xpByDay: const {...days, '2026-11-20': 30},
      tally: const ProgressTally(
        base: {'xp': 253, 'd:2026-11-16': 25, 'd:2026-11-17': 228, 'd:2026-11-18': 10},
        devices: {
          'phone': {'xp': 30, 'd:2026-11-20': 30},
        },
      ),
    );

    test('a stored copy heals on load: total = XP of the days', () {
      final healed = healXp(stored);
      expect(healed.totalXp, 293);
      expect(healed.weekXp(DateTime(2026, 11, 16)), 293);
      // The fix goes into the base: this phone's own share is unchanged.
      expect(healed.tally!.base['xp'], 263);
      expect(healed.tally!.devices['phone'], {'xp': 30, 'd:2026-11-20': 30});
      expect(healXp(healed), same(healed));
    });

    test('merging keeps the total at least the XP of the days', () {
      final merged = mergeProgress(stored, stored, localNewer: true);
      expect(merged.totalXp, 293);
      expect(merged.totalXp, greaterThanOrEqualTo(dayXp(merged)));
    });

    test("a guest's copy merged into the account (no tallies, other days)", () {
      // Account: 253 XP on 16–17 Nov. Guest on the same phone: 10 XP on 18 Nov.
      const account = Progress(totalXp: 253, xpByDay: {'2026-11-16': 25, '2026-11-17': 228});
      const guest = Progress(totalXp: 10, xpByDay: {'2026-11-18': 10});
      for (final m in [
        mergeProgress(guest, account, localNewer: true),
        mergeProgress(account, guest, localNewer: false),
      ]) {
        expect(m.xpByDay, days);
        expect(m.totalXp, 263);
      }
    });

    test('nothing changes when the total already covers the days', () {
      const p = Progress(totalXp: 500, xpByDay: {'2026-11-16': 25});
      expect(healXp(p), same(p));
      final t = consistentXp(const ProgressTally(base: {'xp': 500, 'd:2026-11-16': 25}));
      expect(t.base['xp'], 500);
    });
  });

  group('daily reading level', () {
    test('a beginner without a placement test reads A1, not A2', () {
      expect(suggestedDailyLevel(const Progress()), 'A1');
      expect(suggestedDailyLevel(const Progress(trackId: 'tr_en')), 'A1');
    });

    test("the course section's CEFR decides before the track guess", () {
      expect(suggestedDailyLevel(const Progress(), courseLevel: 'B1'), 'B1');
      expect(suggestedDailyLevel(const Progress(trackId: 'yds'), courseLevel: 'A2'), 'A2');
      expect(suggestedDailyLevel(const Progress(trackId: 'yds')), 'B2');
      expect(suggestedDailyLevel(const Progress(), courseLevel: 'Z9'), 'A1');
    });

    test('course CEFR labels map to a reading band', () {
      expect(dailyBandOf('A1'), 'A1');
      expect(dailyBandOf('A2+–B1'), 'A2');
      expect(dailyBandOf('b2'), 'B2');
      expect(dailyBandOf('C2'), 'C1');
      expect(dailyBandOf(''), isNull);
    });

    test('general course: Bölüm 1 is A1, an opened later section its own level', () async {
      final course = await loadCourse(rootBundle, defaultTrackId);
      final main = mainSections(course);
      expect(courseDailyLevel(course, const Progress()), dailyBandOf(main.first.cefr));
      expect(courseDailyLevel(course, const Progress()), 'A1');
      final later = main.firstWhere((s) => dailyBandOf(s.cefr) == 'B1');
      final opened = Progress(completed: {sectionPassId(later.index): 1});
      expect(courseDailyLevel(course, opened), 'B1');
    });
  });

  test('reading list: no "Genel" tag on some general stories, YDS keeps its own', () {
    ReadingStory story(String id) => ReadingStory.fromJson({
      'id': id,
      'level': 'A1',
      'title': 't',
      'titleTr': 't',
      'text': 'x',
      'glosses': <String, dynamic>{},
      'questions': <Object>[],
    });
    expect(readingSource(story('go_a1')), isNull);
    expect(readingSource(story('s1')), isNull);
    expect(readingSource(story('yb_1')), 'YDS');
  });

  group('reminder window', () {
    const channel = MethodChannel('lingora/reminder_window');
    final calls = <MethodCall>[];
    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        c,
      ) async {
        calls.add(c);
        return 1;
      });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    });

    final plan = planNotifications(
      const Progress(remindersEnabled: true, reminderMinutes: 20 * 60),
      DateTime(2026, 11, 20, 10),
    );

    test('Android: the scheduled reminders move into a 10-minute window at the chosen time', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await narrowReminderWindows(plan);
      expect(calls, hasLength(1));
      final args = calls.single.arguments as Map;
      expect(calls.single.method, 'narrow');
      expect(args['ids'], [for (final n in plan) n.id]);
      expect(args['at'], [for (final n in plan) n.when.millisecondsSinceEpoch]);
      expect((args['at'] as List).first, DateTime(2026, 11, 20, 20).millisecondsSinceEpoch);
      // Ten minutes: not an exact alarm, so no SCHEDULE_EXACT_ALARM.
      expect(args['windowMs'], const Duration(minutes: 10).inMilliseconds);
      expect(reminderWindow, const Duration(minutes: 10));
    });

    test('nothing to do elsewhere or with nothing planned; a failure is harmless', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await narrowReminderWindows(plan);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await narrowReminderWindows(const []);
      expect(calls, isEmpty);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'x'),
      );
      await narrowReminderWindows(plan);
    });
  });
}
