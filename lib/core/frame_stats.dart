import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Frame-time logging for performance work, off unless the app is built with
/// `--dart-define=LINGORA_FRAME_STATS=true`. Every 30 frames it prints the
/// average and slowest build (UI thread) and raster (GPU thread) times and how
/// many frames missed a 16 ms budget, e.g.
/// `FRAMES n=120 build avg 4.1 max 9.8 | raster avg 6.0 max 21.3 | janky 3`.
class FrameStats {
  static const enabled = bool.fromEnvironment('LINGORA_FRAME_STATS');

  static final _build = <double>[];
  static final _raster = <double>[];

  static void start() {
    if (!enabled) return;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _build.add(t.buildDuration.inMicroseconds / 1000);
      _raster.add(t.rasterDuration.inMicroseconds / 1000);
    }
    if (_build.length < 30) return;
    String stats(List<double> v) {
      final avg = v.reduce((a, b) => a + b) / v.length;
      final max = v.reduce((a, b) => a > b ? a : b);
      return 'avg ${avg.toStringAsFixed(1)} max ${max.toStringAsFixed(1)}';
    }

    var janky = 0;
    for (var i = 0; i < _build.length; i++) {
      if (_build[i] > 16 || _raster[i] > 16) janky++;
    }
    debugPrint('FRAMES n=${_build.length} build ${stats(_build)} | raster ${stats(_raster)} | janky $janky');
    _build.clear();
    _raster.clear();
  }
}
