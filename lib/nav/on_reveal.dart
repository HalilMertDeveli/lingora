import 'package:flutter/widgets.dart';

/// Notices when a page becomes visible again after a route covered it (the
/// overlay turns its [TickerMode] back on). Call [revealed] from
/// `didChangeDependencies`.
///
/// The home shell uses it to wake the tab roots it pauses after
/// `HomeScreen.idleAfter`: a paused root also pauses its Riverpod listeners,
/// so after a full-screen flow (the first lesson's end screens) the path
/// stayed on its loading spinner until the next touch (QA, emulator).
class RevealWatch {
  bool? _shown;

  /// Whether [context] has just come back on screen.
  bool revealed(BuildContext context) {
    final shown = TickerMode.valuesOf(context).enabled;
    final back = shown && _shown == false;
    _shown = shown;
    return back;
  }
}
