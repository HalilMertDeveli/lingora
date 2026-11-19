import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../theme.dart';
import 'onboarding_screen.dart' show dailyGoals, dailyGoalPendingKey;

/// Lessons after which the daily goal is asked (not on the first run: by
/// then the learner knows how long a lesson takes).
const dailyGoalAskAfterLessons = 3;

/// Whether the path's daily goal card should ask for the goal now.
bool dailyGoalAskDue(WidgetRef ref) =>
    (ref.watch(prefsProvider).getBool(dailyGoalPendingKey) ?? false) &&
    ref.watch(progressProvider.select((p) => p.lessonsDone)) >= dailyGoalAskAfterLessons;

/// "Günlük hedefin ne olsun?" as a sheet (path card, after a few lessons).
Future<void> showDailyGoalSheet(BuildContext context, WidgetRef ref) async {
  final current = ref.read(progressProvider).dailyGoal;
  final picked = await showModalBottomSheet<int>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (c) {
      final t = Theme.of(c).textTheme;
      return SafeArea(
        child: Padding(
          key: const Key('daily-goal-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Günlük hedefin ne olsun?', style: t.titleLarge),
              const SizedBox(height: 4),
              Text(
                "Birkaç ders yaptın; ne kadar sürdüğünü artık biliyorsun. Profil'den değiştirebilirsin.",
                style: TextStyle(color: Brand.muted),
              ),
              const SizedBox(height: 12),
              for (final (xp, name, hint) in dailyGoals)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TapCard(
                    key: Key('daily-goal-$xp'),
                    selected: xp == current,
                    onTap: () => Navigator.pop(c, xp),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: t.titleMedium),
                              Text(hint, style: t.bodySmall?.copyWith(color: Brand.muted)),
                            ],
                          ),
                        ),
                        Text('$xp XP / gün', style: t.titleSmall?.copyWith(color: Brand.muted)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
  if (picked == null) return;
  // The flag first: setting the goal rebuilds the card, which reads it.
  await ref.read(prefsProvider).remove(dailyGoalPendingKey);
  ref.read(progressProvider.notifier).setDailyGoal(picked);
}
