import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/placement.dart' show LearnReason;
import '../data/progress.dart';

/// "Hedefin ne?": what the learner wants English for. It drives the goal
/// card on the home screen, the paywall copy and the YDS countdown plan.
enum GoalKind {
  exam('📝', 'YDS/YÖKDİL sınavı', 'Sınav tarihine göre günlük plan'),
  interview('💼', 'İş görüşmesi', 'Mülakatına hazır gir'),
  speaking('🗣️', 'Konuşmak / seyahat', 'Günlük konuşma ve yolculuk'),
  general('🎒', 'Okul / genel', 'Derslerim ve kendim için');

  const GoalKind(this.emoji, this.title, this.subtitle);
  final String emoji;
  final String title;
  final String subtitle;

  static GoalKind byName(String? name) => GoalKind.values.where((k) => k.name == name).firstOrNull ?? general;

  /// The onboarding's "Neden İngilizce öğreniyorsun?" answer this goal
  /// preselects (the learner can still change it).
  LearnReason get reason => switch (this) {
    exam => LearnReason.academic,
    interview => LearnReason.work,
    speaking => LearnReason.general,
    general => LearnReason.general,
  };
}

/// Exams of the [GoalKind.exam] goal.
enum GoalExam {
  yds('YDS'),
  yokdil('YÖKDİL');

  const GoalExam(this.label);
  final String label;

  static GoalExam byName(String? name) => GoalExam.values.where((e) => e.name == name).firstOrNull ?? yds;
}

/// The learner's goal, kept in [Progress] and synced (the later edit wins).
class LearnGoal {
  const LearnGoal({required this.kind, this.exam = GoalExam.yds, this.examDate, this.at = 0});

  final GoalKind kind;
  final GoalExam exam;

  /// Exam day ("2027-03-14"), only for [GoalKind.exam]; optional.
  final String? examDate;

  /// When it was set (ms since epoch), for merging two devices.
  final int at;

  DateTime? get examDay => examDate == null ? null : DateTime.tryParse(examDate!);

  /// Whole days from [now]'s day to the exam day (0 on the day itself,
  /// negative once it passed). Null without an exam date.
  int? daysLeft(DateTime now) {
    final d = examDay;
    if (kind != GoalKind.exam || d == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(d.year, d.month, d.day).difference(today).inDays;
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    if (kind == GoalKind.exam) 'exam': exam.name,
    'examDate': ?(kind == GoalKind.exam ? examDate : null),
    'at': at,
  };

  factory LearnGoal.fromJson(Map<String, dynamic> j) => LearnGoal(
    kind: GoalKind.byName(j['kind'] as String?),
    exam: GoalExam.byName(j['exam'] as String?),
    examDate: j['examDate'] as String?,
    at: (j['at'] as num?)?.toInt() ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is LearnGoal && other.kind == kind && other.exam == exam && other.examDate == examDate && other.at == at;

  @override
  int get hashCode => Object.hash(kind, exam, examDate, at);
}

/// Day key ("2027-03-14") of [d].
String goalDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The learner's goal; null until one was chosen.
final learnGoalProvider = Provider<LearnGoal?>((ref) => ref.watch(progressProvider.select((p) => p.learnGoal)));
