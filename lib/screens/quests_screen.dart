import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../data/quests.dart';
import '../theme.dart';

String formatLeft(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} gün ${d.inHours % 24} sa';
  if (d.inHours >= 1) return '${d.inHours} sa ${d.inMinutes % 60} dk';
  return '${d.inMinutes} dk';
}

/// Number of quests ready to claim today (for the tab badge).
final claimableQuestsProvider = Provider<int>((ref) {
  final p = ref.watch(progressProvider);
  final now = ref.watch(clockProvider)();
  return questsForDay(now).where((q) => q.isComplete(p, now) && !p.isClaimed(now, q.id)).length;
});

class QuestsScreen extends ConsumerWidget {
  const QuestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final now = ref.watch(clockProvider)();
    final quests = questsForDay(now);
    final t = Theme.of(context).textTheme;
    final done = quests.where((q) => p.isClaimed(now, q.id)).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Brand.primary, Color(0xFF9B7BFF)]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Günlük görevler',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Yenilenmesine ${formatLeft(untilTomorrow(now))}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                    ),
                  ],
                ),
              ),
              Text(
                '$done/${quests.length}',
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final q in quests) ...[_QuestCard(quest: q, progress: p, now: now), const SizedBox(height: 12)],
        const SizedBox(height: 8),
        Text(
          'Görev ödülleri XP olarak eklenir ve lig puanına da sayılır.',
          textAlign: TextAlign.center,
          style: t.bodySmall?.copyWith(color: Brand.muted),
        ),
      ],
    );
  }
}

class _QuestCard extends ConsumerWidget {
  const _QuestCard({required this.quest, required this.progress, required this.now});
  final QuestDef quest;
  final Progress progress;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = quest.progressOf(progress, now);
    final complete = quest.isComplete(progress, now);
    final claimed = progress.isClaimed(now, quest.id);

    return TapCard(
      selected: complete && !claimed,
      color: Brand.success,
      child: Row(
        children: [
          Icon(
            claimed ? Icons.check_circle_rounded : _icon(quest.metric),
            color: claimed ? Brand.success : Brand.primary,
            size: 34,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(quest.title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: value / quest.target,
                          minHeight: 10,
                          backgroundColor: Brand.line,
                          color: complete ? Brand.success : Brand.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$value/${quest.target}',
                      style: const TextStyle(color: Brand.muted, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (claimed)
            const Text(
              'Alındı',
              style: TextStyle(color: Brand.success, fontWeight: FontWeight.w800),
            )
          else if (complete)
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 40), backgroundColor: Brand.success),
              onPressed: () {
                if (ref.read(progressProvider.notifier).claimQuest(quest)) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text('+${quest.rewardXp} XP kazandın!')));
                }
              },
              child: Text('+${quest.rewardXp}'),
            )
          else
            Row(
              children: [
                const Icon(Icons.bolt, color: Brand.xp, size: 18),
                Text(
                  '${quest.rewardXp}',
                  style: const TextStyle(color: Brand.xp, fontWeight: FontWeight.w800),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static IconData _icon(QuestMetric m) => switch (m) {
    QuestMetric.xp => Icons.bolt,
    QuestMetric.lessons => Icons.menu_book_rounded,
    QuestMetric.perfectLessons => Icons.workspace_premium,
    QuestMetric.listen => Icons.headphones_rounded,
    QuestMetric.translate => Icons.translate_rounded,
    QuestMetric.match => Icons.extension_rounded,
  };
}
