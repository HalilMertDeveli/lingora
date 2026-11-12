import 'dart:math';

import '../data/placement.dart' show Cefr;
import '../data/progress.dart';
import '../models/course.dart';
import '../models/study_plan.dart';
import 'review_queue.dart';
import 'year_plan.dart';

/// "Bugün": the day's study built from the year plan's week (yds-faz1-yontem
/// §3). Weeks move on by steps: when the week's units are done and its new
/// words are started (a review week: after a week's study days), never by
/// the calendar, so a missed day never piles up.

/// Blocks of a study day.
enum PlanBlock {
  review('Tekrar kartları', '🔁'),
  lesson('Yeni ders', '📘'),
  reading('Okuma', '📚'),
  questions('Soru', '🧩'),
  mistakes('Hata defteri', '🔎'),
  mock('Deneme', '⏱️'),
  mockReview('Deneme analizi', '🔬');

  const PlanBlock(this.title, this.emoji);
  final String title;
  final String emoji;
}

enum DayKind { normal, light, mock, afterMock }

/// Daily time choices, in minutes (the plan is built for 2–4 hours; the
/// shorter ones keep the habit on busy days).
const dailyMinuteChoices = [30, 60, 120, 180, 240];

/// Lessons a day in the "Yeni ders" block.
const lessonsPerDay = 2;

/// Light day (about 90 minutes): review, notebook, easy reading, report.
const lightDayMinutes = {PlanBlock.review: 30, PlanBlock.mistakes: 20, PlanBlock.reading: 40};

/// Start week for a placement level: A0–A1 → 1, A2 → 11, B1 and above → 21.
int startWeekFor(Cefr? level) => switch (level) {
  null || Cefr.a1 => 1,
  Cefr.a2 => 11,
  _ => 21,
};

/// Plan weeks a learner may start at by hand: the phases' first weeks.
List<int> startWeeks(YearPlan plan) =>
    plan.phases.isEmpty ? const [1, 11, 21, 35, 43] : [for (final p in plan.phases) p.from];

/// Units of the courses the plan uses (general course and YDS path), by id.
Map<String, Unit> planUnits(Iterable<Course> courses) => {
  for (final c in courses)
    for (final u in c.units) u.id: u,
};

/// Word cards started so far (YDS and general course cards).
int wordsStarted(Progress p) => p.wordBox.keys
    .where((k) => k.startsWith(ydsWordPrefix) || k.startsWith('yd_') || k.startsWith(generalWordPrefix))
    .length;

/// Where the learner stands in the current week.
class WeekStatus {
  const WeekStatus({
    required this.stepsDone,
    required this.stepsTotal,
    required this.words,
    required this.wordsTarget,
    required this.studyDays,
    required this.done,
  });
  final int stepsDone;
  final int stepsTotal;
  final int words;
  final int wordsTarget;

  /// Days with study since the week began.
  final int studyDays;
  final bool done;
}

List<PathNode> _steps(Iterable<String> unitIds, Map<String, Unit> units) => [
  for (final id in unitIds)
    for (final n in units[id]?.nodes ?? const <PathNode>[])
      if (n.type != NodeType.mock) n,
];

WeekStatus weekStatus({
  required StudyPlan plan,
  required YearPlan year,
  required Map<String, Unit> units,
  required Progress progress,
  bool noNewCards = false,
}) {
  final week = year.week(plan.week);
  final steps = _steps(week.unitIds, units);
  final done = steps.where((n) => progress.isDone(n.id)).length;
  final words = max(0, wordsStarted(progress) - plan.weekWordsBase);
  final studyDays = progress.xpByDay.entries
      .where((e) => e.value > 0 && e.key.compareTo(plan.weekStart) >= 0)
      .length;
  final finished = week.reviewWeek
      ? studyDays >= year.daysPerWeek
      : done >= steps.length && (words >= week.newWords || noNewCards);
  return WeekStatus(
    stepsDone: done,
    stepsTotal: steps.length,
    words: words,
    wordsTarget: week.newWords,
    studyDays: studyDays,
    done: finished,
  );
}

/// [plan] moved on past every finished week (a week at most per call, so
/// the learner sees each new week begin).
StudyPlan settleWeek({
  required StudyPlan plan,
  required YearPlan year,
  required Map<String, Unit> units,
  required Progress progress,
  required DateTime now,
  bool noNewCards = false,
}) {
  if (plan.week >= year.length) return plan;
  final status = weekStatus(plan: plan, year: year, units: units, progress: progress, noNewCards: noNewCards);
  if (!status.done) return plan;
  return plan.copyWith(week: plan.week + 1, weekStart: dayKey(now), weekWordsBase: wordsStarted(progress));
}

