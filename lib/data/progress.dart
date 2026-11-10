import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'league.dart';
import 'quests.dart';

const maxHearts = 5;
const heartRefill = Duration(minutes: 30);

/// Daily counters older than this are dropped when saving.
const _keepDays = 8;

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Progress {
  const Progress({
    this.onboarded = false,
    this.dailyGoal = 20,
    this.totalXp = 0,
    this.streak = 0,
    this.lastActiveDay,
    this.xpByDay = const {},
    this.hearts = maxHearts,
    this.heartsSinceMs = 0,
    this.completed = const {},
    this.lessonsDone = 0,
    this.correct = 0,
    this.answered = 0,
    this.counters = const {},
    this.claimed = const [],
    this.leagueTier = 0,
    this.leagueWeek,
    this.leagueResult,
    this.remindersEnabled,
    this.reminderMinutes = 19 * 60,
    this.heartAlerts = true,
  });

  final bool onboarded;
  final int dailyGoal;
  final int totalXp;
  final int streak;
  final String? lastActiveDay;

  /// All XP earned per day (lessons, chests and quest rewards).
  final Map<String, int> xpByDay;

  /// Stored heart count; the real count also depends on time passed
  /// since [heartsSinceMs] (see [heartsAt]).
  final int hearts;
  final int heartsSinceMs;

  /// Node id -> times completed.
  final Map<String, int> completed;
  final int lessonsDone;
  final int correct;
  final int answered;

  /// Daily quest counters, keyed "yyyy-mm-dd:metric".
  final Map<String, int> counters;

  /// Claimed quests, as "yyyy-mm-dd:questId".
  final List<String> claimed;

  /// Index into [leagueTiers].
  final int leagueTier;

  /// Week (Monday's dayKey) the current tier is competing in.
  final String? leagueWeek;

  /// Outcome of the last finished week, shown once then cleared.
  final LeagueResult? leagueResult;

  /// Daily reminder on/off; null until the user has been asked.
  final bool? remindersEnabled;

  /// Reminder time as minutes after midnight.
  final int reminderMinutes;

  /// Notify when all hearts have refilled.
  final bool heartAlerts;

  int heartsAt(DateTime now) {
    if (hearts >= maxHearts) return maxHearts;
    final passed = now.millisecondsSinceEpoch - heartsSinceMs;
    return min(maxHearts, hearts + passed ~/ heartRefill.inMilliseconds);
  }

  /// Time until the next heart, or null when full.
  Duration? nextHeartIn(DateTime now) {
    if (heartsAt(now) >= maxHearts) return null;
    final passed = now.millisecondsSinceEpoch - heartsSinceMs;
    final ms = heartRefill.inMilliseconds - passed % heartRefill.inMilliseconds;
    return Duration(milliseconds: ms);
  }

  /// Streak as shown today: it is lost once a whole day is skipped.
  int streakAt(DateTime now) {
    final today = dayKey(now);
    final yesterday = dayKey(now.subtract(const Duration(days: 1)));
    return (lastActiveDay == today || lastActiveDay == yesterday) ? streak : 0;
  }

  int xpOn(DateTime day) => xpByDay[dayKey(day)] ?? 0;

  /// XP earned in the league week starting on [weekStart].
  int weekXp(DateTime weekStart) {
    var sum = 0;
    for (var i = 0; i < 7; i++) {
      sum += xpOn(weekStart.add(Duration(days: i)));
    }
    return sum;
  }

  int counter(DateTime day, QuestMetric metric) =>
      counters['${dayKey(day)}:${metric.name}'] ?? 0;

  bool isClaimed(DateTime day, String questId) =>
      claimed.contains('${dayKey(day)}:$questId');

  bool isDone(String nodeId) => (completed[nodeId] ?? 0) > 0;

  Progress copyWith({
    bool? onboarded,
    int? dailyGoal,
    int? totalXp,
    int? streak,
    String? lastActiveDay,
    Map<String, int>? xpByDay,
    int? hearts,
    int? heartsSinceMs,
    Map<String, int>? completed,
    int? lessonsDone,
    int? correct,
    int? answered,
    Map<String, int>? counters,
    List<String>? claimed,
    int? leagueTier,
    String? leagueWeek,
    LeagueResult? leagueResult,
    bool clearLeagueResult = false,
    bool? remindersEnabled,
    int? reminderMinutes,
    bool? heartAlerts,
  }) =>
      Progress(
        onboarded: onboarded ?? this.onboarded,
        dailyGoal: dailyGoal ?? this.dailyGoal,
        totalXp: totalXp ?? this.totalXp,
        streak: streak ?? this.streak,
        lastActiveDay: lastActiveDay ?? this.lastActiveDay,
        xpByDay: xpByDay ?? this.xpByDay,
        hearts: hearts ?? this.hearts,
        heartsSinceMs: heartsSinceMs ?? this.heartsSinceMs,
        completed: completed ?? this.completed,
        lessonsDone: lessonsDone ?? this.lessonsDone,
        correct: correct ?? this.correct,
        answered: answered ?? this.answered,
        counters: counters ?? this.counters,
        claimed: claimed ?? this.claimed,
        leagueTier: leagueTier ?? this.leagueTier,
        leagueWeek: leagueWeek ?? this.leagueWeek,
        leagueResult: clearLeagueResult ? null : (leagueResult ?? this.leagueResult),
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
        reminderMinutes: reminderMinutes ?? this.reminderMinutes,
        heartAlerts: heartAlerts ?? this.heartAlerts,
      );

  Map<String, dynamic> toJson() => {
        'onboarded': onboarded,
        'dailyGoal': dailyGoal,
        'totalXp': totalXp,
        'streak': streak,
        'lastActiveDay': lastActiveDay,
        'xpByDay': xpByDay,
        'hearts': hearts,
        'heartsSinceMs': heartsSinceMs,
        'completed': completed,
        'lessonsDone': lessonsDone,
        'correct': correct,
        'answered': answered,
        'counters': counters,
        'claimed': claimed,
        'leagueTier': leagueTier,
        'leagueWeek': leagueWeek,
        'leagueResult': leagueResult?.toJson(),
        'remindersEnabled': remindersEnabled,
        'reminderMinutes': reminderMinutes,
        'heartAlerts': heartAlerts,
      };

  factory Progress.fromJson(Map<String, dynamic> j) => Progress(
        onboarded: j['onboarded'] as bool? ?? false,
        dailyGoal: j['dailyGoal'] as int? ?? 20,
        totalXp: j['totalXp'] as int? ?? 0,
        streak: j['streak'] as int? ?? 0,
        lastActiveDay: j['lastActiveDay'] as String?,
        xpByDay: (j['xpByDay'] as Map?)?.cast<String, int>() ?? const {},
        hearts: j['hearts'] as int? ?? maxHearts,
        heartsSinceMs: j['heartsSinceMs'] as int? ?? 0,
        completed: (j['completed'] as Map?)?.cast<String, int>() ?? const {},
        lessonsDone: j['lessonsDone'] as int? ?? 0,
        correct: j['correct'] as int? ?? 0,
        answered: j['answered'] as int? ?? 0,
        counters: (j['counters'] as Map?)?.cast<String, int>() ?? const {},
        claimed: (j['claimed'] as List?)?.cast<String>() ?? const [],
        leagueTier: j['leagueTier'] as int? ?? 0,
        leagueWeek: j['leagueWeek'] as String?,
        leagueResult: j['leagueResult'] == null
            ? null
            : LeagueResult.fromJson(j['leagueResult'] as Map<String, dynamic>),
        remindersEnabled: j['remindersEnabled'] as bool?,
        reminderMinutes: j['reminderMinutes'] as int? ?? 19 * 60,
        heartAlerts: j['heartAlerts'] as bool? ?? true,
      );
}

