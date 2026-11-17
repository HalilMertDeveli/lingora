import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tr_errors.dart';
import '../data/progress.dart';

/// Türk hata dedektörü history kept on this device only (like the study
/// log): every mistake it found, with the learner's own sentence and its
/// fix, plus how many texts it checked per day. The detailed error analysis
/// shows the learner's own examples from it and measures, per category,
/// whether a mistake is getting rarer (mistakes per check, so writing more
/// does not look like getting worse).
///
/// [Progress.errorStats] keeps the synced all-time counts; this log only
/// feeds the analysis.

/// Mistakes kept (newest win).
const maxTrErrorEvents = 400;

/// Days of check counts kept.
const keepCheckDays = 120;

/// One mistake the hata dedektörü found.
class TrErrorEvent {
  const TrErrorEvent({
    required this.day,
    required this.category,
    required this.wrong,
    required this.corrected,
    this.text,
    this.why,
  });

  final String day;
  final TrErrorCategory category;

  /// The wrong fragment as the learner wrote it.
  final String wrong;

  /// The whole sentence, corrected.
  final String corrected;

  /// The learner's whole sentence, if known.
  final String? text;

  /// The rule's own Turkish explanation.
  final String? why;

  Map<String, dynamic> toJson() => {
    'd': day,
    'c': category.name,
    'w': wrong,
    'f': corrected,
    't': ?text,
    'y': ?why,
  };

  static TrErrorEvent? fromJson(Map<String, dynamic> j) {
    final c = TrErrorCategory.byName(j['c'] as String? ?? '');
    if (c == null) return null;
    return TrErrorEvent(
      day: j['d'] as String,
      category: c,
      wrong: j['w'] as String? ?? '',
      corrected: j['f'] as String? ?? '',
      text: j['t'] as String?,
      why: j['y'] as String?,
    );
  }
}

class TrErrorLog {
  const TrErrorLog({this.events = const [], this.checks = const {}});

  /// Oldest first.
  final List<TrErrorEvent> events;

  /// Texts checked per day (with or without mistakes).
  final Map<String, int> checks;

  Map<String, dynamic> toJson() => {
    'e': [for (final e in events) e.toJson()],
    'k': checks,
  };

  factory TrErrorLog.fromJson(Map<String, dynamic> j) => TrErrorLog(
    events: [
      for (final e in (j['e'] as List?) ?? const []) ?TrErrorEvent.fromJson(e as Map<String, dynamic>),
    ],
    checks: (j['k'] as Map?)?.cast<String, int>() ?? const {},
  );

  /// [this] after a check of [text] on [day] that found [errors] (each
  /// category once per check, like [Progress.errorStats]).
  TrErrorLog record(String day, Iterable<TrError> errors, {String? text}) {
    final seen = <TrErrorCategory>{};
    final added = [
      for (final e in errors)
        if (seen.add(e.category))
          TrErrorEvent(
            day: day,
            category: e.category,
            wrong: e.wrong,
            corrected: e.corrected,
            text: text == null || text.trim().isEmpty ? null : text.trim(),
            why: e.explanation,
          ),
    ];
    var list = [...events, ...added];
    if (list.length > maxTrErrorEvents) list = list.sublist(list.length - maxTrErrorEvents);
    final keys = {...checks.keys, day}.toList()..sort();
    final keep = keys.sublist(keys.length > keepCheckDays ? keys.length - keepCheckDays : 0).toSet();
    return TrErrorLog(events: list, checks: {for (final k in keep) k: (checks[k] ?? 0) + (k == day ? 1 : 0)});
  }
}

class TrErrorLogNotifier extends Notifier<TrErrorLog> {
  static const _key = 'tr_error_log_v1';

  @override
  TrErrorLog build() {
    final raw = ref.read(prefsProvider).getString(_key);
    if (raw == null) return const TrErrorLog();
    try {
      return TrErrorLog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const TrErrorLog();
    }
  }

  void record(Iterable<TrError> errors, {String? text}) {
    state = state.record(dayKey(ref.read(clockProvider)()), errors, text: text);
    ref.read(prefsProvider).setString(_key, jsonEncode(state.toJson()));
  }
}

final trErrorLogProvider = NotifierProvider<TrErrorLogNotifier, TrErrorLog>(TrErrorLogNotifier.new);
