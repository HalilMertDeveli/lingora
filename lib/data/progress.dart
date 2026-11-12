import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/tr_errors.dart';
import '../models/notes.dart';
import 'catalog.dart';
import 'league.dart';
import 'quests.dart';

/// Most questions kept in the error notebook (oldest dropped first).
const maxMistakes = 300;

/// Days until a notebook question comes back, per stage: 1 → 3 → 7 → 21.
const mistakeIntervals = [1, 3, 7, 21];

/// Right answers in a row that take a question out of the notebook.
const mistakeClearRun = 2;

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
  });

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
  });
  final int xp;
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

    _save(
      state.copyWith(
        totalXp: state.totalXp + xp,
        streak: newStreak,
        lastActiveDay: today,
        xpByDay: {...state.xpByDay, today: todayXp},
        completed: {...state.completed, nodeId: (state.completed[nodeId] ?? 0) + 1},
        lessonsDone: state.lessonsDone + (isLesson ? 1 : 0),
        correct: state.correct + correct,
        answered: state.answered + answered,
        counters: counters,
      ),
    );

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
      ),
    );
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
    final result = finishWeek(tier: state.leagueTier, weekStart: start, userXp: state.weekXp(start));
    _save(state.copyWith(leagueTier: result.newTier, leagueWeek: current, leagueResult: result));
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
      ),
    );
  }

  static Map<String, V> _without<V>(Map<String, V> map, List<String> keys) =>
      keys.isEmpty ? map : ({...map}..removeWhere((k, _) => keys.contains(k)));

  void setTrack(String id) => _save(state.copyWith(trackId: id));

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
  void reviewWord(String id, {required bool known}) {
    final now = _now();
    final old = state.wordBox[id] ?? 0;
    final box = known ? min(old + 1, reviewIntervals.length - 1) : max(0, old - 2);
    final due = dayKey(now.add(Duration(days: reviewIntervals[box])));
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
  void learnWord(String id, {required bool known}) {
    final fresh = !state.wordBox.containsKey(id);
    reviewWord(id, known: known);
    if (!fresh) return;
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
  /// category once per check.
  void recordTrErrors(Iterable<TrError> errors) => recordErrorCategories(errors.map((e) => e.category));

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
  /// already added the same English word.
  bool addCustomWord(NoteWord word) {
    final key = word.en.trim().toLowerCase();
    if (key.isEmpty || state.customWords.any((w) => w.en.toLowerCase() == key)) return false;
    _save(state.copyWith(customWords: [...state.customWords, word]));
    return true;
  }

  /// Removes a user-added word and its review history.
  void removeCustomWord(String id) {
    final box = {...state.wordBox}..remove(id);
    final due = {...state.wordDue}..remove(id);
    _save(
      state.copyWith(
        customWords: state.customWords.where((w) => w.id != id).toList(),
        wordBox: box,
        wordDue: due,
        wordLast: {...state.wordLast}..remove(id),
      ),
    );
  }

  void dismissLeagueResult() => _save(state.copyWith(clearLeagueResult: true));

  /// Replaces the progress with a copy merged with the cloud (see
  /// lib/services/firebase/progress_sync.dart).
  void applySynced(Progress merged) => _save(merged);

  void reset() => _save(const Progress(onboarded: true));
}

final progressProvider = NotifierProvider<ProgressNotifier, Progress>(ProgressNotifier.new);

/// Days until a word comes back, per spaced-repetition box. A year-long
/// plan needs boxes past a month, or known words would return every month.
const reviewIntervals = [0, 1, 3, 7, 14, 30, 60, 120, 240];
