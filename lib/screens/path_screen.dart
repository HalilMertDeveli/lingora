import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/course_repository.dart';
import '../data/practice.dart';
import '../data/progress.dart';
import '../models/course.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import 'lesson_screen.dart';
import 'reminder_settings.dart';
import 'speed_match_screen.dart';
import 'story_screen.dart';

enum NodeState { done, active, locked }

String formatWait(Duration d) => d.inMinutes >= 1 ? '${d.inMinutes} dk' : '${d.inSeconds} sn';

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

class _PathList extends ConsumerStatefulWidget {
  const _PathList({required this.course});
  final Course course;

  @override
  ConsumerState<_PathList> createState() => _PathListState();
}

class _PathListState extends ConsumerState<_PathList> {
  final _activeKey = GlobalKey();
  String? _scrolledTo;

  /// Brings the next step into view when it changes (e.g. after a lesson).
  void _scrollToActive(String? id) {
    if (id == null || id == _scrolledTo) return;
    _scrolledTo = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.4,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final course = widget.course;
    final p = ref.watch(progressProvider);
    final all = course.allNodes;
    final activeIndex = all.indexWhere((n) => !p.isDone(n.id));
    // Only scroll once the user is past the first unit's opening steps.
    if (activeIndex > 2) _scrollToActive(all[activeIndex].id);

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
        const SizedBox(height: 12),
        _PracticeRow(course: course),
        const SizedBox(height: 20),
        for (final unit in course.units) ...[
          _UnitHeader(unit: unit, index: course.units.indexOf(unit) + 1),
          const SizedBox(height: 8),
          for (final node in unit.nodes)
            _NodeTile(
              key: stateOf(node) == NodeState.active ? _activeKey : null,
              node: node,
              unit: unit,
              state: stateOf(node),
              isLast: node == unit.nodes.last,
            ),
          const SizedBox(height: 20),
        ],
        if (activeIndex == -1)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Mascot(mood: Mood.cheer, size: 120),
                SizedBox(height: 8),
                Text(
                  'Tüm üniteleri bitirdin! Yeni üniteler yakında.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Hatalarını çalış" and "Hızlı eşleştirme" shortcuts.
class _PracticeRow extends ConsumerWidget {
  const _PracticeRow({required this.course});
  final Course course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final mistakes = p.mistakes.length;
    return Row(
      children: [
        Expanded(
          child: _PracticeCard(
            icon: Icons.fitness_center_rounded,
            color: Brand.primary,
            title: 'Hatalarını çalış',
            subtitle: mistakes == 0 ? 'Hata yok 👏' : '$mistakes soru · can harcamaz',
            onTap: mistakes == 0
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) => LessonScreen(
                        nodeId: 'practice',
                        title: 'Hatalarını çalış',
                        items: mistakeItems(course, p.mistakes),
                        color: Brand.primary,
                        mode: LessonMode.practice,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PracticeCard(
            icon: Icons.timer_rounded,
            color: Brand.accent,
            title: 'Hızlı eşleştirme',
            subtitle: '$speedMatchSeconds saniye',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => SpeedMatchScreen(pool: vocabularyPool(course, p)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PracticeCard extends StatelessWidget {
  const _PracticeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? 0.6 : 1,
    child: TapCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Brand.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
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
                GlossyProgress(value: ratio, height: 12, color: ratio >= 1 ? Brand.success : Brand.accent),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$today / ${p.dailyGoal} XP',
            style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.muted),
          ),
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
      decoration: BoxDecoration(color: unit.color, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ÜNİTE $index',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            unit.title,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
          ),
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
    super.key,
    required this.node,
    required this.unit,
    required this.state,
    required this.isLast,
  });

  final PathNode node;
  final Unit unit;
  final NodeState state;
  final bool isLast;

  Color get color => unit.color;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (state == NodeState.locked) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Önce önceki adımları tamamla.')));
      return;
    }
    final nav = Navigator.of(context);
    switch (node.type) {
      case NodeType.chest:
        if (state == NodeState.done) return;
        ref.read(progressProvider.notifier).completeNode(node.id, xp: node.rewardXp);
        await showDialog<void>(
          context: context,
          builder: (_) => _ChestDialog(xp: node.rewardXp),
        );
      case NodeType.story:
        await nav.push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => StoryScreen(node: node, color: color),
          ),
        );
      case NodeType.test:
        LessonScreen build() => LessonScreen(
          nodeId: node.id,
          title: node.title,
          items: unitTestItems(unit),
          color: color,
          mode: LessonMode.test,
          rewardXp: node.rewardXp,
          retry: build,
        );
        await nav.push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => build()));
      case NodeType.lesson:
        await nav.push(
          MaterialPageRoute<void>(builder: (_) => LessonScreen.forNode(node, color), fullscreenDialog: true),
        );
    }
  }

