import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/tr_errors.dart';
import '../study/tr_error_log.dart';
import '../models/notes.dart';
import '../goals/learn_goal.dart';
import '../models/study_plan.dart';
import '../services/billing/premium_perks.dart' show goldMultiplierProvider;

import 'catalog.dart';
import 'league.dart';
import 'quests.dart';
import 'review_grade.dart';
import 'wallet.dart';

export 'review_grade.dart' show ReviewGrade;

/// Most questions kept in the error notebook (oldest dropped first).
const maxMistakes = 300;

/// Days until a notebook question comes back, per stage: 1 → 3 → 7 → 21.
const mistakeIntervals = [1, 3, 7, 21];

/// Right answers in a row that take a question out of the notebook.
const mistakeClearRun = 2;

/// Wrong answers to the same question ("nodeId#index") that save it in the
/// error notebook ("Hatalarını çalış", Hata defteri). One slip is only asked again later in the
/// lesson; a question missed this often is kept for spaced review.
const mistakeSaveMisses = 3;

/// Most questions whose wrong answers are counted (oldest dropped first).
const maxMissCounts = 500;

/// Progress key of a unit's topic guide (see [Progress.guideSeen]).
String guideKey(String unitId) => 'guide_$unitId';

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
    this.mistakes = const [],
    this.trackId = defaultTrackId,
    this.examBest = const {},
    this.examSeconds = const {},
    this.wordBox = const {},
    this.wordDue = const {},
    this.diary = const {},
    this.errorStats = const {},
    this.customWords = const [],
    this.wordLast = const {},
    this.mistakeStage = const {},
    this.mistakeDue = const {},
    this.mistakeRun = const {},
    this.mistakeMisses = const {},
    this.studyPlan,
    this.readingWords = 0,
    this.mistakeReason = const {},
    this.mistakeNote = const {},
    this.userNotes = const [],
    this.removedWords = const {},
    this.wallet = const Wallet(),
    this.learnGoal,
  });

  /// Altın and Mağaza items (lib/data/wallet.dart).
  final Wallet wallet;

  /// "Hedefin ne?" (onboarding / Profil), null until chosen.
  final LearnGoal? learnGoal;

  /// Selected course or exam (see catalog.dart).
  final String trackId;

  /// Best mini mock exam score (percent) per exam id.
  final Map<String, int> examBest;

  /// Time (seconds) of the last finished mock exam per exam or mock node id.
  final Map<String, int> examSeconds;

  /// Whether the unit's topic guide was opened or its suggestion dismissed.
  bool guideSeen(String unitId) => isDone(guideKey(unitId));

  /// Spaced repetition box (0–5) per personal-dictionary word id.
  final Map<String, int> wordBox;

  /// Day key when each word is due again.
  final Map<String, String> wordDue;

  /// Day key each word was last reviewed (kept for a later FSRS scheduler).
  final Map<String, String> wordLast;

  /// Error notebook: stage (index into [mistakeIntervals]) per question.
  /// Missing for questions saved before the notebook had stages: stage 0.
  final Map<String, int> mistakeStage;

  /// Day each notebook question is due; missing means due now.
  final Map<String, String> mistakeDue;

  /// Right answers in a row per notebook question.
  final Map<String, int> mistakeRun;

  /// Wrong answers per question not (yet) in the notebook; at
  /// [mistakeSaveMisses] the question is saved and its count dropped.
  final Map<String, int> mistakeMisses;

  /// The daily study plan ("Bugün"); null until it is set up.
  final StudyPlan? studyPlan;

  /// Words read in reading texts, all time (the reading counter).
  final int readingWords;

  /// "Neden yanıldın?" per notebook question (a MistakeReason name).
  final Map<String, String> mistakeReason;

  /// The learner's own note on a notebook question (at most 140 letters).
  final Map<String, String> mistakeNote;

  /// The learner's own notes in "Notlarım", deleted ones as tombstones.
  final List<UserNote> userNotes;

  /// Notes to show: not deleted, last edited first.
  List<UserNote> get visibleNotes =>
      userNotes.where((n) => !n.deleted).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// Own words the learner deleted: lowercase English word → when (ms), so a
  /// deletion is not undone by an older copy on another device.
  final Map<String, int> removedWords;

  /// Notebook questions due on [day], oldest saved first.
  List<String> mistakesDue(String day) =>
      mistakes.where((k) => (mistakeDue[k] ?? '').compareTo(day) <= 0).toList();

  /// English diary: day key → text.
  final Map<String, String> diary;

  /// Türk hata dedektörü: how often each [TrErrorCategory] (by name) was
  /// found in the user's answers, diary and conversations.
  final Map<String, int> errorStats;

  /// Most frequent mistake categories, most frequent first.
  List<(TrErrorCategory, int)> topErrorCategories([int count = 3]) {
    final list = [
      for (final e in errorStats.entries)
        if (TrErrorCategory.byName(e.key) case final c? when e.value > 0) (c, e.value),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return list.take(count).toList();
  }

  /// Words the user added to the personal dictionary themselves (from
  /// reading or by hand), merged with assets/notes/words.json.
  final List<NoteWord> customWords;

  /// Exercises answered wrong, as "nodeId#index", oldest first.
  final List<String> mistakes;

  final bool onboarded;
  final int dailyGoal;
  final int totalXp;
  final int streak;
  final String? lastActiveDay;

  /// All XP earned per day (lessons, chests and quest rewards).
  final Map<String, int> xpByDay;

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

  /// Streak as shown today: it is lost once a whole day is skipped. With a
  /// study plan one missed day a week is forgiven (a streak freeze, used
  /// automatically): a habit is not broken by a single day.
  ///
  /// Streak freezes bought in the Mağaza bridge further missed days, one
  /// each (see [streakCover]).
  int streakAt(DateTime now) {
    final today = dayKey(now);
    final yesterday = dayKey(now.subtract(const Duration(days: 1)));
    if (lastActiveDay == today || lastActiveDay == yesterday) return streak;
    return streakCover(now) != null ? streak : 0;
  }

  /// Days missed since [lastActiveDay] (0 when active today or yesterday);
  /// null before the first lesson.
  int? missedDays(DateTime now) {
    final last = lastActiveDay;
    if (last == null) return null;
    final l = DateTime.parse(last);
    final days = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime.utc(l.year, l.month, l.day)).inDays;
    return max(0, days - 1);
  }

  /// How the missed days are bridged: the study plan's weekly freeze (one
  /// day) and bought freezes (one day each). Null when they are not enough
  /// (the streak is lost) or there was never a streak.
  ({bool plan, int bought})? streakCover(DateTime now) {
    final missed = missedDays(now);
    if (missed == null || streak <= 0) return null;
    if (missed == 0) return (plan: false, bought: 0);
    final plan = studyPlan;
    final planFree =
        plan != null && plan.freezeWeek != dayKey(weekStart(now.subtract(const Duration(days: 1))));
    final need = missed - (planFree ? 1 : 0);
    if (need > wallet.freezes) return null;
    return (plan: planFree, bought: need);
  }

  /// Whether a streak freeze bridges yesterday, missed after studying the
  /// day before (one per week, plan users only).
  bool freezeCovers(DateTime now) {
    final plan = studyPlan;
    if (plan == null) return false;
    final missed = now.subtract(const Duration(days: 1));
    if (lastActiveDay != dayKey(now.subtract(const Duration(days: 2)))) return false;
    final week = dayKey(weekStart(missed));
    return plan.freezeWeek != week;
  }

  /// Reading words read on [day].
  int readingWordsOn(String day) => counters['$day:readingWords'] ?? 0;

  int xpOn(DateTime day) => xpByDay[dayKey(day)] ?? 0;

  /// XP earned in the league week starting on [weekStart].
  int weekXp(DateTime weekStart) {
    var sum = 0;
    for (var i = 0; i < 7; i++) {
      sum += xpOn(weekStart.add(Duration(days: i)));
    }
    return sum;
  }

  int counter(DateTime day, QuestMetric metric) => counters['${dayKey(day)}:${metric.name}'] ?? 0;

  bool isClaimed(DateTime day, String questId) => claimed.contains('${dayKey(day)}:$questId');

  bool isDone(String nodeId) => (completed[nodeId] ?? 0) > 0;

  Progress copyWith({
    bool? onboarded,
    int? dailyGoal,
    int? totalXp,
    int? streak,
    String? lastActiveDay,
    Map<String, int>? xpByDay,
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
    List<String>? mistakes,
    String? trackId,
    Map<String, int>? examBest,
    Map<String, int>? examSeconds,
    Map<String, int>? wordBox,
    Map<String, String>? wordDue,
    Map<String, String>? diary,
    Map<String, int>? errorStats,
    List<NoteWord>? customWords,
    Map<String, String>? wordLast,
    Map<String, int>? mistakeStage,
    Map<String, String>? mistakeDue,
    Map<String, int>? mistakeRun,
    Map<String, int>? mistakeMisses,
    StudyPlan? studyPlan,
    bool clearStudyPlan = false,
    int? readingWords,
    Map<String, String>? mistakeReason,
    Map<String, String>? mistakeNote,
    List<UserNote>? userNotes,
    Map<String, int>? removedWords,
    Wallet? wallet,
    LearnGoal? learnGoal,
  }) => Progress(
    onboarded: onboarded ?? this.onboarded,
    dailyGoal: dailyGoal ?? this.dailyGoal,
    totalXp: totalXp ?? this.totalXp,
    streak: streak ?? this.streak,
    lastActiveDay: lastActiveDay ?? this.lastActiveDay,
    xpByDay: xpByDay ?? this.xpByDay,
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
    mistakes: mistakes ?? this.mistakes,
    trackId: trackId ?? this.trackId,
    examBest: examBest ?? this.examBest,
    examSeconds: examSeconds ?? this.examSeconds,
    wordBox: wordBox ?? this.wordBox,
    wordDue: wordDue ?? this.wordDue,
    diary: diary ?? this.diary,
    errorStats: errorStats ?? this.errorStats,
    customWords: customWords ?? this.customWords,
    wordLast: wordLast ?? this.wordLast,
    mistakeStage: mistakeStage ?? this.mistakeStage,
    mistakeDue: mistakeDue ?? this.mistakeDue,
    mistakeRun: mistakeRun ?? this.mistakeRun,
    mistakeMisses: mistakeMisses ?? this.mistakeMisses,
    studyPlan: clearStudyPlan ? null : (studyPlan ?? this.studyPlan),
    readingWords: readingWords ?? this.readingWords,
    mistakeReason: mistakeReason ?? this.mistakeReason,
    mistakeNote: mistakeNote ?? this.mistakeNote,
    userNotes: userNotes ?? this.userNotes,
    removedWords: removedWords ?? this.removedWords,
    wallet: wallet ?? this.wallet,
    learnGoal: learnGoal ?? this.learnGoal,
  );

  Map<String, dynamic> toJson() => {
    'onboarded': onboarded,
    'dailyGoal': dailyGoal,
    'totalXp': totalXp,
    'streak': streak,
    'lastActiveDay': lastActiveDay,
    'xpByDay': xpByDay,
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
    'mistakes': mistakes,
    'trackId': trackId,
    'examBest': examBest,
    'examSeconds': examSeconds,
    'wordBox': wordBox,
    'wordDue': wordDue,
    'diary': diary,
    'errorStats': errorStats,
    'customWords': [for (final w in customWords) w.toJson()],
    'wordLast': wordLast,
    'mistakeStage': mistakeStage,
    'mistakeDue': mistakeDue,
    'mistakeRun': mistakeRun,
    'mistakeMisses': mistakeMisses,
    'studyPlan': studyPlan?.toJson(),
    'readingWords': readingWords,
    'mistakeReason': mistakeReason,
    'mistakeNote': mistakeNote,
    'userNotes': [for (final n in userNotes) n.toJson()],
    'removedWords': removedWords,
    'wallet': wallet.toJson(),
    'learnGoal': ?learnGoal?.toJson(),
  };

  factory Progress.fromJson(Map<String, dynamic> j) => Progress(
    onboarded: j['onboarded'] as bool? ?? false,
    dailyGoal: j['dailyGoal'] as int? ?? 20,
    totalXp: j['totalXp'] as int? ?? 0,
    streak: j['streak'] as int? ?? 0,
    lastActiveDay: j['lastActiveDay'] as String?,
    xpByDay: (j['xpByDay'] as Map?)?.cast<String, int>() ?? const {},
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
    mistakes: (j['mistakes'] as List?)?.cast<String>() ?? const [],
    trackId: j['trackId'] as String? ?? defaultTrackId,
    examBest: (j['examBest'] as Map?)?.cast<String, int>() ?? const {},
    examSeconds: (j['examSeconds'] as Map?)?.cast<String, int>() ?? const {},
    wordBox: (j['wordBox'] as Map?)?.cast<String, int>() ?? const {},
    wordDue: (j['wordDue'] as Map?)?.cast<String, String>() ?? const {},
    diary: (j['diary'] as Map?)?.cast<String, String>() ?? const {},
    errorStats: (j['errorStats'] as Map?)?.cast<String, int>() ?? const {},
    customWords: [
      for (final w in (j['customWords'] as List?) ?? const []) NoteWord.fromJson(w as Map<String, dynamic>),
    ],
    wordLast: (j['wordLast'] as Map?)?.cast<String, String>() ?? const {},
    mistakeStage: (j['mistakeStage'] as Map?)?.cast<String, int>() ?? const {},
    mistakeDue: (j['mistakeDue'] as Map?)?.cast<String, String>() ?? const {},
    mistakeRun: (j['mistakeRun'] as Map?)?.cast<String, int>() ?? const {},
    mistakeMisses: (j['mistakeMisses'] as Map?)?.cast<String, int>() ?? const {},
    studyPlan: j['studyPlan'] == null ? null : StudyPlan.fromJson(j['studyPlan'] as Map<String, dynamic>),
    readingWords: j['readingWords'] as int? ?? 0,
    mistakeReason: (j['mistakeReason'] as Map?)?.cast<String, String>() ?? const {},
    mistakeNote: (j['mistakeNote'] as Map?)?.cast<String, String>() ?? const {},
    userNotes: [
      for (final n in (j['userNotes'] as List?) ?? const []) UserNote.fromJson(n as Map<String, dynamic>),
    ],
    removedWords: {
      for (final e in ((j['removedWords'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toInt(),
    },
    wallet: j['wallet'] is Map
        ? Wallet.fromJson(Map<String, dynamic>.from(j['wallet'] as Map))
        : const Wallet(),
    learnGoal: j['learnGoal'] is Map
        ? LearnGoal.fromJson(Map<String, dynamic>.from(j['learnGoal'] as Map))
        : null,
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
    this.questProgress = const [],
    this.gold = const [],
    this.freezesUsed = 0,
  });
  final int xp;

  /// Gold earned with this lesson, by reason (lesson, perfect, daily goal,
  /// streak milestone), in that order.
  final List<(GoldReason, int)> gold;

  /// Total of [gold].
  int get goldTotal => gold.fold(0, (a, g) => a + g.$2);

  /// Bought streak freezes used up to keep the streak.
  final int freezesUsed;
  final int streak;
  final bool streakExtended;
  final int todayXp;
  final int dailyGoal;

  /// Daily quests that became complete with this lesson.
  final List<QuestDef> questsCompleted;

  /// Today's quests with their progress before and after this lesson.
  final List<QuestStep> questProgress;

  /// XP earned today before this lesson.
  int get todayXpBefore => (todayXp - xp).clamp(0, todayXp);
}

/// One daily quest's progress across a lesson (for the celebration chain).
class QuestStep {
  const QuestStep({required this.quest, required this.before, required this.after});
  final QuestDef quest;
  final int before;
  final int after;

  bool get moved => after > before;
  bool get completedNow => after >= quest.target && before < quest.target;
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

  /// This install's id in the wallet counters.
  String get device => walletDevice(_prefs);

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
      claimed: [
        for (final c in p.claimed)
          if (recent(c)) c,
      ],
    );
    state = pruned;
    _prefs.setString(_key, jsonEncode(pruned.toJson()));
  }

  void finishOnboarding(int dailyGoal) => _save(state.copyWith(onboarded: true, dailyGoal: dailyGoal));

  void setDailyGoal(int goal) => _save(state.copyWith(dailyGoal: goal));

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
    // Freezes bridged missed days: use them up (the plan's for that week).
    final cover = alreadyToday ? null : state.streakCover(now);
    final freeze = cover != null && cover.plan
        ? state.studyPlan!.copyWith(freezeWeek: dayKey(weekStart(now.subtract(const Duration(days: 1)))))
        : null;
    final freezesUsed = cover?.bought ?? 0;
    final newStreak = alreadyToday ? shownStreak : shownStreak + 1;
    final todayXp = (state.xpByDay[today] ?? 0) + xp;
    final isLesson = answered > 0;

    // Altın: the lesson, a perfect run, the daily goal, a streak milestone.
    var wallet = state.wallet.pruned(today).useFreezes(device, freezesUsed);
    final gold = <(GoldReason, int)>[];
    final once = {...wallet.once};
    void give(GoldReason reason, int amount, [String? onceKey]) {
      if (amount <= 0) return;
      if (onceKey != null) {
        if (once.containsKey(onceKey)) return;
        once[onceKey] = today;
      }
      gold.add((reason, amount));
    }

    if (isLesson) give(GoldReason.lesson, goldPerLesson);
    if (isLesson && perfect) give(GoldReason.perfect, goldPerfectBonus);
    final goalBefore = state.xpByDay[today] ?? 0;
    if (goalBefore < state.dailyGoal && todayXp >= state.dailyGoal) {
      give(GoldReason.dailyGoal, goldDailyGoal, 'goal:$today');
    }
    if (!alreadyToday && goldStreakMilestones[newStreak] != null) {
      final start = dayKey(now.subtract(Duration(days: newStreak - 1)));
      give(GoldReason.streak, goldStreakMilestones[newStreak]!, 'streak:$newStreak:$start');
    }
    // Premium: the same again (one entry, so the result screen can say so).
    final base = gold.fold(0, (a, g) => a + g.$2);
    final bonus = base * (ref.read(goldMultiplierProvider) - 1);
    if (bonus > 0) gold.add((GoldReason.premium, bonus));
    wallet = wallet.copyWith(once: once).credit(device, base + bonus);

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

    _save(
      state.copyWith(
        totalXp: state.totalXp + xp,
        streak: newStreak,
        lastActiveDay: today,
        xpByDay: {...state.xpByDay, today: todayXp},
        completed: {...state.completed, nodeId: (state.completed[nodeId] ?? 0) + 1},
        lessonsDone: state.lessonsDone + (isLesson ? 1 : 0),
        studyPlan: freeze,
        correct: state.correct + correct,
        answered: state.answered + answered,
        counters: counters,
        wallet: wallet,
      ),
    );

    final quests = questsForDay(now);
    return LessonReward(
      xp: xp,
      streak: newStreak,
      streakExtended: !alreadyToday,
      todayXp: todayXp,
      dailyGoal: state.dailyGoal,
      gold: gold,
      freezesUsed: freezesUsed,
      questsCompleted: [
        for (final q in quests)
          if (!q.isComplete(before, now) && q.isComplete(state, now)) q,
      ],
      questProgress: [
        for (final q in quests)
          QuestStep(quest: q, before: q.progressOf(before, now), after: q.progressOf(state, now)),
      ],
    );
  }

  /// Claims a completed daily quest's reward. Returns false if it is not
  /// complete or was already claimed.
  bool claimQuest(QuestDef quest) {
    final now = _now();
    if (!quest.isComplete(state, now) || state.isClaimed(now, quest.id)) return false;
    final today = dayKey(now);
    _save(
      state.copyWith(
        totalXp: state.totalXp + quest.rewardXp,
        xpByDay: {...state.xpByDay, today: (state.xpByDay[today] ?? 0) + quest.rewardXp},
        claimed: [...state.claimed, '$today:${quest.id}'],
        wallet: state.wallet.credit(device, quest.rewardGold * ref.read(goldMultiplierProvider)),
      ),
    );
    return true;
  }

  /// Closes a finished league week: moves the user up or down a tier and
  /// stores the result to show. Safe to call any time.
  ///
  /// With [quiet] (the learner plays in the Dünya Ligi, whose server decides
  /// the tier) only the week moves on; no simulated result is made.
  void settleLeague({bool quiet = false}) {
    final now = _now();
    final current = dayKey(weekStart(now));
    final week = state.leagueWeek;
    if (week == current) return;
    if (week == null || quiet) {
      _save(state.copyWith(leagueWeek: current));
      return;
    }
    final start = DateTime.parse(week);
    final userXp = state.weekXp(start);
    final result = finishWeek(tier: state.leagueTier, weekStart: start, userXp: userXp);
    final gold = goldForLeague(
      promoted: result.promoted,
      demoted: result.demoted,
      rank: result.rank,
      xp: userXp,
    );
    final key = 'league:$week';
    final wallet = gold > 0 && !state.wallet.once.containsKey(key)
        ? state.wallet
              .copyWith(once: {...state.wallet.once, key: dayKey(now)})
              .credit(device, gold * ref.read(goldMultiplierProvider))
        : state.wallet;
    _save(
      state.copyWith(leagueTier: result.newTier, leagueWeek: current, leagueResult: result, wallet: wallet),
    );
  }

  void setReminders({bool? enabled, int? minutes}) =>
      _save(state.copyWith(remindersEnabled: enabled, reminderMinutes: minutes));

  /// Puts a question the user got wrong into the error notebook. It comes
  /// back after a day; a question already there starts its run of right
  /// answers again but keeps its stage.
  void addMistake(String key) {
    var list = [...state.mistakes.where((k) => k != key), key];
    final dropped = list.length > maxMistakes ? list.sublist(0, list.length - maxMistakes) : const <String>[];
    if (dropped.isNotEmpty) list = list.sublist(dropped.length);
    final due = dayKey(_now().add(Duration(days: mistakeIntervals.first)));
    _save(
      state.copyWith(
        mistakes: list,
        mistakeStage: {..._without(state.mistakeStage, dropped), key: state.mistakeStage[key] ?? 0},
        mistakeDue: {..._without(state.mistakeDue, dropped), key: due},
        mistakeRun: {..._without(state.mistakeRun, dropped), key: 0},
      ),
    );
  }

  /// A question answered wrong in a lesson or review. A question already in
  /// the notebook goes back to its start ([addMistake]); any other one is
  /// counted and saved at its [mistakeSaveMisses]th wrong answer, so a single
  /// slip does not fill the notebook. Returns whether it is in the notebook.
  bool recordWrong(String key) {
    if (state.mistakes.contains(key)) {
      addMistake(key);
      return true;
    }
    final misses = (state.mistakeMisses[key] ?? 0) + 1;
    if (misses >= mistakeSaveMisses) {
      _save(state.copyWith(mistakeMisses: _without(state.mistakeMisses, [key])));
      addMistake(key);
      return true;
    }
    // Re-inserted last, so the oldest counts are the ones dropped.
    var counts = {
      ..._without(state.mistakeMisses, [key]),
      key: misses,
    };
    if (counts.length > maxMissCounts) {
      counts = Map.fromEntries(counts.entries.skip(counts.length - maxMissCounts));
    }
    _save(state.copyWith(mistakeMisses: counts));
    return false;
  }

  /// A notebook question answered right: the first right answer moves it to
  /// the next interval (1 → 3 → 7 → 21 days), [mistakeClearRun] in a row
  /// take it out of the notebook.
  void answerMistakeRight(String key) {
    if (!state.mistakes.contains(key)) return;
    final run = (state.mistakeRun[key] ?? 0) + 1;
    if (run >= mistakeClearRun) {
      clearMistake(key);
      return;
    }
    final stage = min((state.mistakeStage[key] ?? 0) + 1, mistakeIntervals.length - 1);
    _save(
      state.copyWith(
        mistakeStage: {...state.mistakeStage, key: stage},
        mistakeDue: {
          ...state.mistakeDue,
          key: dayKey(_now().add(Duration(days: mistakeIntervals[stage]))),
        },
        mistakeRun: {...state.mistakeRun, key: run},
      ),
    );
  }

  /// Takes a question out of the notebook.
  void clearMistake(String key) {
    if (!state.mistakes.contains(key)) return;
    _save(
      state.copyWith(
        mistakes: state.mistakes.where((k) => k != key).toList(),
        mistakeStage: _without(state.mistakeStage, [key]),
        mistakeDue: _without(state.mistakeDue, [key]),
        mistakeRun: _without(state.mistakeRun, [key]),
        mistakeReason: _without(state.mistakeReason, [key]),
        mistakeNote: _without(state.mistakeNote, [key]),
      ),
    );
  }

  /// Tags a notebook question with why it went wrong, and the learner's
  /// own note (cut to 140 letters; empty removes it).
  void tagMistake(String key, {String? reason, String? note}) {
    if (!state.mistakes.contains(key)) return;
    final notes = {...state.mistakeNote};
    if (note != null) {
      final n = note.trim();
      n.isEmpty ? notes.remove(key) : notes[key] = n.length > 140 ? n.substring(0, 140) : n;
    }
    _save(
      state.copyWith(
        mistakeReason: reason == null ? null : {...state.mistakeReason, key: reason},
        mistakeNote: notes,
      ),
    );
  }

  /// Brings a notebook question back after [days] (e.g. "İki şık arasında
  /// kaldım": see it again in 3 days).
  void postponeMistake(String key, int days) {
    if (!state.mistakes.contains(key)) return;
    _save(
      state.copyWith(
        mistakeDue: {
          ...state.mistakeDue,
          key: dayKey(_now().add(Duration(days: days))),
        },
      ),
    );
  }

  /// Puts word cards into today's review (box 0), unless already learning.
  /// Returns how many were added.
  int queueWords(Iterable<String> ids) {
    final add = [
      for (final id in ids)
        if (!state.wordBox.containsKey(id)) id,
    ];
    if (add.isEmpty) return 0;
    final today = dayKey(_now());
    _save(
      state.copyWith(
        wordBox: {...state.wordBox, for (final id in add) id: 0},
        wordDue: {...state.wordDue, for (final id in add) id: today},
      ),
    );
    return add.length;
  }

  static Map<String, V> _without<V>(Map<String, V> map, List<String> keys) =>
      keys.isEmpty ? map : ({...map}..removeWhere((k, _) => keys.contains(k)));

  void setTrack(String id) => _save(state.copyWith(trackId: id));

  /// Sets the learner's goal ("Hedefin ne?").
  void setLearnGoal(LearnGoal goal) => _save(state.copyWith(learnGoal: goal));

  /// Sets up or changes the study plan; null removes it.
  void setStudyPlan(StudyPlan? plan) =>
      _save(plan == null ? state.copyWith(clearStudyPlan: true) : state.copyWith(studyPlan: plan));

  /// Counts words read in a reading text (today and all time).
  void addReading(int words) {
    if (words <= 0) return;
    final k = '${dayKey(_now())}:readingWords';
    _save(
      state.copyWith(
        readingWords: state.readingWords + words,
        counters: {...state.counters, k: (state.counters[k] ?? 0) + words},
      ),
    );
  }

  /// Marks nodes as already known (e.g. after the placement test) so the
  /// path starts further on. No XP, streak or lesson counts are given.
  void markKnown(Iterable<String> nodeIds) {
    final completed = {...state.completed};
    for (final id in nodeIds) {
      if ((completed[id] ?? 0) == 0) completed[id] = 1;
    }
    _save(state.copyWith(completed: completed));
  }

  /// Keeps the best mock exam score for [examId].
  void recordExam(String examId, int percent) {
    if (percent > (state.examBest[examId] ?? -1)) {
      _save(state.copyWith(examBest: {...state.examBest, examId: percent}));
    }
  }

  /// Records a finished mock exam: the best score and this attempt's time.
  void recordMock(String id, int percent, Duration time) {
    _save(
      state.copyWith(
        examBest: {...state.examBest, id: max(percent, state.examBest[id] ?? -1)},
        examSeconds: {...state.examSeconds, id: time.inSeconds},
      ),
    );
  }

  /// Remembers that the unit's guide was offered, so it is suggested once.
  void markGuideSeen(String unitId) {
    if (state.guideSeen(unitId)) return;
    _save(state.copyWith(completed: {...state.completed, guideKey(unitId): 1}));
  }

  /// Moves a word up a box when known, two boxes down when not (a forgotten
  /// word does not start from zero). A word in box 0 is due again today.
  /// [weakSpelling]: known, but typed with a small spelling slip. The word
  /// stays in its box and comes back tomorrow to practise the spelling.
  void reviewWord(String id, {required bool known, bool weakSpelling = false}) {
    final now = _now();
    final old = state.wordBox[id] ?? 0;
    final box = known ? (weakSpelling ? old : min(old + 1, reviewIntervals.length - 1)) : max(0, old - 2);
    final due = dayKey(
      now.add(Duration(days: weakSpelling && known ? reviewIntervals[1] : reviewIntervals[box])),
    );
    _save(
      state.copyWith(
        wordBox: {...state.wordBox, id: box},
        wordDue: {...state.wordDue, id: due},
        wordLast: {...state.wordLast, id: dayKey(now)},
      ),
    );
  }

  /// Reviews a path word card; a card seen for the first time counts as a
  /// new word of the day (counter "day:newWords").
  void learnWord(String id, {required bool known}) =>
      gradeWord(id, known ? ReviewGrade.good : ReviewGrade.again, countNew: true);

  /// Grades a flipped review card ("Bilmiyordum / Zor / Bildim / Kolay",
  /// see [scheduleReview]). With [countNew], a card seen for the first time
  /// counts as a new word of the day.
  void gradeWord(String id, ReviewGrade grade, {bool countNew = false}) {
    final fresh = !state.wordBox.containsKey(id);
    final now = _now();
    final next = scheduleReview(state.wordBox[id], grade);
    _save(
      state.copyWith(
        wordBox: {...state.wordBox, id: next.box},
        wordDue: {
          ...state.wordDue,
          id: dayKey(now.add(Duration(days: next.days))),
        },
        wordLast: {...state.wordLast, id: dayKey(now)},
      ),
    );
    if (!fresh || !countNew) return;
    final k = '${dayKey(_now())}:newWords';
    _save(state.copyWith(counters: {...state.counters, k: (state.counters[k] ?? 0) + 1}));
  }

  /// Sorts a new word in "Kelime keşfet": a known word skips ahead to the
  /// first "known" box and comes back in a week; a word to learn joins
  /// today's review queue.
  void triageWord(String id, {required bool known}) {
    final box = known ? 3 : 0;
    final due = dayKey(_now().add(Duration(days: reviewIntervals[box])));
    _save(state.copyWith(wordBox: {...state.wordBox, id: box}, wordDue: {...state.wordDue, id: due}));
  }

  void saveDiary(String day, String text) {
    final diary = {...state.diary};
    text.trim().isEmpty ? diary.remove(day) : diary[day] = text.trim();
    _save(state.copyWith(diary: diary));
  }

  /// Counts the categories of mistakes the hata dedektörü found, each
  /// category once per check, and keeps the check (with the learner's [text])
  /// in the on-device history the detailed error analysis reads.
  void recordTrErrors(Iterable<TrError> errors, {String? text}) {
    ref.read(trErrorLogProvider.notifier).record(errors, text: text);
    recordErrorCategories(errors.map((e) => e.category));
  }

  /// Counts error categories found elsewhere (AI writing feedback), each
  /// category once per check, like [recordTrErrors].
  void recordErrorCategories(Iterable<TrErrorCategory> categories) {
    final names = categories.map((c) => c.name).toSet();
    if (names.isEmpty) return;
    final stats = {...state.errorStats};
    for (final n in names) {
      stats[n] = (stats[n] ?? 0) + 1;
    }
    _save(state.copyWith(errorStats: stats));
  }

  /// Adds a word to the personal dictionary. Returns false if the user has
  /// already added the same English word. The word joins the next review.
  bool addCustomWord(NoteWord word) {
    final key = word.en.trim().toLowerCase();
    if (key.isEmpty || state.customWords.any((w) => w.en.toLowerCase() == key)) return false;
    final at = _now().millisecondsSinceEpoch;
    _save(
      state.copyWith(
        customWords: [
          ...state.customWords,
          word.copyWith(at: at),
        ],
        removedWords: {...state.removedWords}..remove(key),
      ),
    );
    return true;
  }

  /// Edits one of the learner's own words. The id (and so the review
  /// history) stays. Returns false if [en] is empty or another own word
  /// already has it.
  bool updateCustomWord(String id, {required String en, required String tr, String? example}) {
    final key = en.trim().toLowerCase();
    if (key.isEmpty || tr.trim().isEmpty) return false;
    if (state.customWords.any((w) => w.id != id && w.en.toLowerCase() == key)) return false;
    final at = _now().millisecondsSinceEpoch;
    final ex = example?.trim() ?? '';
    _save(
      state.copyWith(
        customWords: [
          for (final w in state.customWords)
            w.id == id
                ? w.copyWith(en: en.trim(), tr: tr.trim(), example: ex, clearExample: ex.isEmpty, at: at)
                : w,
        ],
      ),
    );
    return true;
  }

  /// Removes a user-added word and its review history.
  void removeCustomWord(String id) {
    final box = {...state.wordBox}..remove(id);
    final due = {...state.wordDue}..remove(id);
    final removed = state.customWords.where((w) => w.id == id);
    _save(
      state.copyWith(
        customWords: state.customWords.where((w) => w.id != id).toList(),
        wordBox: box,
        wordDue: due,
        wordLast: {...state.wordLast}..remove(id),
        removedWords: {
          ...state.removedWords,
          for (final w in removed) w.en.trim().toLowerCase(): _now().millisecondsSinceEpoch,
        },
      ),
    );
  }

  /// Saves a new or edited note in "Notlarım" (by [UserNote.id]).
  void saveUserNote({String? id, required String title, required String body}) {
    final now = _now().millisecondsSinceEpoch;
    final existing = state.userNotes.where((n) => n.id == id).firstOrNull;
    final note = existing == null
        ? UserNote(
            id: id ?? 'n_${now.toRadixString(36)}',
            title: title.trim(),
            body: body.trim(),
            createdAt: now,
            updatedAt: now,
          )
        : existing.copyWith(title: title.trim(), body: body.trim(), updatedAt: now, deleted: false);
    _save(state.copyWith(userNotes: [...state.userNotes.where((n) => n.id != note.id), note]));
  }

  /// Deletes a note (keeps an empty tombstone for sync).
  void deleteUserNote(String id) {
    final now = _now().millisecondsSinceEpoch;
    _save(
      state.copyWith(
        userNotes: [
          for (final n in state.userNotes)
            n.id == id ? n.copyWith(title: '', body: '', updatedAt: now, deleted: true) : n,
        ],
      ),
    );
  }

  /// Changes the wallet (see GoldWallet in lib/data/gold_wallet.dart).
  void updateWallet(Wallet Function(Wallet w, String device) change) =>
      _save(state.copyWith(wallet: change(state.wallet, device)));

  void dismissLeagueResult() => _save(state.copyWith(clearLeagueResult: true));

  /// Keeps the on-device tier in step with the Dünya Ligi server, so the
  /// offline preview shows the same league.
  void adoptLeagueTier(int tier) {
    final t = tier.clamp(0, leagueTiers.length - 1);
    if (t != state.leagueTier) _save(state.copyWith(leagueTier: t));
  }

  /// Replaces the progress with a copy merged with the cloud (see
  /// lib/services/firebase/progress_sync.dart).
  void applySynced(Progress merged) => _save(merged);

  void reset() => _save(const Progress(onboarded: true));
}

final progressProvider = NotifierProvider<ProgressNotifier, Progress>(ProgressNotifier.new);

/// Days until a word comes back, per spaced-repetition box. A year-long
/// plan needs boxes past a month, or known words would return every month.
const reviewIntervals = [0, 1, 3, 7, 14, 30, 60, 120, 240];
