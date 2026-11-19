import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tr_errors.dart';
import '../data/progress.dart';
import 'error_insights.dart';
import 'study_state.dart';
import 'tr_error_log.dart';

/// Haftalık koç mesajı: every Monday a short summary of the week that just
/// ended, built on the device from the answer log and the hata dedektörü
/// history (no AI: the numbers are the learner's own, and the message is
/// a few fixed Turkish sentences, so it costs nothing and cannot invent).

/// Graded answers the reviewed week needs before there is a message.
const minAnswersForCoach = 10;

/// Monday (as a `dayKey`) of the week that holds [d].
String mondayOf(DateTime d) => dayKey(DateTime(d.year, d.month, d.day - (d.weekday - 1)));

/// One of the week's most frequent mistakes.
class CoachPattern {
  const CoachPattern({
    required this.label,
    required this.wrong,
    this.answered,
    this.kind = CoachPatternKind.topic,
  });
  final String label;
  final int wrong;

  /// Questions of this kind answered in the week (null for writing habits).
  final int? answered;
  final CoachPatternKind kind;

  String get detail => answered == null ? '$wrong kez yazarken' : '$answered soruda $wrong yanlış';
}

enum CoachPatternKind { topic, type, habit }

class WeeklyCoachMessage {
  const WeeklyCoachMessage({
    required this.weekKey,
    required this.from,
    required this.to,
    required this.answered,
    required this.correct,
    required this.activeDays,
    required this.top,
    this.improved,
    this.focus,
  });

  /// Monday of the current week: the message's id.
  final String weekKey;

  /// First and last day (`dayKey`) of the week it is about.
  final String from;
  final String to;
  final int answered;
  final int correct;
  final int activeDays;

  /// The week's most frequent mistakes, at most three.
  final List<CoachPattern> top;

  /// What got better than the week before, in one Turkish sentence.
  final String? improved;

  /// One focus suggestion; drillable ones start with one tap.
  final FocusItem? focus;
}

bool _inRange(String day, String from, String to) => day.compareTo(from) >= 0 && day.compareTo(to) <= 0;

/// The message for the week of [now] (about the seven days before its
/// Monday), or null when that week had fewer than [minAnswersForCoach]
/// graded answers.
WeeklyCoachMessage? buildWeeklyCoach({
  required List<AnswerLog> log,
  required Map<String, String> titles,
  required TrErrorLog trLog,
  required DateTime now,
}) {
  final monday = mondayOf(now);
  final from = daysBefore(monday, 7), to = daysBefore(monday, 1);
  final prevFrom = daysBefore(monday, 14), prevTo = daysBefore(monday, 8);
  final week = [
    for (final a in log)
      if (_inRange(a.day, from, to)) a,
  ];
  if (week.length < minAnswersForCoach) return null;
  final prev = [
    for (final a in log)
      if (_inRange(a.day, prevFrom, prevTo)) a,
  ];
  // Types of the open course only, as in the analysis screen.
  bool ofCourse(AnswerLog a) => a.unitId == null || titles.containsKey(a.unitId);

  final topics = topicBuckets(week, titles);
  final types = typeBuckets(week.where(ofCourse));
  final habits = <TrErrorCategory, int>{};
  for (final e in trLog.events) {
    if (_inRange(e.day, from, to)) habits[e.category] = (habits[e.category] ?? 0) + 1;
  }

  // At most two of a kind, so the three are not one topic seen three ways.
  final candidates = [
    for (final b in topics.values)
      if (b.wrong > 0) CoachPattern(label: b.label, wrong: b.wrong, answered: b.answered),
    for (final b in types.values)
      if (b.wrong > 0)
        CoachPattern(label: b.label, wrong: b.wrong, answered: b.answered, kind: CoachPatternKind.type),
    for (final e in habits.entries)
      CoachPattern(label: e.key.label, wrong: e.value, kind: CoachPatternKind.habit),
  ]..sort((a, b) => b.wrong != a.wrong ? b.wrong.compareTo(a.wrong) : a.label.compareTo(b.label));
  final top = <CoachPattern>[];
  final perKind = <CoachPatternKind, int>{};
  for (final c in candidates) {
    if ((perKind[c.kind] ?? 0) >= 2) continue;
    perKind[c.kind] = (perKind[c.kind] ?? 0) + 1;
    top.add(c);
    if (top.length == 3) break;
  }

  final focusItems = weeklyFocus(
    weakest(topics.values, minAnswers: 3),
    weakest(types.values, minAnswers: 3),
    trPatterns(
      const {},
      TrErrorLog(
        events: [
          for (final e in trLog.events)
            if (_inRange(e.day, from, to)) e,
        ],
      ),
    ),
  );

  return WeeklyCoachMessage(
    weekKey: monday,
    from: from,
    to: to,
    answered: week.length,
    correct: week.where((a) => a.correct).length,
    activeDays: {for (final a in week) a.day}.length,
    top: top,
    improved: _improved(week, prev, titles, ofCourse),
    focus: focusItems.where((f) => f.drillable).firstOrNull ?? focusItems.firstOrNull,
  );
}

