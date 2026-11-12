import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The 52-week YDS programme (assets/plans/yds_1_yil.json, written by
/// yds-arastirma from docs/sinav/yds-1-yil.md).

const yearPlanAsset = 'assets/plans/yds_1_yil.json';

class PlanWeek {
  const PlanWeek({
    required this.week,
    required this.phase,
    required this.units,
    this.unitIds = const [],
    this.parallelUnitIds = const [],
    this.questionWork = '',
    this.mock,
    this.newWords = 0,
    this.wordsTotal = 0,
    this.readingWordsPerDay = 0,
    this.intensiveTextsPerDay = 0,
    this.choicePerDay = 0,
  });

  final int week;
  final int phase;

  /// What the week covers, for people ("YDS ys1u4 Koşul ve wish").
  final String units;

  /// Main-path units of the week: general course ("u1", "s2u3") or YDS
  /// ("ys1u11"). Empty in a review week.
  final List<String> unitIds;

  /// Side-path units (Kelime bankası ys5, Okuma evi ys6).
  final List<String> parallelUnitIds;
  final String questionWork;

  /// The week's mock exam, if any ("Tam deneme 3 (yeni: yds_m11)").
  final String? mock;
  final int newWords;
  final int wordsTotal;
  final int readingWordsPerDay;
  final int intensiveTextsPerDay;
  final int choicePerDay;

  bool get reviewWeek => unitIds.isEmpty;

  /// A full (80 questions, 180 min) rather than a half mock.
  bool get fullMock => mock != null && !mock!.toLowerCase().contains('yarım');

  factory PlanWeek.fromJson(Map<String, dynamic> j) => PlanWeek(
    week: j['week'] as int,
    phase: j['phase'] as int? ?? 1,
    units: j['units'] as String? ?? '',
    unitIds: ((j['unitIds'] as List?) ?? const []).cast<String>(),
    parallelUnitIds: ((j['parallelUnitIds'] as List?) ?? const []).cast<String>(),
    questionWork: j['questionWork'] as String? ?? '',
    mock: j['mock'] as String?,
    newWords: j['newWords'] as int? ?? 0,
    wordsTotal: j['wordsTotal'] as int? ?? 0,
    readingWordsPerDay: j['readingWordsPerDay'] as int? ?? 0,
    intensiveTextsPerDay: j['intensiveTextsPerDay'] as int? ?? 0,
    choicePerDay: j['choicePerDay'] as int? ?? 0,
  );
}

class PlanPhase {
  const PlanPhase({required this.id, required this.title, required this.from, required this.to});
  final int id;
  final String title;
  final int from;
  final int to;

  factory PlanPhase.fromJson(Map<String, dynamic> j) {
    final weeks = (j['weeks'] as List).cast<int>();
    return PlanPhase(id: j['id'] as int, title: j['title'] as String, from: weeks.first, to: weeks.last);
  }
}

class YearPlan {
  const YearPlan({
    required this.weeks,
    required this.phases,
    required this.shares,
    this.daysPerWeek = 6,
    this.targetSeconds = const {},
  });

  final List<PlanWeek> weeks;
  final List<PlanPhase> phases;

  /// Share of the day per block id (review, lesson, reading, questions,
  /// mistakes).
  final Map<String, double> shares;
  final int daysPerWeek;

  /// Target seconds per question type (shared qtype names).
  final Map<String, int> targetSeconds;

  int get length => weeks.length;

  PlanWeek week(int n) => weeks[(n - 1).clamp(0, weeks.length - 1)];

  PlanPhase? phaseOf(int week) => phases.where((p) => p.from <= week && week <= p.to).firstOrNull;

  factory YearPlan.fromJson(Map<String, dynamic> j) => YearPlan(
    weeks: [for (final w in j['weeks'] as List) PlanWeek.fromJson(w as Map<String, dynamic>)]
      ..sort((a, b) => a.week.compareTo(b.week)),
    phases: [
      for (final p in (j['phases'] as List?) ?? const []) PlanPhase.fromJson(p as Map<String, dynamic>),
    ],
    shares: {
      for (final b in (j['blocks'] as List?) ?? const [])
        (b as Map)['id'] as String: (b['share'] as num).toDouble(),
    },
    daysPerWeek: j['daysPerWeek'] as int? ?? 6,
    targetSeconds: ((j['targetSeconds'] as Map?) ?? const {}).cast<String, int>(),
  );
}

Future<YearPlan?> loadYearPlan(AssetBundle bundle) async {
  try {
    return YearPlan.fromJson(jsonDecode(await bundle.loadString(yearPlanAsset)) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

final yearPlanProvider = FutureProvider<YearPlan?>((ref) => loadYearPlan(rootBundle));
