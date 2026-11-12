import 'dart:math';

import 'question_types.dart';
import 'study_state.dart';

/// Error notebook and mock analysis (yds-faz1-yontem §4–§5): accuracy and
/// time per question type, weak units, the mock report against the 72-right
/// plan and the YDS score estimate.

/// A YDS point per right answer (80 questions, 100 points).
const ydsPointsPerQuestion = 1.25;

/// Answers before a score estimate is shown.
const minAnswersForEstimate = 20;

/// Answers per type the estimate looks back on.
const estimateWindow = 200;

/// A question slower than this (outside reading) should be marked and
/// skipped: the "2 minutes" rule.
const markAndSkipSeconds = 120;

class TypeStat {
  const TypeStat({
    required this.type,
    required this.answered,
    required this.correct,
    required this.blank,
    required this.seconds,
  });
  final QType type;
  final int answered;
  final int correct;
  final int blank;

  /// Time spent on all of them.
  final int seconds;

  int get wrong => answered - correct - blank;
  double get accuracy => answered == 0 ? 0 : correct / answered;
  double get avgSeconds => answered == 0 ? 0 : seconds / answered;
  int get targetSeconds => type.targetSeconds * answered;

  /// Slower than the target on average.
  bool get slow => answered > 0 && avgSeconds > type.targetSeconds;
}

/// Accuracy and time per type over [answers] (exam-style questions only).
Map<QType, TypeStat> typeStats(Iterable<AnswerLog> answers) {
  final groups = <QType, List<AnswerLog>>{};
  for (final a in answers) {
    final t = QType.byName(a.type);
    if (t == null || t == QType.other) continue;
    groups.putIfAbsent(t, () => []).add(a);
  }
  return {
    for (final e in groups.entries)
      e.key: TypeStat(
        type: e.key,
        answered: e.value.length,
        correct: e.value.where((a) => a.correct).length,
        blank: e.value.where((a) => a.blank).length,
        seconds: e.value.fold(0, (s, a) => s + a.seconds),
      ),
  };
}

/// Types to work on: at least [minAnswers] answered, lowest accuracy first.
List<TypeStat> weakTypes(Map<QType, TypeStat> stats, {int minAnswers = 5, int count = 3}) =>
    (stats.values.where((s) => s.answered >= minAnswers).toList()
          ..sort((a, b) => a.accuracy.compareTo(b.accuracy)))
        .take(count)
        .toList();

/// Units with the most wrong answers: (unit id, wrong, answered).
List<(String, int, int)> weakUnits(Iterable<AnswerLog> answers, {int count = 3}) {
  final wrong = <String, int>{};
  final all = <String, int>{};
  for (final a in answers) {
    final u = a.unitId;
    if (u == null || QType.byName(a.type) == null) continue;
    all[u] = (all[u] ?? 0) + 1;
    if (!a.correct) wrong[u] = (wrong[u] ?? 0) + 1;
  }
  final list = [for (final e in wrong.entries) (e.key, e.value, all[e.key]!)]
    ..sort((a, b) => b.$2.compareTo(a.$2));
  return list.take(count).toList();
}

/// A YDS score range, e.g. 62–70.
class ScoreRange {
  const ScoreRange(
    this.low,
    this.high, {
    required this.fromMocks,
    required this.basis,
    this.halfMocksOnly = false,
  });

  /// Rests on half mocks only (easier than the exam: a wider range).
  final bool halfMocksOnly;
  final int low;
  final int high;

  /// From recent mocks (else from question accuracy per type).
  final bool fromMocks;

  /// Questions the estimate rests on.
  final int basis;

  @override
  String toString() => '$low–$high';
}

