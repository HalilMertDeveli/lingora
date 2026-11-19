import 'dart:convert';

import '../../data/level_report.dart';
import '../../data/progress.dart';
import '../../data/progress_tally.dart';
import '../../models/notes.dart';
import '../../data/wallet.dart';
import '../../goals/learn_goal.dart';
import '../../models/study_plan.dart';

/// Merges two copies of the user's progress (this device and the cloud) so
/// that nothing earned is ever lost:
///
/// * a copy from before a progress reset ([Progress.resetAt]) is discarded:
///   the copy with the later reset is taken as it is;
/// * additive numbers (XP, XP per day, completed nodes, lesson/answer
///   counts, quest counters, reading words, error stats) add up per device
///   without counting anything twice ([mergeTallies]); copies without a
///   tally fall back to the maximum;
/// * exam bests take the maximum per key;
/// * collections the user builds up (claimed quests, diary days) are
///   united;
/// * own words and own notes are united per item, the later edit winning;
///   a deletion on one device (a tombstone) wins over an older copy;
/// * the streak comes from whichever copy was active more recently (the
///   longer one on the same day);
/// * settings and lists the user edits (daily goal, reminders, track,
///   mistakes, league state) come from the copy changed last ([localNewer]);
/// * the Altın wallet is merged by [mergeWallets] (no gold is lost);
/// * Seviye Karnesi reports are united per day ([mergeLevelReports]).
Progress mergeProgress(Progress local, Progress remote, {required bool localNewer}) {
  // A reset wins over everything from before it, on any device.
  if (local.resetAt != remote.resetAt) return local.resetAt > remote.resetAt ? local : remote;
  final newer = localNewer ? local : remote;
  final older = localNewer ? remote : local;

  Map<String, int> maxMap(Map<String, int> a, Map<String, int> b) => {
    ...a,
    for (final e in b.entries)
      if (!a.containsKey(e.key) || e.value > a[e.key]!) e.key: e.value,
  };
  int maxInt(int a, int b) => a > b ? a : b;

  // Streak: later active day wins; same day → longer streak.
  final la = local.lastActiveDay ?? '';
  final ra = remote.lastActiveDay ?? '';
  final cmp = la.compareTo(ra);
  final streakFrom = cmp > 0 ? local : (cmp < 0 ? remote : (local.streak >= remote.streak ? local : remote));

  // Spaced repetition: per word, the copy reviewed last (see [laterReview]).
  final wordBox = <String, int>{};
  final wordDue = <String, String>{};
  final wordLast = <String, String>{};
  final wordAt = <String, int>{};
  for (final id in {
    ...local.wordBox.keys,
    ...remote.wordBox.keys,
    ...local.wordDue.keys,
    ...remote.wordDue.keys,
  }) {
    final useRemote = laterReview(remote, local, id, aNewer: !localNewer);
    final src = useRemote ? remote : local;
    if (src.wordBox[id] case final b?) wordBox[id] = b;
    if (src.wordDue[id] case final d?) wordDue[id] = d;
    if (src.wordLast[id] case final l?) wordLast[id] = l;
    if (src.wordAt[id] case final t?) wordAt[id] = t;
  }

  // Additive numbers: per-device counters, nothing lost or counted twice.
  final sums = mergeTallies(local, remote);

  // League: the later week wins; same week → the newer copy.
  final lw = local.leagueWeek ?? '';
  final rw = remote.leagueWeek ?? '';
  final leagueFrom = lw.compareTo(rw) > 0 ? local : (lw.compareTo(rw) < 0 ? remote : newer);

  // Own words: union by English word; the later edit wins (newer copy on a
  // tie); a later deletion removes the word.
  final removedWords = <String, int>{...local.removedWords};
  for (final e in remote.removedWords.entries) {
    if ((removedWords[e.key] ?? -1) < e.value) removedWords[e.key] = e.value;
  }
  final words = <String, NoteWord>{};
  for (final w in [...newer.customWords, ...older.customWords]) {
    final key = w.en.trim().toLowerCase();
    final have = words[key];
    if (have == null || (w.at ?? 0) > (have.at ?? 0)) words[key] = w;
  }
  words.removeWhere((key, w) => (removedWords[key] ?? -1) >= (w.at ?? 0));

  // Own notes: per id, the later edit (or deletion) wins.
  final notes = <String, UserNote>{};
  for (final n in [...newer.userNotes, ...older.userNotes]) {
    final have = notes[n.id];
    if (have == null || n.updatedAt > have.updatedAt) notes[n.id] = n;
  }

  final merged = Progress(
    resetAt: local.resetAt,
    wordAt: wordAt,
    onboarded: local.onboarded || remote.onboarded,
    dailyGoal: newer.dailyGoal,
    totalXp: maxInt(local.totalXp, remote.totalXp),
    streak: streakFrom.streak,
    lastActiveDay: streakFrom.lastActiveDay,
    xpByDay: maxMap(local.xpByDay, remote.xpByDay),
    completed: maxMap(local.completed, remote.completed),
    lessonsDone: maxInt(local.lessonsDone, remote.lessonsDone),
    correct: maxInt(local.correct, remote.correct),
    answered: maxInt(local.answered, remote.answered),
    counters: maxMap(local.counters, remote.counters),
    claimed: [
      ...newer.claimed,
      for (final c in older.claimed)
        if (!newer.claimed.contains(c)) c,
    ],
    leagueTier: leagueFrom.leagueTier,
    leagueWeek: leagueFrom.leagueWeek,
    leagueResult: leagueFrom.leagueResult,
    remindersEnabled: newer.remindersEnabled ?? older.remindersEnabled,
    reminderMinutes: newer.reminderMinutes,
    mistakes: newer.mistakes,
    trackId: newer.trackId,
    examBest: maxMap(local.examBest, remote.examBest),
    examSeconds: {...older.examSeconds, ...newer.examSeconds},
    wordBox: wordBox,
    wordDue: wordDue,
    diary: {...older.diary, ...newer.diary},
    errorStats: maxMap(local.errorStats, remote.errorStats),
    // Wrong-answer counts only grow until the question is saved.
    mistakeMisses: {
      for (final e in maxMap(local.mistakeMisses, remote.mistakeMisses).entries)
        if (!newer.mistakes.contains(e.key)) e.key: e.value,
    },
    customWords: words.values.toList(),
    removedWords: removedWords,
    userNotes: notes.values.toList(),
    wordLast: wordLast,
    studyPlan: _laterPlan(newer, older),
    readingWords: maxInt(local.readingWords, remote.readingWords),
    // The error notebook travels with its list.
    mistakeStage: {for (final k in newer.mistakes) k: ?newer.mistakeStage[k]},
    mistakeDue: {for (final k in newer.mistakes) k: ?newer.mistakeDue[k]},
    mistakeRun: {for (final k in newer.mistakes) k: ?newer.mistakeRun[k]},
    mistakeReason: {for (final k in newer.mistakes) k: ?(newer.mistakeReason[k] ?? older.mistakeReason[k])},
    mistakeNote: {for (final k in newer.mistakes) k: ?(newer.mistakeNote[k] ?? older.mistakeNote[k])},
    // Altın: grow-only counters per device, owned items united (wallet.dart).
    wallet: mergeWallets(local.wallet, remote.wallet),
    // The goal: the later choice wins (either copy may not have one yet).
    learnGoal: _laterGoal(local.learnGoal, remote.learnGoal),
    // Seviye Karnesi: one report per day, united.
    levelReports: mergeLevelReports(local.levelReports, remote.levelReports),
  );
  return withCounts(merged, sums.counts).copyWith(tally: sums.tally);
}