/// Result of finishing a lesson, used by the result screen.
class LessonReward {
  const LessonReward({
    required this.xp,
    required this.streak,
    required this.streakExtended,
    required this.todayXp,
    required this.dailyGoal,
    this.questsCompleted = const [],
  });
  final int xp;
  final int streak;
  final bool streakExtended;
  final int todayXp;
  final int dailyGoal;

  /// Daily quests that became complete with this lesson.
  final List<QuestDef> questsCompleted;
}

final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('prefsProvider must be overridden'),
);

/// Injectable clock so tests can control time.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class ProgressNotifier extends Notifier<Progress> {
  static const _key = 'progress_v1';

  SharedPreferences get _prefs => ref.read(prefsProvider);
  DateTime _now() => ref.read(clockProvider)();

  @override
  Progress build() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const Progress();
    try {
      return Progress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const Progress();
    }
  }

  void _save(Progress p) {
    // Drop quest data for days that can no longer matter.
    final oldest = dayKey(_now().subtract(const Duration(days: _keepDays)));
    bool recent(String key) => key.substring(0, 10).compareTo(oldest) >= 0;
    final pruned = p.copyWith(
      counters: {
        for (final e in p.counters.entries)
          if (recent(e.key)) e.key: e.value,
      },
      claimed: [for (final c in p.claimed) if (recent(c)) c],
    );
    state = pruned;
    _prefs.setString(_key, jsonEncode(pruned.toJson()));
  }

  void finishOnboarding(int dailyGoal) =>
      _save(state.copyWith(onboarded: true, dailyGoal: dailyGoal));

  void setDailyGoal(int goal) => _save(state.copyWith(dailyGoal: goal));

  /// Removes one heart; returns how many are left.
  int loseHeart() {
    final now = _now();
    final current = state.heartsAt(now);
    if (current <= 0) return 0;
    // Keep the refill timer running if it already was; start it otherwise.
    final since = current >= maxHearts
        ? now.millisecondsSinceEpoch
        : state.heartsSinceMs +
            (current - state.hearts) * heartRefill.inMilliseconds;
    _save(state.copyWith(hearts: current - 1, heartsSinceMs: since));
    return current - 1;
  }

  /// Records a finished lesson or chest. [stats] counts correct answers per
  /// quest metric (e.g. listening exercises) for daily quests.
  LessonReward completeNode(
    String nodeId, {
    required int xp,
    int correct = 0,
    int answered = 0,
    bool perfect = false,
    Map<QuestMetric, int> stats = const {},
  }) {
    final now = _now();
    final today = dayKey(now);
    final shownStreak = state.streakAt(now);
    final alreadyToday = state.lastActiveDay == today;
    final newStreak = alreadyToday ? shownStreak : shownStreak + 1;
    final todayXp = (state.xpByDay[today] ?? 0) + xp;
    final isLesson = answered > 0;

    final before = state;
    final counters = {...state.counters};
    void bump(QuestMetric m, int by) {
      if (by <= 0) return;
      final k = '$today:${m.name}';
      counters[k] = (counters[k] ?? 0) + by;
    }

    bump(QuestMetric.xp, xp);
    if (isLesson) bump(QuestMetric.lessons, 1);
    if (isLesson && perfect) bump(QuestMetric.perfectLessons, 1);
    stats.forEach(bump);

    _save(state.copyWith(
      totalXp: state.totalXp + xp,
      streak: newStreak,
      lastActiveDay: today,
      xpByDay: {...state.xpByDay, today: todayXp},
      completed: {...state.completed, nodeId: (state.completed[nodeId] ?? 0) + 1},
      lessonsDone: state.lessonsDone + (isLesson ? 1 : 0),
      correct: state.correct + correct,
      answered: state.answered + answered,
      counters: counters,
    ));

    final quests = questsForDay(now);
    return LessonReward(
      xp: xp,
      streak: newStreak,
      streakExtended: !alreadyToday,
      todayXp: todayXp,
      dailyGoal: state.dailyGoal,
      questsCompleted: [
        for (final q in quests)
          if (!q.isComplete(before, now) && q.isComplete(state, now)) q,
      ],
    );
  }

  /// Claims a completed daily quest's reward. Returns false if it is not
  /// complete or was already claimed.
  bool claimQuest(QuestDef quest) {
    final now = _now();
    if (!quest.isComplete(state, now) || state.isClaimed(now, quest.id)) return false;
    final today = dayKey(now);
    _save(state.copyWith(
      totalXp: state.totalXp + quest.rewardXp,
      xpByDay: {...state.xpByDay, today: (state.xpByDay[today] ?? 0) + quest.rewardXp},
      claimed: [...state.claimed, '$today:${quest.id}'],
    ));
    return true;
  }

  /// Closes a finished league week: moves the user up or down a tier and
  /// stores the result to show. Safe to call any time.
  void settleLeague() {
    final now = _now();
    final current = dayKey(weekStart(now));
    final week = state.leagueWeek;
    if (week == current) return;
    if (week == null) {
      _save(state.copyWith(leagueWeek: current));
      return;
    }
    final start = DateTime.parse(week);
    final result = finishWeek(
      tier: state.leagueTier,
      weekStart: start,
      userXp: state.weekXp(start),
    );
    _save(state.copyWith(
      leagueTier: result.newTier,
      leagueWeek: current,
      leagueResult: result,
    ));
  }

  void setReminders({bool? enabled, int? minutes, bool? heartAlerts}) => _save(state.copyWith(
        remindersEnabled: enabled,
        reminderMinutes: minutes,
        heartAlerts: heartAlerts,
      ));

  void dismissLeagueResult() => _save(state.copyWith(clearLeagueResult: true));

  void reset() => _save(const Progress(onboarded: true));
}

final progressProvider =
    NotifierProvider<ProgressNotifier, Progress>(ProgressNotifier.new);