/// The YDS score estimate (yds-faz1-yontem §5): the weighted mean of the last
/// three mocks of 40+ questions (newest counts most); without them, each
/// type's accuracy over its last [estimateWindow] answers weighted by its
/// share of the exam. Null with fewer than [minAnswersForEstimate] answers.
ScoreRange? estimateScore(List<AnswerLog> log, {Set<String> halfMocks = const {}}) {
  // Attempts, oldest first, by their log source; a retake of a mock already
  // seen does not count (its questions are known).
  final attempts = <String, List<AnswerLog>>{};
  for (final a in log) {
    if (a.fromMock) attempts.putIfAbsent(a.source, () => []).add(a);
  }
  final firsts = <String, List<AnswerLog>>{};
  for (final e in attempts.entries) {
    firsts.putIfAbsent(mockIdOf(e.key), () => e.value);
  }
  // Full mocks only; without them the plan's half mocks (an easier level, so
  // a wider range). Section mocks, asked right after their topics, never.
  final full = [
    for (final e in firsts.entries)
      if (fullMockId.hasMatch(e.key) && e.value.length >= 40) e.value,
  ];
  final halves = [
    for (final e in firsts.entries)
      if (halfMocks.contains(e.key)) e.value,
  ];
  final use = full.isNotEmpty ? full : halves;
  if (use.isNotEmpty) {
    final last = use.sublist(max(0, use.length - 3));
    var sum = 0.0, weights = 0.0, lo = 100.0, hi = 0.0;
    for (final (i, m) in last.indexed) {
      final pct = m.where((a) => a.correct).length / m.length;
      final w = i + 1.0;
      sum += pct * w;
      weights += w;
      lo = min(lo, pct);
      hi = max(hi, pct);
    }
    final mid = sum / weights * 100;
    final half = max(full.isNotEmpty ? 4.0 : 8.0, (hi - lo) * 100 / 2);
    return ScoreRange(
      (mid - half).clamp(0, 100).round(),
      (mid + half).clamp(0, 100).round(),
      fromMocks: true,
      halfMocksOnly: full.isEmpty,
      basis: last.fold(0, (s, m) => s + m.length),
    );
  }
  final byType = <QType, List<AnswerLog>>{};
  for (final a in log.reversed) {
    final t = QType.byName(a.type);
    if (t == null || t == QType.other) continue;
    final list = byType.putIfAbsent(t, () => []);
    if (list.length < estimateWindow) list.add(a);
  }
  final n = byType.values.fold(0, (s, l) => s + l.length);
  if (n < minAnswersForEstimate) return null;
  final overall = byType.values.expand((l) => l).where((a) => a.correct).length / n;
  var right = 0.0;
  for (final t in QType.values.where((t) => t.inExam > 0)) {
    final l = byType[t];
    final acc = l == null || l.length < 5 ? overall : l.where((a) => a.correct).length / l.length;
    right += t.inExam * acc;
  }
  final mid = right * ydsPointsPerQuestion;
  final half = n < 100 ? 8.0 : (n < 400 ? 6.0 : 4.0);
  return ScoreRange(
    (mid - half).clamp(0, 100).round(),
    (mid + half).clamp(0, 100).round(),
    fromMocks: false,
    basis: n,
  );
}

/// A pack's full mock id (yds_m9).
final fullMockId = RegExp(r'^yds_m\d+$');

/// Mock id of a log source (`mock:<id>@<start>`).
String mockIdOf(String source) {
  final s = source.startsWith('mock:') ? source.substring(5) : source;
  final at = s.lastIndexOf('@');
  return at < 0 ? s : s.substring(0, at);
}

/// One row of the mock report.
class MockRow {
  const MockRow(this.stat, this.target);
  final TypeStat stat;

  /// Right answers the 72-right plan expects for this many questions.
  final double target;

  /// Right answers short of the plan.
  int get gap => max(0, (target - stat.correct).ceil());
}

/// The mock report: per type right/wrong/blank, time against the targets
/// and the gap to the 72-right plan (scaled to the mock's size).
class MockReport {
  MockReport(List<AnswerLog> answers) : stats = typeStats(answers), total = answers.length;
  final Map<QType, TypeStat> stats;
  final int total;

  List<MockRow> get rows => [
    for (final t in QType.values)
      if (stats[t] case final s?)
        MockRow(s, t.inExam == 0 ? s.answered.toDouble() : t.target72 * s.answered / t.inExam),
  ];

  int get correct => stats.values.fold(0, (s, t) => s + t.correct);
  int get blank => stats.values.fold(0, (s, t) => s + t.blank);
  int get seconds => stats.values.fold(0, (s, t) => s + t.seconds);
  int get targetSeconds => stats.values.fold(0, (s, t) => s + t.targetSeconds);

  /// Score on the YDS scale for a full mock; a percentage otherwise.
  double get percent => total == 0 ? 0 : correct * 100 / total;

  /// Types to work on: the biggest gaps first.
  List<MockRow> get focus => (rows.where((r) => r.gap > 0).toList()..sort((a, b) => b.gap.compareTo(a.gap)));
}

/// Questions of [answers] over the 2-minute rule (reading has its own
/// 12 minutes per text).
int overTwoMinutes(Iterable<AnswerLog> answers) =>
    answers.where((a) => a.type != QType.reading.name && a.seconds > markAndSkipSeconds).length;
