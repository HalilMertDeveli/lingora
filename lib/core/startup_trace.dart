import 'dart:developer';

import 'package:flutter/foundation.dart';

/// Cold-start timeline: `main()` → prefs → first frame → course → path.
///
/// Each [mark] adds a Timeline instant event (visible in DevTools in profile
/// builds) and, with `--dart-define=LINGORA_STARTUP_TRACE=true`, prints a
/// `STARTUP <name> <ms>` line to logcat with the time since `main()` started.
/// Costs nothing measurable otherwise.
abstract final class StartupTrace {
  static const _print = bool.fromEnvironment('LINGORA_STARTUP_TRACE');

  static final Stopwatch _clock = Stopwatch()..start();
  static final _seen = <String>{};

  /// Starts the clock (first line of `main()`).
  static void start() {
    _clock
      ..reset()
      ..start();
    mark('main');
  }

  /// Milliseconds since [start].
  static int get elapsedMs => _clock.elapsedMilliseconds;

  /// Records [name] once; later calls with the same name are ignored.
  static void mark(String name) {
    if (!_seen.add(name)) return;
    if (!kReleaseMode) Timeline.instantSync('startup:$name');
    if (_print) debugPrint('STARTUP $name ${_clock.elapsedMilliseconds}');
  }
}