/// The next path step of the week: its main units first, then the side
/// paths (Kelime bankası, Okuma evi).
/// Side-path units left unfinished in earlier weeks come after the week's
/// own (oldest first), so a week that moved on early does not drop them.
(Unit, PathNode)? nextPlanStep(PlanWeek week, Map<String, Unit> units, Progress p, {YearPlan? year}) {
  final earlier = [
    if (year != null)
      for (var w = 1; w < week.week; w++) ...year.week(w).parallelUnitIds,
  ];
  for (final id in {...week.unitIds, ...week.parallelUnitIds, ...earlier}) {
    final unit = units[id];
    if (unit == null) continue;
    for (final n in unit.nodes) {
      if (n.type != NodeType.mock && !p.isDone(n.id)) return (unit, n);
    }
  }
  return null;
}

/// Days after the first mock that a week's second mock comes (§3.3).
const secondMockAfterDays = 3;

/// The mock of the day: the week's first mock on the mock day, a second one
/// [secondMockAfterDays] days later. A level check is never a mock day.
PlanMock? todayMock({required StudyPlan plan, required PlanWeek week, required DateTime now}) {
  final mocks = week.examMocks;
  if (mocks.isEmpty) return null;
  if (now.weekday == plan.mockDay) return mocks.first;
  final second = (plan.mockDay - 1 + secondMockAfterDays) % 7 + 1;
  if (mocks.length > 1 && now.weekday == second) return mocks[1];
  return null;
}

DayKind dayKind({
  required StudyPlan plan,
  required PlanWeek week,
  required DateTime now,
  bool mockYesterday = false,
}) {
  if (todayMock(plan: plan, week: week, now: now) != null) return DayKind.mock;
  if (mockYesterday) return DayKind.afterMock;
  if (now.weekday == plan.lightDay) return DayKind.light;
  return DayKind.normal;
}

/// Break between blocks on a day of [daily] minutes (10 min from 2 hours).
int breakMinutes(int daily) => daily >= 120 ? 10 : 0;

/// Minutes per block: the plan's shares of the day without its break, in
/// whole 5 minutes (largest remainder first), at least 5 each. A 3.5-hour
/// day is 30/60/45/45/20 plus a 10-minute break (yds-1-yil.md §3.1).
Map<PlanBlock, int> blockMinutes(int daily, Map<String, double> shares) {
  final s = {
    PlanBlock.review: shares['review'] ?? 0.15,
    PlanBlock.lesson: shares['lesson'] ?? 0.30,
    PlanBlock.reading: shares['reading'] ?? 0.225,
    PlanBlock.questions: shares['questions'] ?? 0.225,
    PlanBlock.mistakes: shares['mistakes'] ?? 0.10,
  };
  final study = daily - breakMinutes(daily);
  final raw = {for (final e in s.entries) e.key: study * e.value};
  final result = {for (final e in raw.entries) e.key: max(5, (e.value / 5).floor() * 5)};
  var left = study - result.values.fold(0, (a, b) => a + b);
  final byRemainder = raw.keys.toList()
    ..sort((a, b) => (raw[b]! - result[b]!).compareTo(raw[a]! - result[a]!));
  for (var i = 0; left >= 5 && i < 100; i++) {
    final b = byRemainder[i % byRemainder.length];
    result[b] = result[b]! + 5;
    left -= 5;
  }
  return result;
}

/// One block of today's plan.
class DayBlock {
  const DayBlock({
    required this.block,
    required this.minutes,
    required this.detail,
    required this.progress,
    this.title,
  });
  final PlanBlock block;
  final int minutes;

  /// What it holds today ("2 ders", "1.000 kelime").
  final String detail;

  /// 0–1.
  final double progress;
  final String? title;

  String get name => title ?? block.title;
  bool get done => progress >= 1;
}

/// What the day's blocks are measured against.
class DayCounts {
  const DayCounts({
    this.cardsLeft = 0,
    this.cardsDone = 0,
    this.reviewDay = false,
    this.mistakesDue = 0,
    this.lessonsToday = 0,
    this.questionsToday = 0,
    this.readingToday = 0,
    this.mockToday = false,
  });

  /// Word cards still due or allowed new today, and cards reviewed today.
  final int cardsLeft;
  final int cardsDone;
  final bool reviewDay;
  final int mistakesDue;
  final int lessonsToday;
  final int questionsToday;
  final int readingToday;
  final bool mockToday;
}

String _n(int n) {
  final s = n.toString();
  return s.length <= 3 ? s : '${s.substring(0, s.length - 3)}.${s.substring(s.length - 3)}';
}

double _ratio(int done, int target) => target <= 0 ? 1 : (done / target).clamp(0, 1).toDouble();