  IconData get _typeIcon => switch (node.type) {
    NodeType.chest => Icons.card_giftcard_rounded,
    NodeType.story => Icons.auto_stories_rounded,
    NodeType.test => Icons.workspace_premium_rounded,
    NodeType.lesson => Icons.star_rounded,
  };

  String get _cta => switch (node.type) {
    NodeType.chest => 'AÇ',
    NodeType.story => 'OKU',
    NodeType.test => 'SINAV',
    NodeType.lesson => 'BAŞLA',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChest = node.type == NodeType.chest;
    final active = state == NodeState.active;
    final (Color dotColor, IconData icon) = switch (state) {
      NodeState.done => (Brand.success, Icons.check_rounded),
      NodeState.active => (color, _typeIcon),
      NodeState.locked => (Brand.line, node.type == NodeType.lesson ? Icons.lock_rounded : _typeIcon),
    };

    final dot = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: state == NodeState.locked ? const Color(0xFFD3D1DC) : edgeOf(dotColor),
            offset: const Offset(0, 4),
          ),
          if (active) BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 14, spreadRadius: 3),
        ],
      ),
      child: Icon(icon, color: state == NodeState.locked ? Brand.muted : Colors.white),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 56,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Pulse(enabled: active, amount: 0.08, child: dot),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 4,
                      margin: const EdgeInsets.only(top: 4),
                      color: state == NodeState.done ? Brand.success : Brand.line,
                    ),
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
                  selected: active,
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
                            Text(node.description, style: const TextStyle(color: Brand.muted, fontSize: 13)),
                          ],
                        ),
                      ),
                      if (active)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: edgeOf(color), offset: const Offset(0, 3))],
                          ),
                          child: Text(
                            _cta,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                          ),
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

/// Chest wobbles, bursts open and reveals the XP with confetti.
class _ChestDialog extends StatefulWidget {
  const _ChestDialog({required this.xp});
  final int xp;

  @override
  State<_ChestDialog> createState() => _ChestDialogState();
}

class _ChestDialogState extends State<_ChestDialog> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..forward();

  @override
  void initState() {
    super.initState();
    Haptics.success();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    clipBehavior: Clip.antiAlias,
    child: Confetti(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final wobble = t < 0.55 ? sin(t * pi * 14) * 0.18 * (1 - t / 0.55) : 0.0;
            final opened = t >= 0.55;
            final burst = opened ? Curves.elasticOut.transform(((t - 0.55) / 0.45).clamp(0.0, 1.0)) : 0.0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 120,
                  child: Center(
                    child: Transform.rotate(
                      angle: wobble,
                      child: Transform.scale(
                        scale: opened ? 0.9 + 0.3 * burst : 1,
                        child: Text(opened ? '✨' : '🎁', style: const TextStyle(fontSize: 84)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Opacity(
                  opacity: opened ? 1 : 0,
                  child: Column(
                    children: [
                      Text('Ödül açıldı!', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      CountUp(
                        value: opened ? widget.xp : 0,
                        prefix: '+',
                        suffix: ' XP',
                        style: const TextStyle(color: Brand.xp, fontSize: 28, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                PressableButton(label: 'HARİKA', onPressed: () => Navigator.pop(context)),
              ],
            );
          },
        ),
      ),
    ),
  );
}
