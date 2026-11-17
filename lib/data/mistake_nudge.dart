import 'package:shared_preferences/shared_preferences.dart';

/// Day ("yyyy-mm-dd") the "Bunlar senin hataların" reminder was last shown.
const mistakeNudgeDayKey = 'mistake_nudge_day_v1';

/// Questions the reminder offers at once (the rest wait for the notebook).
const mistakeNudgeSize = 10;

/// Questions named on the reminder card.
const mistakeNudgePreview = 3;

/// Whether the reminder shows after a lesson today: some notebook questions
/// are due (their 1, 3, 7 or 21 days are up) and it has not shown today.
bool mistakeNudgeDue(SharedPreferences prefs, {required String today, required int due}) =>
    due > 0 && prefs.getString(mistakeNudgeDayKey) != today;

/// Remembers that the reminder showed on [today]: at most once a day.
void markMistakeNudge(SharedPreferences prefs, String today) => prefs.setString(mistakeNudgeDayKey, today);
