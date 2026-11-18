import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../theme.dart';
import 'learn_goal.dart';

/// "Hedefin ne?" options (onboarding and Profil > Hedefim). The exam
/// option adds YDS / YÖKDİL and an optional exam date.
class GoalPicker extends StatelessWidget {
  const GoalPicker({super.key, required this.goal, required this.onChanged, required this.now});
  final LearnGoal? goal;
  final ValueChanged<LearnGoal> onChanged;
  final DateTime now;

  LearnGoal _with({GoalKind? kind, GoalExam? exam, String? examDate, bool clearDate = false}) => LearnGoal(
    kind: kind ?? goal?.kind ?? GoalKind.general,
    exam: exam ?? goal?.exam ?? GoalExam.yds,
    examDate: clearDate ? null : (examDate ?? goal?.examDate),
    at: now.millisecondsSinceEpoch,
  );

  Future<void> _pickDate(BuildContext context) async {
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: goal?.examDay ?? today.add(const Duration(days: 60)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
      helpText: 'Sınav tarihin',
    );
    if (picked != null) onChanged(_with(kind: GoalKind.exam, examDate: goalDayKey(picked)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kind = goal?.kind;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final k in GoalKind.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TapCard(
              key: ValueKey('goal-${k.name}'),
              selected: kind == k,
              onTap: () => onChanged(_with(kind: k)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(k.emoji, style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(k.title, style: t.titleMedium),
                            Text(k.subtitle, style: t.bodySmall?.copyWith(color: Brand.muted)),
                          ],
                        ),
                      ),
                      if (kind == k) Icon(Icons.check_circle, color: Brand.primary),
                    ],
                  ),
                  if (k == GoalKind.exam && kind == GoalKind.exam) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final e in GoalExam.values)
                          ChoiceChip(
                            key: ValueKey('goal-exam-${e.name}'),
                            label: Text(e.label),
                            selected: goal?.exam == e,
                            onSelected: (_) => onChanged(_with(exam: e)),
                          ),
                        InputChip(
                          key: const ValueKey('goal-exam-date'),
                          avatar: const Icon(Icons.event_rounded, size: 18),
                          label: Text(switch (goal?.examDay) {
                            final d? => 'Sınav: ${d.day}.${d.month}.${d.year}',
                            null => 'Sınav tarihi ekle (isteğe bağlı)',
                          }),
                          onPressed: () => _pickDate(context),
                          deleteButtonTooltipMessage: 'Tarihi kaldır',
                          onDeleted: goal?.examDate == null ? null : () => onChanged(_with(clearDate: true)),
                        ),
                      ],
                    ),
                    if (goal?.daysLeft(now) case final left? when left > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${goal!.exam.label} sınavına $left gün var.',
                          style: TextStyle(color: Brand.primary, fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Profil > Hedefim: the goal, changeable at any time.
class GoalProfileTile extends ConsumerWidget {
  const GoalProfileTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(learnGoalProvider);
    final now = ref.read(clockProvider)();
    final left = goal?.daysLeft(now);
    return TapCard(
      key: const ValueKey('profile-goal'),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const _GoalSheet(),
      ),
      child: Row(
        children: [
          Text(goal?.kind.emoji ?? '🎯', style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal == null
                      ? 'Hedef seç'
                      : goal.kind == GoalKind.exam
                      ? '${goal.exam.label} sınavı'
                      : goal.kind.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  left != null && left > 0 ? 'Sınava $left gün kaldı' : 'Değiştirmek için dokun',
                  style: TextStyle(color: Brand.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Brand.muted),
        ],
      ),
    );
  }
}

class _GoalSheet extends ConsumerWidget {
  const _GoalSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(learnGoalProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Hedefin ne?', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            GoalPicker(
              goal: goal,
              now: ref.read(clockProvider)(),
              onChanged: (g) => ref.read(progressProvider.notifier).setLearnGoal(g),
            ),
          ],
        ),
      ),
    );
  }
}
