import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Counts how often the app came back to the foreground. Providers whose
/// answer depends on the wall clock (Premium expiry, the month's streak
/// freezes) watch it, because Dart timers do not run while the phone sleeps
/// and Android may keep the process alive for days.
final appResumeProvider = NotifierProvider<AppResume, int>(AppResume.new);

class AppResume extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// How far ahead [recheckAt] keeps a timer.
const recheckHorizon = Duration(hours: 24);

/// Re-evaluates the provider of [ref] when [deadline] passes (while the app
/// runs) and on every resume. Call it from a provider body.
void recheckAt(Ref ref, DateTime? deadline, DateTime now) {
  ref.watch(appResumeProvider);
  if (deadline == null || !deadline.isAfter(now)) return;
  final left = deadline.difference(now);
  // Far deadlines are caught by a later resume, which arms the timer then.
  if (left > recheckHorizon) return;
  // A little after the deadline, so the re-check sees it as passed.
  final timer = Timer(left + const Duration(seconds: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
}

/// Bumps [appResumeProvider] when the app is resumed. Wraps the app once
/// (main.dart).
class AppResumeWatcher extends ConsumerStatefulWidget {
  const AppResumeWatcher({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppResumeWatcher> createState() => _AppResumeWatcherState();
}

class _AppResumeWatcherState extends ConsumerState<AppResumeWatcher> {
  late final AppLifecycleListener _listener = AppLifecycleListener(
    onResume: () => ref.read(appResumeProvider.notifier).bump(),
  );

  @override
  void initState() {
    super.initState();
    _listener; // created now
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
