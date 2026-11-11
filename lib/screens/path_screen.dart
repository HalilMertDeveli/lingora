import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/course_repository.dart';
import '../data/practice.dart';
import '../data/progress.dart';
import '../data/sections.dart';
import '../models/course.dart';
import '../nav/tab_navigator.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import 'lesson_screen.dart';
import 'reminder_settings.dart';
import 'section_header.dart';
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
  final _viewportKey = GlobalKey();
  final _scroll = ScrollController();
  ValueListenable<int>? _reselected;

  /// Active node the path was last scrolled to.
  String? _focusedId;

  /// Active node seen on the last build (a change means a step was finished).
  String? _seenActiveId;

  /// Scroll to the active node once the path is visible again.
  bool _focusPending = false;

  /// Newly reached node, briefly highlighted.
  String? _highlightId;
  Timer? _highlightTimer;

  /// Direction of the active node when it is off screen ("Bulunduğun yere dön").
  AxisDirection? _jump;

  bool get _visible => TickerMode.valuesOf(context).enabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = TabScope.maybeOf(context)?.reselected;
    if (next != _reselected) {
      _reselected?.removeListener(_onReselect);
      _reselected = next?..addListener(_onReselect);
    }
    // Became visible again (a lesson closed, or the tab was selected).
    if (_focusPending && _visible) _focusSoon();
  }

  @override
  void dispose() {
    _reselected?.removeListener(_onReselect);
    _highlightTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onReselect() => _focusSoon(force: true);

  /// Brings the active node into view after this frame.
  void _focusSoon({bool force = false}) {
    _focusPending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeKey.currentContext;
      if (!mounted || ctx == null || !ctx.mounted) {
        if (force && mounted && _scroll.hasClients) _animateTo(0);
        return;
      }
      _focusedId = _seenActiveId;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.4,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      ).then((_) => _updateJump());
    });
  }

  void _animateTo(double offset) =>
      _scroll.animateTo(offset, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);

  /// Called on every build with the current active node.
  void _track(String? activeId, int activeIndex) {
    final previous = _seenActiveId;
    _seenActiveId = activeId;
    if (activeId == null) return;
    final first = previous == null && _focusedId == null;
    // On start only scroll once the user is past the first unit's opening steps.
    if (first && activeIndex <= 2) {
      _focusedId = activeId;
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateJump());
      return;
    }
    if (activeId == _focusedId) return;
    if (!first) {
      _highlightTimer?.cancel();
      _highlightId = activeId;
      _highlightTimer = Timer(const Duration(milliseconds: 2400), () {
        if (mounted) setState(() => _highlightId = null);
      });
    }
    _focusedId = activeId;
    if (_visible) {
      _focusSoon();
    } else {
      _focusPending = true;
    }
  }

  void _updateJump() {
    if (!mounted) return;
    final tile = _activeKey.currentContext?.findRenderObject() as RenderBox?;
    final viewport = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    AxisDirection? next;
    if (tile != null && viewport != null && tile.attached && tile.hasSize && viewport.hasSize) {
      final top = tile.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final bottom = top + tile.size.height;
      if (bottom < 0) next = AxisDirection.up;
      if (top > viewport.size.height) next = AxisDirection.down;
    }
    if (next != _jump) setState(() => _jump = next);
  }

  /// Sections the learner opened by hand ("üniteye göz at").
  final _expanded = <String>{};

  /// Sections shown unfolded without asking: the one with the current node,
  /// and open sections still in progress. Locked and finished sections start
  /// folded, so the path does not build hundreds of tiles up front.
  bool _autoExpanded(Section s, bool open, PathNode? current, Progress p) =>
      s.implicit ||
      (current != null && s.units.any((u) => u.nodes.contains(current))) ||
      (open && sectionProgress(s, p) < 1);

  bool _showUnits(Section s, bool open, PathNode? current, Progress p) =>
      _autoExpanded(s, open, current, p) || _expanded.contains(s.id);

  @override
  Widget build(BuildContext context) {
    final course = widget.course;
    final p = ref.watch(progressProvider);
    final all = course.allNodes;
    // Each open section has its own next node; the path focuses on the one in
    // the furthest section (see currentNode).
    final active = {for (final n in activeNodes(course, p).values) n.id};
    final current = currentNode(course, p);
    final open = {for (final s in course.sections) s.id: sectionOpen(course, s, p)};
    _track(current?.id, current == null ? -1 : all.indexOf(current));

    NodeState stateOf(PathNode n) {
      if (p.isDone(n.id)) return NodeState.done;
      return active.contains(n.id) ? NodeState.active : NodeState.locked;
    }

    return Stack(
      key: _viewportKey,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _updateJump();
            return false;
          },
          // Not lazy: every node exists, so the active one can always be found.
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ReminderPromptCard(),
                const _DailyGoalCard(),
                const SizedBox(height: 20),
                for (final section in course.sections) ...[
                  if (!section.implicit) ...[
                    SectionHeader(section: section, open: open[section.id]!),
                    const SizedBox(height: 8),
                    if (!_autoExpanded(section, open[section.id]!, current, p))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: ValueKey('section-toggle-${section.id}'),
                          icon: Icon(_expanded.contains(section.id) ? Icons.expand_less : Icons.expand_more),
                          label: Text(
                            _expanded.contains(section.id)
                                ? 'Üniteleri gizle'
                                : '${section.units.length} üniteye göz at',
                          ),
                          onPressed: () => setState(() {
                            if (!_expanded.remove(section.id)) _expanded.add(section.id);
                          }),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                  if (_showUnits(section, open[section.id]!, current, p))
                    for (final unit in section.units) ...[
                      _UnitHeader(unit: unit, index: section.units.indexOf(unit) + 1),
                      const SizedBox(height: 8),
                      for (final node in unit.nodes)
                        _NodeTile(
                          key: node == current ? _activeKey : ValueKey(node.id),
                          node: node,
                          unit: unit,
                          state: stateOf(node),
                          sectionOpen: open[section.id]!,
                          isLast: node == unit.nodes.last,
                          highlight: node.id == _highlightId,
                        ),
                      const SizedBox(height: 20),
                    ],
                ],
                if (current == null)
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
            ),
          ),
        ),
        if (_jump != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: FloatingActionButton.extended(
                key: const Key('back-to-current'),
                heroTag: null,
                onPressed: () => _focusSoon(force: true),
                icon: Icon(
                  _jump == AxisDirection.up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                ),
                label: const Text('Bulunduğun yere dön'),
              ),
            ),
          ),
      ],
    );
  }
}