/// The biggest real improvement over the week before, told with the
/// learner's own counts; null when nothing improved clearly.
String? _improved(
  List<AnswerLog> week,
  List<AnswerLog> prev,
  Map<String, String> titles,
  bool Function(AnswerLog) ofCourse,
) {
  if (prev.isEmpty) return null;
  Bucket? bestNow, bestBefore;
  var bestDrop = 0.0;
  void compare(Map<String, Bucket> before, Map<String, Bucket> now) {
    for (final e in before.entries) {
      final n = now[e.key];
      final b = e.value;
      if (n == null || b.answered < 4 || n.answered < 4 || b.wrong == 0) continue;
      final drop = (b.errorRate - n.errorRate) / b.errorRate;
      if (drop >= minImprovement && drop > bestDrop) {
        bestDrop = drop;
        bestNow = n;
        bestBefore = b;
      }
    }
  }

  compare(topicBuckets(prev, titles), topicBuckets(week, titles));
  compare(typeBuckets(prev.where(ofCourse)), typeBuckets(week.where(ofCourse)));
  if (bestNow case final n?) {
    final b = bestBefore!;
    return '${n.label}: geçen hafta ${b.answered} soruda ${b.wrong} yanlış, bu hafta ${n.answered} soruda ${n.wrong} yanlış.';
  }
  final accNow = week.where((a) => a.correct).length / week.length;
  final accBefore = prev.where((a) => a.correct).length / prev.length;
  if (prev.length >= minAnswersForCoach && accNow - accBefore >= 0.05) {
    return 'Genel doğruluğun arttı: geçen hafta ${prev.length} soruda ${prev.where((a) => a.correct).length} doğru, '
        'bu hafta ${week.length} soruda ${week.where((a) => a.correct).length} doğru.';
  }
  return null;
}

/// Monday (`weekKey`) of the last coach message the learner closed.
class WeeklyCoachSeen extends Notifier<String?> {
  static const key = 'weekly_coach_seen_v1';

  @override
  String? build() => ref.read(prefsProvider).getString(key);

  void dismiss(String weekKey) {
    ref.read(prefsProvider).setString(key, weekKey);
    state = weekKey;
  }
}

final weeklyCoachSeenProvider = NotifierProvider<WeeklyCoachSeen, String?>(WeeklyCoachSeen.new);

/// The Monday notification for the coach message (on by default; it only
/// fires when daily reminders are on, see `planNotifications`).
class WeeklyCoachNotify extends Notifier<bool> {
  static const key = 'weekly_coach_notify_v1';

  @override
  bool build() => ref.read(prefsProvider).getBool(key) ?? true;

  void set(bool on) {
    ref.read(prefsProvider).setBool(key, on);
    state = on;
  }
}

final weeklyCoachNotifyProvider = NotifierProvider<WeeklyCoachNotify, bool>(WeeklyCoachNotify.new);
