import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings.dart';
import '../data/progress.dart';
import '../theme.dart';
import 'countdown_screen.dart';
import 'interview_entry.dart';
import 'learn_goal.dart';

/// Home ("Öğren") card for the learner's goal: the exam countdown plan or
/// the interview rehearsal. Nothing for other goals or in Çocuk modu.
class GoalHomeCard extends ConsumerWidget {
  const GoalHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(learnGoalProvider);
    if (goal == null || ref.watch(appSettingsProvider.select((s) => s.isKid))) return const SizedBox.shrink();
    final now = ref.watch(clockProvider)();
    final (emoji, title, subtitle, VoidCallback? onTap) = switch (goal.kind) {
      GoalKind.exam => (
        '📝',
        switch (goal.daysLeft(now)) {
          final d? when d > 0 => "${goal.exam.label}'ye $d gün kaldı".replaceAll("YÖKDİL'ye", "YÖKDİL'e"),
          _ => '${goal.exam.label} planım',
        },
        'Sınava kadar şu konuları çalış: bugünün planı hazır',
        () => openCountdown(context),
      ),
      GoalKind.interview => (
        '💼',
        'Mülakat provası',
        'Gerçek sorularla prova yap, kişisel geri bildirim al',
        () => openInterviewRehearsal(context),
      ),
      _ => ('', '', '', null),
    };
    if (onTap == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TapCard(
        key: ValueKey('goal-card-${goal.kind.name}'),
        onTap: onTap,
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  Text(subtitle, style: TextStyle(color: Brand.muted, fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Brand.primary),
          ],
        ),
      ),
    );
  }
}