List<DayBlock> dayBlocks({
  required DayKind kind,
  required StudyPlan plan,
  required YearPlan year,
  required PlanWeek week,
  required DayCounts c,
  String? nextStep,
  PlanMock? mock,
}) {
  final minutes = blockMinutes(plan.dailyMinutes, year.shares);
  final reviewTotal = c.cardsDone + c.cardsLeft;
  DayBlock review(int m) => DayBlock(
    block: PlanBlock.review,
    minutes: m,
    detail: c.cardsLeft == 0 && c.mistakesDue == 0
        ? 'Bugünlük kart kalmadı'
        : '${c.cardsLeft} kart${c.reviewDay ? ' · tekrar günü: yeni kelime azaltıldı' : ''}',
    progress: c.cardsLeft == 0 ? 1 : _ratio(c.cardsDone, reviewTotal),
  );
  DayBlock mistakes(int m) => DayBlock(
    block: PlanBlock.mistakes,
    minutes: m,
    detail: c.mistakesDue == 0 ? 'Vadesi gelen soru yok' : '${c.mistakesDue} soru bugün tekrar zamanında',
    progress: c.mistakesDue == 0 ? 1 : 0,
  );
  DayBlock reading(int m, {bool easy = false}) => DayBlock(
    block: PlanBlock.reading,
    minutes: m,
    detail: easy
        ? 'Keyif için kolay okuma'
        : '${_n(c.readingToday)} / ${_n(week.readingWordsPerDay)} kelime'
              '${week.intensiveTextsPerDay > 0 ? ' · ${week.intensiveTextsPerDay} yoğun metin' : ''}',
    progress: easy ? (c.readingToday > 0 ? 1 : 0) : _ratio(c.readingToday, week.readingWordsPerDay),
  );
  switch (kind) {
    case DayKind.mock:
      final m = mock ?? (week.examMocks.isEmpty ? null : week.examMocks.first);
      return [
        review(20),
        DayBlock(
          block: PlanBlock.mock,
          title: m?.label,
          minutes: m == null || m.minutes == 0 ? 90 : m.minutes,
          detail: '${m == null || m.size == 0 ? '' : '${m.size} soru · '}tek oturum, gerçek koşul',
          progress: c.mockToday ? 1 : 0,
        ),
      ];
    case DayKind.light:
      return [
        review(lightDayMinutes[PlanBlock.review]!),
        mistakes(lightDayMinutes[PlanBlock.mistakes]!),
        reading(lightDayMinutes[PlanBlock.reading]!, easy: true),
      ];
    case DayKind.normal || DayKind.afterMock:
      final lessonTarget = nextStep == null ? 0 : lessonsPerDay;
      final blocks = <DayBlock>[
        review(minutes[PlanBlock.review]!),
        DayBlock(
          block: PlanBlock.lesson,
          minutes: minutes[PlanBlock.lesson]!,
          detail: nextStep == null
              ? 'Haftanın üniteleri bitti: tekrar ve soruya ağırlık ver'
              : '${min(c.lessonsToday, lessonsPerDay)} / $lessonsPerDay ders · sıradaki: $nextStep',
          progress: _ratio(c.lessonsToday, lessonTarget),
        ),
        reading(minutes[PlanBlock.reading]!),
        if (kind == DayKind.afterMock)
          DayBlock(
            block: PlanBlock.mockReview,
            minutes: minutes[PlanBlock.questions]!,
            detail: 'Dünkü denemenin yanlışları: neden yanıldın?',
            progress: c.mistakesDue == 0 ? 1 : 0,
          )
        else if (week.choicePerDay > 0)
          DayBlock(
            block: PlanBlock.questions,
            minutes: minutes[PlanBlock.questions]!,
            title: 'Soru',
            detail:
                '${c.questionsToday} / ${week.choicePerDay} soru'
                '${week.questionWork.isEmpty || week.questionWork == '—' ? '' : ' · ${week.questionWork}'}',
            progress: _ratio(c.questionsToday, week.choicePerDay),
          ),
        mistakes(minutes[PlanBlock.mistakes]!),
      ];
      // Short days: memory and mistakes first, then questions (§3.1 note).
      if (plan.dailyMinutes <= 60) {
        const order = [
          PlanBlock.review,
          PlanBlock.mistakes,
          PlanBlock.questions,
          PlanBlock.mockReview,
          PlanBlock.lesson,
          PlanBlock.reading,
        ];
        blocks.sort((a, b) => order.indexOf(a.block).compareTo(order.indexOf(b.block)));
      }
      return blocks;
  }
}

/// Day the plan would end if every week from now takes a calendar week.
DateTime estimatedFinish(StudyPlan plan, YearPlan year, DateTime now) =>
    now.add(Duration(days: (year.length - plan.week + 1) * 7));
