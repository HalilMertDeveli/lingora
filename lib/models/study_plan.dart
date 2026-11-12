/// The learner's daily study plan settings ("Bugün"), kept in Progress and
/// synced. Weeks advance by steps, not by the calendar: a week moves on when
/// its targets are met, so missed days never pile up.
class StudyPlan {
  const StudyPlan({
    required this.exam,
    required this.week,
    required this.weekStart,
    required this.dailyMinutes,
    required this.startDay,
    this.weekWordsBase = 0,
    this.place = '',
    this.lightDay = DateTime.sunday,
    this.mockDay = DateTime.saturday,
    this.freezeWeek,
  });

  /// yds, yokdil_fen, yokdil_saglik, yokdil_sosyal.
  final String exam;

  /// Current week of the year plan, 1–52.
  final int week;

  /// Day the current week began.
  final String weekStart;

  /// Words started before this week (to count the week's new words).
  final int weekWordsBase;

  /// Daily study time, in minutes.
  final int dailyMinutes;
  final String startDay;

  /// Where the learner studies (implementation intention, "Mutfak masası").
  final String place;

  /// Day of the week (DateTime.monday…sunday) that is a light day.
  final int lightDay;

  /// Day of the week for mock exams in mock weeks.
  final int mockDay;

  /// Monday (day key) of the week a streak freeze was last used.
  final String? freezeWeek;

  StudyPlan copyWith({
    String? exam,
    int? week,
    String? weekStart,
    int? weekWordsBase,
    int? dailyMinutes,
    String? place,
    int? lightDay,
    int? mockDay,
    String? freezeWeek,
  }) => StudyPlan(
    exam: exam ?? this.exam,
    week: week ?? this.week,
    weekStart: weekStart ?? this.weekStart,
    weekWordsBase: weekWordsBase ?? this.weekWordsBase,
    dailyMinutes: dailyMinutes ?? this.dailyMinutes,
    startDay: startDay,
    place: place ?? this.place,
    lightDay: lightDay ?? this.lightDay,
    mockDay: mockDay ?? this.mockDay,
    freezeWeek: freezeWeek ?? this.freezeWeek,
  );

  Map<String, dynamic> toJson() => {
    'exam': exam,
    'week': week,
    'weekStart': weekStart,
    'weekWordsBase': weekWordsBase,
    'dailyMinutes': dailyMinutes,
    'startDay': startDay,
    'place': place,
    'lightDay': lightDay,
    'mockDay': mockDay,
    'freezeWeek': ?freezeWeek,
  };

  factory StudyPlan.fromJson(Map<String, dynamic> j) => StudyPlan(
    exam: j['exam'] as String? ?? 'yds',
    week: j['week'] as int? ?? 1,
    weekStart: j['weekStart'] as String,
    weekWordsBase: j['weekWordsBase'] as int? ?? 0,
    dailyMinutes: j['dailyMinutes'] as int? ?? 180,
    startDay: j['startDay'] as String? ?? j['weekStart'] as String,
    place: j['place'] as String? ?? '',
    lightDay: j['lightDay'] as int? ?? DateTime.sunday,
    mockDay: j['mockDay'] as int? ?? DateTime.saturday,
    freezeWeek: j['freezeWeek'] as String?,
  );
}

/// Exams the plan prepares for.
const planExams = {
  'yds': 'YDS',
  'yokdil_fen': 'YÖKDİL Fen',
  'yokdil_saglik': 'YÖKDİL Sağlık',
  'yokdil_sosyal': 'YÖKDİL Sosyal',
};