/// Whether [a]'s review of word [id] is later than [b]'s: by the last review
/// day, then the exact review time (copies saved before [Progress.wordAt]
/// have none), then the later due day (the old rule); on a full tie,
/// [aNewer] (whether [a] is the copy changed last).
bool laterReview(Progress a, Progress b, String id, {required bool aNewer}) {
  int cmp<T extends Comparable<T>>(T? x, T? y) =>
      x == null ? (y == null ? 0 : -1) : (y == null ? 1 : x.compareTo(y));
  if (!a.wordBox.containsKey(id) && !a.wordDue.containsKey(id)) return false;
  if (!b.wordBox.containsKey(id) && !b.wordDue.containsKey(id)) return true;
  for (final c in [
    cmp<String>(a.wordLast[id], b.wordLast[id]),
    cmp<num>(a.wordAt[id], b.wordAt[id]),
    cmp<String>(a.wordDue[id], b.wordDue[id]),
  ]) {
    if (c != 0) return c > 0;
  }
  return aNewer;
}

LearnGoal? _laterGoal(LearnGoal? a, LearnGoal? b) {
  if (a == null) return b;
  if (b == null) return a;
  return b.at > a.at ? b : a;
}

/// The study plan of the newer copy, but never a week behind the other one
/// (a week reached is not undone by a stale device).
StudyPlan? _laterPlan(Progress newer, Progress older) {
  final a = newer.studyPlan, b = older.studyPlan;
  if (a == null || b == null) return a ?? b;
  return b.week > a.week
      ? a.copyWith(week: b.week, weekStart: b.weekStart, weekWordsBase: b.weekWordsBase)
      : a;
}

/// Order-independent JSON of [p], used to tell whether two copies differ.
String canonicalProgress(Progress p) => jsonEncode(_sorted(jsonDecode(jsonEncode(p.toJson()))));

Object? _sorted(Object? v) => switch (v) {
  Map() => {for (final k in (v.keys.map((k) => '$k').toList()..sort())) k: _sorted(v[k])},
  List() => [for (final e in v) _sorted(e)],
  _ => v,
};

/// Progress JSON as read back from Firestore (nested maps are
/// `Map<String, dynamic>` with dynamic values) → [Progress].
Progress progressFromFirestore(Map<String, dynamic> raw) {
  final Map<String, dynamic> j = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
  return Progress.fromJson(j);
}