/// A soft glow around the node the user has just reached.
class NodeHighlight extends StatelessWidget {
  const NodeHighlight({super.key, required this.on, required this.color, required this.child});
  final bool on;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 400),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(Radii.md + 2),
      boxShadow: [if (on) BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 18, spreadRadius: 2)],
    ),
    child: child,
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
          Icon(Icons.flag_rounded, color: Brand.primary, size: 32),
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
            style: TextStyle(fontWeight: FontWeight.w700, color: Brand.muted),
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
      decoration: context.lingora.hero(unit.color),
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
    this.sectionOpen = true,
    this.highlight = false,
  });

  final PathNode node;
  final Unit unit;
  final NodeState state;
  final bool isLast;

  /// False while the node's section is still locked.
  final bool sectionOpen;

  /// Just reached after a lesson: glows for a moment.
  final bool highlight;

  Color get color => Brand.tone(unit.color);

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (state == NodeState.locked) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              sectionOpen
                  ? 'Önce önceki adımları tamamla.'
                  : 'Bu bölüm kilitli. Önceki bölümü bitir ya da "Bölüme atla" sınavını geç.',
            ),
          ),
        );
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
          if (Brand.isKid)
            BoxShadow(
              color: state == NodeState.locked ? Brand.palette.edge : edgeOf(dotColor),
              offset: const Offset(0, 4),
            ),
          if (active && Brand.isKid)
            BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 14, spreadRadius: 3),
        ],
      ),
      child: Icon(icon, color: state == NodeState.locked ? Brand.muted : onColor(dotColor)),
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
                child: NodeHighlight(
                  on: highlight,
                  color: color,
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
                              Text(node.description, style: TextStyle(color: Brand.muted, fontSize: 13)),
                            ],
                          ),
                        ),
                        if (active)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                if (Brand.isKid) BoxShadow(color: edgeOf(color), offset: const Offset(0, 3)),
                              ],
                            ),
                            child: Text(
                              Brand.isKid ? _cta : sentenceCase(_cta),
                              style: TextStyle(color: onColor(color), fontWeight: FontWeight.w900),
                            ),
                          )
                        else if (state == NodeState.done && !isChest)
                          Icon(Icons.replay_rounded, color: Brand.muted),
                      ],
                    ),
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
                        child: Brand.isKid
                            ? Text(opened ? '✨' : '🎁', style: const TextStyle(fontSize: 84))
                            : Icon(
                                opened ? Icons.redeem_rounded : Icons.card_giftcard_rounded,
                                size: 72,
                                color: Brand.accent,
                              ),
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
                        style: TextStyle(color: Brand.xp, fontSize: 28, fontWeight: FontWeight.w900),
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
