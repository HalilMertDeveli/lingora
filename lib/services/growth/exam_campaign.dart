import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress.dart';
import '../../goals/learn_goal.dart';
import '../firebase/firebase_providers.dart';

/// Exam-season campaigns ("Sınava kadar Premium"): a few weeks before YDS,
/// YÖKDİL or LGS, learners aiming at that exam see a countdown and a soft
/// Premium card in Öğren. Same Play products and prices; only the message
/// changes (plus an optional Play promo offer id, docs/buyume-kampanya.md).
///
/// The schedule lives in Firestore `config/examCampaigns` so the owner can
/// change dates without a release; [defaultExamCampaigns] is used when the
/// doc is missing or unreachable.

/// Paywall placement (analytics) of the campaign card.
const examSeasonPlacement = 'exam_season';

class ExamCampaign {
  const ExamCampaign({
    required this.id,
    required this.label,
    required this.dates,
    this.weeksBefore = 8,
    this.enabled = true,
    this.promoOfferId,
  });

  /// `yds`, `yokdil` or `lgs`.
  final String id;
  final String label;

  /// Exam days ("2027-03-28"), any order.
  final List<String> dates;

  /// How many weeks before an exam day the campaign starts.
  final int weeksBefore;
  final bool enabled;

  /// Optional Google Play promo offer id for the base plans (placeholder:
  /// set it in the config doc once the offer exists in Play Console).
  final String? promoOfferId;

  factory ExamCampaign.fromJson(String id, Map<String, dynamic> j, {ExamCampaign? fallback}) => ExamCampaign(
    id: id,
    label: j['label'] as String? ?? fallback?.label ?? id.toUpperCase(),
    dates: [
      for (final d in (j['dates'] as List<dynamic>? ?? fallback?.dates ?? const []))
        if (d is String && DateTime.tryParse(d) != null) d,
    ],
    weeksBefore: ((j['weeksBefore'] as num?)?.toInt() ?? fallback?.weeksBefore ?? 8).clamp(1, 26),
    enabled: j['enabled'] as bool? ?? fallback?.enabled ?? true,
    promoOfferId: switch (j['promoOfferId']) {
      final String s when s.trim().isNotEmpty => s.trim(),
      _ => null,
    },
  );

  Map<String, dynamic> toJson() => {
    'label': label,
    'dates': dates,
    'weeksBefore': weeksBefore,
    'enabled': enabled,
    'promoOfferId': ?promoOfferId,
  };
}

/// 2027 dates from the ÖSYM 2027 calendar (28 Oct 2026) and MEB's 2027 exam
/// calendar. Update `config/examCampaigns` when they change.
const defaultExamCampaigns = <String, ExamCampaign>{
  'yds': ExamCampaign(id: 'yds', label: 'YDS', dates: ['2027-03-28', '2027-11-21']),
  'yokdil': ExamCampaign(id: 'yokdil', label: 'YÖKDİL', dates: ['2027-02-28', '2027-07-25']),
  'lgs': ExamCampaign(id: 'lgs', label: 'LGS', dates: ['2027-06-13']),
};

/// Parses `config/examCampaigns` ({ exams: { yds: {...}, ... } }); unknown
/// exams are ignored, missing ones keep their defaults.
Map<String, ExamCampaign> parseExamCampaigns(Map<String, dynamic>? doc) {
  final exams = doc?['exams'];
  if (exams is! Map) return defaultExamCampaigns;
  return {
    for (final MapEntry(:key, :value) in defaultExamCampaigns.entries)
      key: switch (exams[key]) {
        final Map<dynamic, dynamic> m => ExamCampaign.fromJson(key, m.cast<String, dynamic>(), fallback: value),
        _ => value,
      },
  };
}

/// A running campaign for the learner.
class ExamSeasonWindow {
  const ExamSeasonWindow({required this.campaign, required this.examDay, required this.daysLeft});
  final ExamCampaign campaign;
  final DateTime examDay;

  /// Whole days until the exam (1 = tomorrow).
  final int daysLeft;

  /// "YDS'ye 41 gün kaldı" with the right Turkish suffix.
  String get countdown => '${campaign.label}${_dative(campaign.label)} $daysLeft gün kaldı';
}

String _dative(String label) => switch (label) {
  'YÖKDİL' => "'e",
  'LGS' => "'ye",
  _ => "'ye",
};

/// The exam campaign that fits the learner: the "Hedefin ne?" exam goal,
/// otherwise the exam track (LGS / YDS) they study.
String? campaignExamFor({LearnGoal? goal, required String trackId}) {
  if (goal?.kind == GoalKind.exam) return goal!.exam.name;
  return switch (trackId) {
    'lgs' => 'lgs',
    'yds' => 'yds',
    _ => null,
  };
}

/// The window of [examId] at [now]: the next exam day within
/// `weeksBefore` weeks (exam day itself excluded). Null outside it.
ExamSeasonWindow? examSeasonWindow(Map<String, ExamCampaign> schedule, String? examId, DateTime now) {
  final c = examId == null ? null : schedule[examId];
  if (c == null || !c.enabled) return null;
  final today = DateTime(now.year, now.month, now.day);
  ExamSeasonWindow? best;
  for (final raw in c.dates) {
    final d = DateTime.tryParse(raw);
    if (d == null) continue;
    final left = DateTime(d.year, d.month, d.day).difference(today).inDays;
    if (left < 1 || left > c.weeksBefore * 7) continue;
    if (best == null || left < best.daysLeft) {
      best = ExamSeasonWindow(campaign: c, examDay: DateTime(d.year, d.month, d.day), daysLeft: left);
    }
  }
  return best;
}

/// The campaign schedule: Firestore `config/examCampaigns`, the last copy
/// cached on the device, or [defaultExamCampaigns].
final examCampaignScheduleProvider = FutureProvider<Map<String, ExamCampaign>>((ref) async {
  const cacheKey = 'growth.exam_campaigns';
  final prefs = ref.read(prefsProvider);
  Map<String, ExamCampaign> cached() {
    final raw = prefs.getString(cacheKey);
    if (raw == null) return defaultExamCampaigns;
    try {
      return parseExamCampaigns(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return defaultExamCampaigns;
    }
  }

  final db = ref.watch(firestoreProvider);
  if (db == null || ref.watch(currentUidProvider) == null) return cached();
  try {
    final snap = await db.doc('config/examCampaigns').get().timeout(const Duration(seconds: 6));
    final data = snap.data();
    if (data == null) return cached();
    final parsed = parseExamCampaigns(data);
    prefs.setString(
      cacheKey,
      jsonEncode({
        'exams': {for (final e in parsed.entries) e.key: e.value.toJson()},
      }),
    );
    return parsed;
  } on Object {
    return cached();
  }
});

/// The learner's running campaign window, or null.
final examSeasonProvider = Provider<ExamSeasonWindow?>((ref) {
  final schedule = ref.watch(examCampaignScheduleProvider).value ?? defaultExamCampaigns;
  final examId = campaignExamFor(
    goal: ref.watch(learnGoalProvider),
    trackId: ref.watch(progressProvider.select((p) => p.trackId)),
  );
  return examSeasonWindow(schedule, examId, ref.watch(clockProvider)());
});
