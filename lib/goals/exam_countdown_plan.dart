import 'dart:math';

import '../study/question_types.dart';

/// "Sınava kadar şu konuları çalış": a day-by-day plan from today to the
/// exam, built from the learner's weak question types and the days left.
/// Pure, so it can be unit tested; the screen turns [PlanLink]s into the
/// app's existing lessons, topic practice and mock exams.

/// Longest plan drawn day by day; a later exam gets these days first (the
/// plan is rebuilt every day, so it always looks this far ahead).
const maxCountdownDays = 90;

/// Every this-many days a full mock exam (yds-faz1-yontem: weekly mocks).
const mockEveryDays = 7;

enum CountdownDayKind {
  /// Study the day's focus type: a lesson + topic practice + review cards.
  study,

  /// A full mock exam under real time.
  mock,

  /// The day after a mock: its report and the error notebook.
  analysis,

  /// The day before the exam: light review, no new topics.
  eve,
}

enum PlanItemKind { lesson, practice, mock, report, notebook, review }

/// Something the plan opens: a path unit, an exam bank section, a mock...
class PlanLink {
  const PlanLink(this.kind, this.title, {this.ref});
  final PlanItemKind kind;
  final String title;

  /// Unit id (lesson), exam section id (practice); null otherwise.
  final String? ref;

  @override
  bool operator ==(Object other) => other is PlanLink && other.kind == kind && other.title == title && other.ref == ref;

  @override
  int get hashCode => Object.hash(kind, title, ref);

  @override
  String toString() => '${kind.name}:${ref ?? title}';
}

class CountdownDay {
  const CountdownDay({required this.index, required this.date, required this.kind, required this.items, this.focus});

  /// 0 = today.
  final int index;
  final DateTime date;
  final CountdownDayKind kind;

  /// Question type the day works on (study days).
  final QType? focus;
  final List<PlanLink> items;
}

class CountdownPlan {
  const CountdownPlan({required this.daysLeft, required this.days, required this.weights});

  /// Days from today to the exam (0 = exam day).
  final int daysLeft;
  final List<CountdownDay> days;

  /// How much each focus type weighed, strongest first.
  final List<(QType, double)> weights;

  /// Study days per focus type, for the summary line.
  Map<QType, int> get focusDays {
    final m = <QType, int>{};
    for (final d in days) {
      if (d.focus case final f?) m[f] = (m[f] ?? 0) + 1;
    }
    return m;
  }

  bool get isEmpty => days.isEmpty;
}

/// Builds the plan.
///
/// * [daysLeft]: days from [today] to the exam; nothing to plan at ≤ 0.
/// * [weak]: weak question types with how many right answers they are short
///   of the 72-right target (`MockReport.focus`), strongest gap first. Empty
///   when no full mock was taken yet: then day 1 is a mock ("önce durumunu
///   gör") and the exam's own question mix decides the weights.
/// * [lessons] / [practice]: existing path units and exam bank sections per
///   type; a type with none still gets review and practice where it can.
CountdownPlan buildCountdownPlan({
  required DateTime today,
  required int daysLeft,
  required List<(QType, int)> weak,
  Map<QType, List<PlanLink>> lessons = const {},
  Map<QType, List<PlanLink>> practice = const {},
  ExamMix mix = ExamMix.yds,
}) {
  if (daysLeft <= 0) return CountdownPlan(daysLeft: daysLeft, days: const [], weights: const []);
  final noMock = weak.isEmpty;
  final weights = noMock
      ? <(QType, double)>[
          for (final t in QType.values)
            if (t != QType.other && mix.count(t) > 0) (t, mix.count(t).toDouble()),
        ]
      : <(QType, double)>[
          for (final (t, gap) in weak)
            if (gap > 0 && t != QType.other) (t, gap.toDouble()),
        ];
  weights.sort((a, b) => b.$2.compareTo(a.$2));

  final n = min(daysLeft, maxCountdownDays);
  final start = DateTime(today.year, today.month, today.day);
  // Smooth weighted round robin: each type gets days in proportion to its
  // weight, spread out (never the same type many days in a row).
  final current = {for (final (t, _) in weights) t: 0.0};
  final total = weights.fold(0.0, (s, w) => s + w.$2);
  QType? nextFocus() {
    if (weights.isEmpty) return null;
    QType? best;
    for (final (t, w) in weights) {
      current[t] = current[t]! + w;
      if (best == null || current[t]! > current[best]!) best = t;
    }
    current[best!] = current[best]! - total;
    return best;
  }

  final used = <QType, int>{};
  PlanLink? pick(Map<QType, List<PlanLink>> from, QType t, int k) {
    final list = from[t];
    if (list == null || list.isEmpty) return null;
    return list[k % list.length];
  }

  const review = PlanLink(PlanItemKind.review, 'Tekrar kartları (15 dk)');
  const mock = PlanLink(PlanItemKind.mock, 'Tam deneme (gerçek süreyle)');
  final days = <CountdownDay>[];
  // With a mock already taken, the next one is a week from today.
  var lastMock = 0;
  for (var i = 0; i < n; i++) {
    final date = start.add(Duration(days: i));
    final isEve = i == daysLeft - 1 && daysLeft > 1;
    if (isEve) {
      days.add(
        CountdownDay(
          index: i,
          date: date,
          kind: CountdownDayKind.eve,
          items: const [
            review,
            PlanLink(PlanItemKind.notebook, 'Hata defterinden son tekrar'),
          ],
        ),
      );
      continue;
    }
    // A mock on day 1 without data; then every [mockEveryDays] days. Not
    // the two days before the exam (rest, then the eve).
    final mockDay = (noMock && i == 0) || (i - lastMock >= mockEveryDays && i > 0 && i < daysLeft - 2);
    if (mockDay) {
      lastMock = i;
      days.add(CountdownDay(index: i, date: date, kind: CountdownDayKind.mock, items: const [mock]));
      continue;
    }
    final focus = nextFocus();
    final k = focus == null ? 0 : (used[focus] = (used[focus] ?? -1) + 1);
    if (days.isNotEmpty && days.last.kind == CountdownDayKind.mock) {
      days.add(
        CountdownDay(
          index: i,
          date: date,
          kind: CountdownDayKind.analysis,
          focus: focus,
          items: [
            const PlanLink(PlanItemKind.report, 'Deneme raporunu incele'),
            const PlanLink(PlanItemKind.notebook, 'Yanlışları hata defterine işle'),
            if (focus != null) ?pick(practice, focus, k),
          ],
        ),
      );
      continue;
    }
    days.add(
      CountdownDay(
        index: i,
        date: date,
        kind: CountdownDayKind.study,
        focus: focus,
        items: [
          if (focus != null) ...[?pick(lessons, focus, k), ?pick(practice, focus, k)],
          review,
        ],
      ),
    );
  }
  return CountdownPlan(daysLeft: daysLeft, days: days, weights: weights);
}

/// The YDS score estimate of one finished mock: every question weighs the
/// same, the whole test is 100 points (YDS/YÖKDİL: 80 questions × 1,25),
/// wrong answers cost nothing. An estimate: ÖSYM computes the real score.
double estimatedYdsScore({required int correct, required int total}) =>
    total <= 0 ? 0 : (correct.clamp(0, total) * 100 / total);

/// "72,5" (Turkish decimal comma, at most two decimals).
String formatScore(double score) {
  final r = (score * 100).round() / 100;
  final s = r == r.roundToDouble() ? r.toStringAsFixed(0) : (r * 10 == (r * 10).roundToDouble() ? r.toStringAsFixed(1) : r.toStringAsFixed(2));
  return s.replaceAll('.', ',');
}
