import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

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

/// Pause after the first frame before start-up work nothing on screen needs
/// (Firebase, scheduling reminders). On Android Flutter runs Dart on the
/// main thread, so a plugin's main-thread work stalls the path while it is
/// being drawn.
const startupSettleDelay = Duration(milliseconds: 1500);

/// Runs [work] once the first frame is on screen and [delay] has passed.
Future<T> afterFirstFrames<T>(Future<T> Function() work, {Duration delay = startupSettleDelay}) async {
  await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
  await Future<void>.delayed(delay);
  return work();
}
