import 'package:flutter/material.dart';

import '../theme.dart';
import '../ui/motion.dart';

/// Asks before leaving a lesson or exam (X button or Android back).
///
/// Dilbaz never punishes leaving: the sheet says only that this session's
/// progress is not saved. Returns true when the user chose to leave.
Future<bool> confirmQuitFlow(BuildContext context, {required String title, required String detail}) async {
  final quit = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        key: const Key('quit-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, textAlign: TextAlign.center, style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.muted, height: 1.4),
            ),
            const SizedBox(height: 6),
            Text(
              'Ceza yok: serin, XP\'n ve görevlerin olduğu gibi kalır.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            PressableButton(label: 'DEVAM ET', onPressed: () => Navigator.pop(c, false)),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Çık')),
          ],
        ),
      ),
    ),
  );
  return quit == true;
}

/// One screen of an end-of-lesson sequence; [next] moves on.
typedef EndStep = Widget Function(VoidCallback next);

/// Shows end-of-lesson screens (result, streak, …) one after another in
/// place of the lesson. Each replaces the previous one, so the last "Devam"
/// is a single pop back to the path: nothing of the lesson stays behind.
///
/// Returns the first push's future (completes when the first step is
/// replaced or closed).
Future<void> showEndSequence(NavigatorState nav, List<EndStep> steps) {
  assert(steps.isNotEmpty);
  var current = 0;
  Route<void> routeFor(int index) => MaterialPageRoute<void>(
    settings: RouteSettings(name: 'end-$index'),
    builder: (_) => steps[index](() {
      // A second tap on the same "Devam" does nothing.
      if (index != current || !nav.mounted) return;
      current++;
      if (current < steps.length) {
        nav.pushReplacement(routeFor(current));
      } else {
        nav.pop();
      }
    }),
  );
  return nav.pushReplacement(routeFor(0));
}
