import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A timed mock exam in progress, kept on the phone so the clock runs
/// against a fixed end time: suspending the app, a phone call or the system
/// killing the app does not give extra time, and reopening the same mock
/// continues it (same questions, answers kept) until the end time.
class MockAttempt {
  const MockAttempt({
    required this.questionIds,
    required this.startedAt,
    required this.deadline,
    this.answers = const {},
    this.pos = 0,
  });

  final List<String> questionIds;
  final DateTime startedAt;
  final DateTime deadline;

  /// Chosen option per question index.
  final Map<int, int> answers;
  final int pos;

  MockAttempt copyWith({Map<int, int>? answers, int? pos}) => MockAttempt(
    questionIds: questionIds,
    startedAt: startedAt,
    deadline: deadline,
    answers: answers ?? this.answers,
    pos: pos ?? this.pos,
  );

  Map<String, dynamic> toJson() => {
    'q': questionIds,
    's': startedAt.millisecondsSinceEpoch,
    'd': deadline.millisecondsSinceEpoch,
    'a': {for (final e in answers.entries) '${e.key}': e.value},
    'p': pos,
  };

  static MockAttempt? fromJson(Object? j) {
    if (j is! Map) return null;
    final q = j['q'], s = j['s'], d = j['d'];
    if (q is! List || s is! int || d is! int) return null;
    final a = j['a'];
    return MockAttempt(
      questionIds: [for (final x in q) '$x'],
      startedAt: DateTime.fromMillisecondsSinceEpoch(s),
      deadline: DateTime.fromMillisecondsSinceEpoch(d),
      answers: {
        if (a is Map)
          for (final e in a.entries)
            if (int.tryParse('${e.key}') case final k? when e.value is int) k: e.value as int,
      },
      pos: j['p'] is int ? j['p'] as int : 0,
    );
  }
}

/// Whole seconds left until [deadline] (rounded up, never negative).
int secondsLeft(DateTime deadline, DateTime now) =>
    max(0, (deadline.difference(now).inMilliseconds / 1000).ceil());

/// Mock attempts in progress, one per mock (path node, pack mock or exam).
class MockAttempts {
  MockAttempts(this._prefs);
  final SharedPreferences _prefs;

  static String _key(String id) => 'mock_attempt_v1:$id';

  /// The saved attempt of mock [id], if it was for the same [questionIds]
  /// (a mini mock draws new questions each time: then there is none).
  MockAttempt? load(String id, List<String> questionIds) {
    final raw = _prefs.getString(_key(id));
    if (raw == null) return null;
    try {
      final a = MockAttempt.fromJson(jsonDecode(raw));
      if (a == null || a.questionIds.join('\n') != questionIds.join('\n')) return null;
      return a;
    } catch (_) {
      return null;
    }
  }

  void save(String id, MockAttempt a) => _prefs.setString(_key(id), jsonEncode(a.toJson()));

  void clear(String id) => _prefs.remove(_key(id));
}
