import 'dart:math';

import 'progress.dart';

/// Per-device counters behind the additive numbers of [Progress] (XP, lesson
/// and answer counts, XP per day, quest counters, node completions, reading
/// words, mistake categories), so two devices that both earned offline add up
/// instead of one overwriting the other (a grow-only counter per device).
///
/// Every additive number is `base + Σ devices`:
/// * [base] is what the progress held before it had a tally (older app
///   versions, older synced documents); it only ever takes the maximum, the
///   way all numbers were merged before;
/// * [devices] holds what each install earned since, keyed by its install id
///   ([walletDevice]); each device only ever writes its own entry.
///
/// Keys are flattened, see [progressCounts].
class ProgressTally {
  const ProgressTally({this.base = const {}, this.devices = const {}});

  final Map<String, int> base;
  final Map<String, Map<String, int>> devices;

  /// A fresh tally (a new or reset progress): nothing earned yet.
  static const empty = ProgressTally();

  /// `base + Σ devices` per key.
  Map<String, int> get totals {
    final out = {...base};
    for (final d in devices.values) {
      for (final e in d.entries) {
        out[e.key] = (out[e.key] ?? 0) + e.value;
      }
    }
    return out;
  }

  /// Sum of every device's entry except [device].
  Map<String, int> othersThan(String? device) {
    final out = <String, int>{};
    for (final d in devices.entries) {
      if (d.key == device) continue;
      for (final e in d.value.entries) {
        out[e.key] = (out[e.key] ?? 0) + e.value;
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {'b': base, 'd': devices};

  static ProgressTally? fromJson(Object? j) {
    if (j is! Map) return null;
    Map<String, int> ints(Object? m) => {
      if (m is Map)
        for (final e in m.entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
    };
    final d = j['d'];
    return ProgressTally(
      base: ints(j['b']),
      devices: {
        if (d is Map)
          for (final e in d.entries) '${e.key}': ints(e.value),
      },
    );
  }
}

/// The additive numbers of [p], flattened to one map: `xp`, `lessons`,
/// `correct`, `answered`, `reading`, and `d:<day>` (XP per day),
/// `c:<day:metric>` (quest counters), `n:<node>` (completions) and
/// `e:<category>` (mistake categories). Zeros are left out.
Map<String, int> progressCounts(Progress p) {
  final out = <String, int>{};
  void put(String k, int v) {
    if (v != 0) out[k] = v;
  }

  put('xp', p.totalXp);
  put('lessons', p.lessonsDone);
  put('correct', p.correct);
  put('answered', p.answered);
  put('reading', p.readingWords);
  p.xpByDay.forEach((k, v) => put('d:$k', v));
  p.counters.forEach((k, v) => put('c:$k', v));
  p.completed.forEach((k, v) => put('n:$k', v));
  p.errorStats.forEach((k, v) => put('e:$k', v));
  return out;
}

/// [p] with its additive numbers replaced by [counts] (see [progressCounts]).
Progress withCounts(Progress p, Map<String, int> counts) {
  Map<String, int> prefixed(String prefix) => {
    for (final e in counts.entries)
      if (e.key.startsWith(prefix)) e.key.substring(prefix.length): e.value,
  };
  return p.copyWith(
    totalXp: counts['xp'] ?? 0,
    lessonsDone: counts['lessons'] ?? 0,
    correct: counts['correct'] ?? 0,
    answered: counts['answered'] ?? 0,
    readingWords: counts['reading'] ?? 0,
    xpByDay: prefixed('d:'),
    counters: prefixed('c:'),
    completed: prefixed('n:'),
    errorStats: prefixed('e:'),
  );
}

/// [p] with a tally: a copy saved before tallies existed gets all its
/// numbers as the base (run when the progress is loaded, before anything new
/// is earned, so new work is this device's own).
Progress migrateTally(Progress p) =>
    p.tally != null ? p : p.copyWith(tally: ProgressTally(base: progressCounts(p)));

/// [p] with [device]'s own tally entry brought up to date: whatever its
/// numbers hold beyond the base and the other devices was earned here.
///
/// Run on every save, so an upload always carries this device's latest
/// share. Keys no longer present (pruned quest counters) leave the tally.
Progress stampTally(Progress p, String device) {
  final counts = progressCounts(p);
  final t = p.tally ?? ProgressTally(base: counts); // older copy: all of it is base
  Map<String, int> keep(Map<String, int> m) => {
    for (final e in m.entries)
      if (counts.containsKey(e.key) && e.value > 0) e.key: e.value,
  };
  final base = keep(t.base);
  final devices = <String, Map<String, int>>{
    for (final d in t.devices.entries)
      if (d.key != device && keep(d.value).isNotEmpty) d.key: keep(d.value),
  };
  final others = ProgressTally(devices: devices).othersThan(null);
  final mine = <String, int>{
    for (final e in counts.entries)
      if (e.value - (base[e.key] ?? 0) - (others[e.key] ?? 0) case final v when v > 0) e.key: v,
  };
  if (mine.isNotEmpty) devices[device] = mine;
  return p.copyWith(tally: ProgressTally(base: base, devices: devices));
}

/// Adds two copies' additive numbers without counting anything twice:
/// the base takes the maximum, each device's entry its maximum (a device's
/// own counter only grows), and the numbers are `base + Σ devices`.
///
/// A copy without a tally (an older app version, an old document) counts as
/// base only; what the other copy's devices already account for is taken
/// out of it first, so the result is never below either copy (the old
/// "maximum" merge) and nothing is added twice.
({Map<String, int> counts, ProgressTally tally}) mergeTallies(Progress a, Progress b) {
  ProgressTally norm(Progress p, Progress other) {
    if (p.tally case final t?) return t;
    final counts = progressCounts(p);
    final od = other.tally?.othersThan(null) ?? const <String, int>{};
    return ProgressTally(
      base: {
        for (final e in counts.entries)
          if (e.value - (od[e.key] ?? 0) case final v when v > 0) e.key: v,
      },
    );
  }

  final ta = norm(a, b), tb = norm(b, a);
  Map<String, int> maxMap(Map<String, int> x, Map<String, int> y) => {
    ...x,
    for (final e in y.entries) e.key: max(e.value, x[e.key] ?? 0),
  };
  final tally = ProgressTally(
    base: maxMap(ta.base, tb.base),
    devices: {
      for (final d in {...ta.devices.keys, ...tb.devices.keys})
        d: maxMap(ta.devices[d] ?? const {}, tb.devices[d] ?? const {}),
    },
  );
  return (counts: tally.totals, tally: tally);
}
