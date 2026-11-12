import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';

/// Study data kept on this device only, next to [Progress]: a log of
/// answered questions (type, topic, time) for the error notebook, the mock
/// report and the score estimate. It is large and only feeds statistics,
/// so it is not synced; everything the schedule depends on lives in
/// [Progress].

/// Answers kept in the log (newest win).
const maxAnswerLog = 3000;

/// One answered question.
class AnswerLog {
  const AnswerLog({
    required this.key,
    required this.day,
    required this.correct,
    required this.seconds,
    this.type,
    this.unitId,
    this.source = 'lesson',
    this.blank = false,
  });

  /// Item key ("nodeId#index") or exam question id.
  final String key;
  final String day;
  final bool correct;
  final int seconds;

  /// QType name for exam-style questions, else the exercise type name.
  final String? type;

  /// Path unit of the question (its topic), if any.
  final String? unitId;

  /// Where it was answered: lesson, test, practice, `mock:<id>@<start>`...
  final String source;

  /// Left blank in a mock exam.
  final bool blank;

  bool get fromMock => source.startsWith('mock:');

  Map<String, dynamic> toJson() => {
    'k': key,
    'day': day,
    'ok': correct,
    'sec': seconds,
    't': ?type,
    'u': ?unitId,
    'src': source,
    if (blank) 'b': true,
  };

  factory AnswerLog.fromJson(Map<String, dynamic> j) => AnswerLog(
    key: j['k'] as String,
    day: j['day'] as String,
    correct: j['ok'] as bool,
    seconds: j['sec'] as int? ?? 0,
    type: j['t'] as String?,
    unitId: j['u'] as String?,
    source: j['src'] as String? ?? 'lesson',
    blank: j['b'] as bool? ?? false,
  );
}

class StudyLog {
  const StudyLog({this.answers = const []});

  /// Oldest first.
  final List<AnswerLog> answers;

  Map<String, dynamic> toJson() => {
    'answers': [for (final a in answers) a.toJson()],
  };

  factory StudyLog.fromJson(Map<String, dynamic> j) => StudyLog(
    answers: [
      for (final a in (j['answers'] as List?) ?? const []) AnswerLog.fromJson(a as Map<String, dynamic>),
    ],
  );
}

class StudyLogNotifier extends Notifier<StudyLog> {
  static const _key = 'study_log_v1';

  @override
  StudyLog build() {
    final raw = ref.read(prefsProvider).getString(_key);
    if (raw == null) return const StudyLog();
    try {
      return StudyLog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const StudyLog();
    }
  }

  void add(Iterable<AnswerLog> entries) {
    if (entries.isEmpty) return;
    var list = [...state.answers, ...entries];
    if (list.length > maxAnswerLog) list = list.sublist(list.length - maxAnswerLog);
    state = StudyLog(answers: list);
    ref.read(prefsProvider).setString(_key, jsonEncode(state.toJson()));
  }
}

final studyLogProvider = NotifierProvider<StudyLogNotifier, StudyLog>(StudyLogNotifier.new);
