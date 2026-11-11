import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Suggests a short break after a run of lessons in one app session:
/// every [lessonsPerBreak] lessons or [timePerBreak] of lesson time,
/// whichever comes first. Kept in memory only; a fresh app start resets it.
class BreakTracker {
  BreakTracker({this.lessonsPerBreak = 3, this.timePerBreak = const Duration(minutes: 20)});
  final int lessonsPerBreak;
  final Duration timePerBreak;

  int _lessons = 0;
  Duration _time = Duration.zero;

  /// Records a finished lesson; true when it is time to suggest a break
  /// (the counters then start again).
  bool recordLesson(Duration duration) {
    _lessons++;
    _time += duration;
    if (_lessons < lessonsPerBreak && _time < timePerBreak) return false;
    _lessons = 0;
    _time = Duration.zero;
    return true;
  }
}

final breakTrackerProvider = Provider<BreakTracker>((ref) => BreakTracker());
