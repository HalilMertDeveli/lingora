import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/course_repository.dart';
import '../data/progress.dart';
import '../models/course.dart';
import '../theme.dart';
import 'lesson_screen.dart';
import 'reminder_settings.dart';

enum NodeState { done, active, locked }

String formatWait(Duration d) =>
    d.inMinutes >= 1 ? '${d.inMinutes} dk' : '${d.inSeconds} sn';

class PathScreen extends ConsumerWidget {
  const PathScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseProvider);
    return course.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Kurs yüklenemedi: $e')),
      data: (c) => _PathList(course: c),
    );
  }
}

class _PathList extends ConsumerWidget {
  const _PathList({required this.course});
  final Course course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final all = course.allNodes;
    final activeIndex = all.indexWhere((n) => !p.isDone(n.id));

    NodeState stateOf(PathNode n) {
      final i = all.indexOf(n);
      if (p.isDone(n.id)) return NodeState.done;
      return i == activeIndex ? NodeState.active : NodeState.locked;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const ReminderPromptCard(),
        const _DailyGoalCard(),
        const SizedBox(height: 20),
        for (final unit in course.units) ...[
          _UnitHeader(unit: unit, index: course.units.indexOf(unit) + 1),
          const SizedBox(height: 8),
          for (final node in unit.nodes)
            _NodeTile(
              node: node,
              color: unit.color,
              state: stateOf(node),
              isLast: node == unit.nodes.last,
            ),
          const SizedBox(height: 20),
        ],
        if (activeIndex == -1)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '🎉 Tüm üniteleri bitirdin! Yeni üniteler yakında.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

class _DailyGoalCard extends ConsumerWidget {
  const _DailyGoalCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final today = p.xpOn(ref.watch(clockProvider)());
    final ratio = (today / p.dailyGoal).clamp(0.0, 1.0);
    return TapCard(
      child: Row(
        children: [
          const Icon(Icons.flag_rounded, color: Brand.primary, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ratio >= 1 ? 'Günlük hedef tamam!' : 'Günlük hedef',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 10,
                    backgroundColor: Brand.line,
                    color: ratio >= 1 ? Brand.success : Brand.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('$today / ${p.dailyGoal} XP',
              style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.muted)),
        ],
      ),
    );
  }
}

class _UnitHeader extends StatelessWidget {
  const _UnitHeader({required this.unit, required this.index});
  final Unit unit;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: unit.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ÜNİTE $index',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                fontSize: 12,
              )),
          const SizedBox(height: 4),
          Text(unit.title,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(unit.description, style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
        ],
      ),
    );
  }
}

/// One stop on the vertical timeline: a status dot on the line plus a card.
class _NodeTile extends ConsumerWidget {
  const _NodeTile({
    required this.node,
    required this.color,
    required this.state,
    required this.isLast,
  });

  final PathNode node;
  final Color color;
  final NodeState state;
  final bool isLast;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (state == NodeState.locked) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Önce önceki adımları tamamla.')));
      return;
    }
    if (node.type == NodeType.chest) {
      if (state == NodeState.done) return;
      ref.read(progressProvider.notifier).completeNode(node.id, xp: node.rewardXp);
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('🎁 Ödül açıldı!', textAlign: TextAlign.center),
          content: Text('+${node.rewardXp} XP kazandın.', textAlign: TextAlign.center),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Harika')),
          ],
        ),
      );
      return;
    }
    final now = ref.read(clockProvider)();
    final p = ref.read(progressProvider);
    if (p.heartsAt(now) == 0) {
      final wait = p.nextHeartIn(now)!;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Canın kalmadı. Yeni can ${formatWait(wait)} sonra.')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LessonScreen(node: node, color: color),
      fullscreenDialog: true,
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChest = node.type == NodeType.chest;
    final (Color dotColor, IconData icon) = switch (state) {
      NodeState.done => (Brand.success, Icons.check_rounded),
      NodeState.active => (color, isChest ? Icons.card_giftcard : Icons.play_arrow_rounded),
      NodeState.locked => (Brand.line, isChest ? Icons.card_giftcard : Icons.lock_rounded),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 56,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    boxShadow: state == NodeState.active
                        ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 12, spreadRadius: 2)]
                        : null,
                  ),
                  child: Icon(icon, color: state == NodeState.locked ? Brand.muted : Colors.white),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 4, color: state == NodeState.done ? Brand.success : Brand.line),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Opacity(
                opacity: state == NodeState.locked ? 0.55 : 1,
                child: TapCard(
                  selected: state == NodeState.active,
                  color: color,
                  onTap: () => _open(context, ref),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(node.title, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 2),
                            Text(node.description,
                                style: const TextStyle(color: Brand.muted, fontSize: 13)),
                          ],
                        ),
                      ),
                      if (state == NodeState.active)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                          child: Text(isChest ? 'AÇ' : 'BAŞLA',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                        )
                      else if (state == NodeState.done && !isChest)
                        const Icon(Icons.replay_rounded, color: Brand.muted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
