import 'dart:math';

import 'package:flutter/material.dart';

import '../models/course.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';

/// Building blocks of the learning path map (docs/arayuz-referans.md,
/// "Yol ekranı"): zigzag round nodes, the unit band, the bouncing start
/// balloon, the lesson card and the unit guide.

enum NodeState { done, active, locked }

/// Size of a path node (the round face, without its lip).
const pathNodeSize = 70.0;

/// Height of the darker lip under a node.
const pathNodeLip = 7.0;

/// Vertical space for one node row.
const pathRowHeight = 96.0;

/// Extra room above the active node for its start balloon.
const balloonRoom = 58.0;

/// Horizontal offset of the [i]th of [count] nodes in a unit, as a share of
/// the maximum swing. Five lanes, walked in a repeating wave of eight
/// (centre, half left, left, half left, centre, half right, right, half
/// right). Odd units start the other way; a unit's last node (its test or
/// chest) is always centred.
double zigzag(int i, {int? count, bool mirror = false}) {
  if (count != null && i == count - 1) return 0;
  const pattern = [0.0, -0.5, -1.0, -0.5, 0.0, 0.5, 1.0, 0.5];
  final v = pattern[i % pattern.length];
  return mirror ? -v : v;
}

/// Maximum swing of the zigzag for a path [width].
double zigzagSwing(double width) => min(70.0, width * 0.2);

/// Row of the unit (0-based) next to which Çaycı Dayı stands, or -1 when
/// the unit is too short. He waits where the path swings away from him.
int mascotRow(Unit unit) => unit.nodes.length < 4 ? -1 : 2;

IconData nodeIcon(NodeType type) => switch (type) {
  NodeType.chest => Icons.card_giftcard_rounded,
  NodeType.story => Icons.auto_stories_rounded,
  NodeType.test => Icons.emoji_events_rounded,
  NodeType.lesson => Icons.star_rounded,
};

/// Call to action of a node ("BAŞLA", "AÇ"…), in the current mode's case.
String nodeCta(NodeType type) {
  final s = switch (type) {
    NodeType.chest => 'AÇ',
    NodeType.story => 'OKU',
    NodeType.test => 'SINAV',
    NodeType.lesson => 'BAŞLA',
  };
  return Brand.isKid ? s : sentenceCase(s);
}

/// One round node of the path: a coloured face on a darker lip that sinks
/// while pressed. Chests and unit tests (trophies) have their own icons.
class PathNodeButton extends StatefulWidget {
  const PathNodeButton({
    super.key,
    required this.type,
    required this.state,
    required this.color,
    required this.onTap,
    this.semanticLabel,
  });

  final NodeType type;
  final NodeState state;
  final Color color;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  State<PathNodeButton> createState() => _PathNodeButtonState();
}

class _PathNodeButtonState extends State<PathNodeButton> {
  bool _down = false;

  void _set(bool v) {
    if (v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (Color face, Color fg, IconData icon) = switch (widget.state) {
      NodeState.done => (
        widget.type == NodeType.chest ? p.accent : widget.color,
        onColor(widget.type == NodeType.chest ? p.accent : widget.color),
        widget.type == NodeType.lesson ? Icons.check_rounded : nodeIcon(widget.type),
      ),
      NodeState.active => (
        widget.type == NodeType.chest ? p.accent : widget.color,
        onColor(widget.type == NodeType.chest ? p.accent : widget.color),
        nodeIcon(widget.type),
      ),
      NodeState.locked => (
        p.isDark ? p.surface : p.line,
        p.muted,
        widget.type == NodeType.lesson ? Icons.lock_rounded : nodeIcon(widget.type),
      ),
    };
    final lip = widget.state == NodeState.locked ? Color.alphaBlend(p.edge, face) : edgeOf(face);
    final sink = _down ? pathNodeLip - 2 : 0.0;
    final active = widget.state == NodeState.active;
    final node = SizedBox(
      width: pathNodeSize,
      height: pathNodeSize + pathNodeLip,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: pathNodeSize,
            child: DecoratedBox(
              decoration: BoxDecoration(color: lip, shape: BoxShape.circle),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 70),
            left: 0,
            right: 0,
            top: sink,
            height: pathNodeSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: face,
                shape: BoxShape.circle,
                // Done nodes are a touch lighter than the current one.
                gradient: widget.state == NodeState.done
                    ? null
                    : RadialGradient(
                        center: const Alignment(-0.3, -0.4),
                        radius: 0.9,
                        colors: [Color.lerp(face, Colors.white, 0.12)!, face],
                      ),
              ),
              child: Icon(icon, color: fg, size: widget.type == NodeType.lesson ? 34 : 32),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: () {
          Haptics.tap();
          widget.onTap();
        },
        // The current node wears a ring, like a target to aim for.
        child: active ? _Ring(color: widget.color, child: node) : node,
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('active-ring'),
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color.withValues(alpha: 0.35), width: 5),
    ),
    child: child,
  );
}

/// "Başla" speech balloon over the current node. It bobs up and down
/// (unless animations are reduced); tapping it starts the step at once.
class StartBalloon extends StatefulWidget {
  const StartBalloon({super.key, required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  /// One leg of the bob (up, then the same back down).
  static const leg = Duration(milliseconds: 1000);

  /// How far the balloon rises.
  static const amplitude = 8.0;

  @override
  State<StartBalloon> createState() => _StartBalloonState();
}

class _StartBalloonState extends State<StartBalloon> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: StartBalloon.leg);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loopsEnabled(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = widget.color;
    final bubble = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        widget.onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.isDark ? p.line : p.line, width: 2),
              boxShadow: [BoxShadow(color: p.isDark ? p.edge : p.line, offset: const Offset(0, 3))],
            ),
            child: Text(
              widget.label,
              style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.4),
            ),
          ),
          CustomPaint(
            size: const Size(16, 8),
            painter: _PointerPainter(fill: p.card, border: p.line),
          ),
        ],
      ),
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, -StartBalloon.amplitude * Curves.easeInOut.transform(_c.value)),
        child: child,
      ),
      child: bubble,
    );
  }
}

/// Small downward triangle under a balloon or above/below a card.
class _PointerPainter extends CustomPainter {
  _PointerPainter({required this.fill, required this.border, this.up = false});
  final Color fill;
  final Color border;
  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    final path = up
        ? (Path()
            ..moveTo(0, size.height)
            ..lineTo(size.width / 2, 0)
            ..lineTo(size.width, size.height))
        : (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width / 2, size.height)
            ..lineTo(size.width, 0));
    canvas
      ..drawPath(path, Paint()..color = fill)
      ..drawPath(
        path,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.fill != fill || old.border != border || old.up != up;
}

/// Unit band at the top of each unit: "ÜNİTE 2", the title and a guide
/// button. The same band is pinned to the top of the path while the unit
/// is scrolled ([compact]).
class UnitBand extends StatelessWidget {
  const UnitBand({
    super.key,
    required this.unit,
    required this.index,
    required this.onGuide,
    this.compact = false,
  });
  final Unit unit;
  final int index;
  final VoidCallback onGuide;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final lt = context.lingora;
    final deco = lt.hero(unit.color);
    final base = deco.color ?? unit.color;
    final lip = edgeOf(base);
    return Container(
      decoration: BoxDecoration(
        color: lip,
        borderRadius: (deco.borderRadius ?? BorderRadius.circular(Radii.lg)) as BorderRadius,
      ),
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: EdgeInsets.fromLTRB(18, compact ? 10 : 16, 10, compact ? 10 : 16),
        decoration: deco,
        child: Row(
          children: [
            Expanded(
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
                  const SizedBox(height: 2),
                  Text(
                    unit.title,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 17 : 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 2),
                    Text(unit.description, style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _GuideButton(key: Key('unit-guide-${unit.id}${compact ? '-pinned' : ''}'), onTap: onGuide),
          ],
        ),
      ),
    );
  }
}

class _GuideButton extends StatelessWidget {
  const _GuideButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Ünite rehberi',
    child: Material(
      color: Colors.white.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.45), width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_rounded, color: Colors.white, size: 22),
              SizedBox(width: 6),
              Text(
                'Rehber',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Card that opens under (or over) a tapped node: title, where the step is
/// in its unit, and the action. Locked steps explain how to open them.
class LessonCard extends StatelessWidget {
  const LessonCard({
    super.key,
    required this.node,
    required this.state,
    required this.color,
    required this.position,
    required this.count,
    required this.onStart,
    this.lockedMessage,
    this.arrowX,
    this.above = false,
  });

  final PathNode node;
  final NodeState state;
  final Color color;

  /// 1-based position of the step in its unit, and the unit's step count.
  final int position;
  final int count;
  final VoidCallback onStart;
  final String? lockedMessage;

  /// Horizontal centre of the node, from the card's left edge.
  final double? arrowX;

  /// True when the card sits above the node (pointer at its bottom).
  final bool above;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final locked = state == NodeState.locked;
    final face = locked ? p.card : color;
    final fg = locked ? p.ink : onColor(color);
    final sub = locked ? p.muted : fg.withValues(alpha: 0.85);
    final kind = switch (node.type) {
      NodeType.lesson => 'Ders $position / $count',
      NodeType.story => 'Hikâye',
      NodeType.test => 'Ünite sınavı',
      NodeType.chest => 'Ödül sandığı',
    };
    final (String label, bool enabled) = switch ((state, node.type)) {
      (NodeState.locked, _) => ('', false),
      (NodeState.done, NodeType.chest) => ('AÇILDI', false),
      (NodeState.done, _) => ('TEKRAR ET', true),
      (NodeState.active, NodeType.chest) => ('AÇ', true),
      (NodeState.active, NodeType.test) => ('SINAVA BAŞLA', true),
      (NodeState.active, NodeType.story) => ('OKU', true),
      (NodeState.active, NodeType.lesson) => ('BAŞLA +${node.rewardXp > 0 ? node.rewardXp : 10} XP', true),
    };
    final pointer = CustomPaint(
      size: const Size(22, 11),
      painter: _PointerPainter(fill: face, border: locked ? p.line : face, up: !above),
    );
    Widget arrow() => Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(left: max(0, (arrowX ?? 160) - 11)),
        child: pointer,
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: Column(
        key: const Key('lesson-card'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!above) arrow(),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: face,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: locked ? Border.all(color: p.line, width: 2) : null,
              boxShadow: [
                BoxShadow(
                  color: locked ? (p.isDark ? p.edge : p.line) : edgeOf(color),
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  node.title,
                  style: TextStyle(color: fg, fontSize: 19, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  locked ? (lockedMessage ?? 'Önce önceki adımları tamamla.') : kind,
                  style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                ),
                if (node.type == NodeType.lesson) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      key: const Key('lesson-card-progress'),
                      value: count == 0 ? 0 : (state == NodeState.done ? position : position - 1) / count,
                      minHeight: 8,
                      color: locked ? p.muted : fg,
                      backgroundColor: (locked ? p.line : fg).withValues(alpha: locked ? 1 : 0.25),
                    ),
                  ),
                ],
                if (!locked && node.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(node.description, style: TextStyle(color: sub, fontSize: 13)),
                ],
                if (label.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  PressableButton(
                    key: const Key('lesson-card-start'),
                    label: label,
                    color: p.card,
                    foreground: color,
                    onPressed: enabled ? onStart : null,
                  ),
                ],
              ],
            ),
          ),
          if (above) arrow(),
        ],
      ),
    );
  }
}

/// Çaycı Dayı standing beside the path. Kid mode: bigger and bobbing.
class PathMascot extends StatelessWidget {
  const PathMascot({super.key, required this.mood});
  final Mood mood;

  @override
  Widget build(BuildContext context) =>
      Dayi(key: const Key('path-mascot'), mood: mood, size: context.isKid ? 104 : 84, animate: context.isKid);
}

/// Key words and phrases of a unit, from its exercises (English → Turkish).
List<(String, String)> unitPhrases(Unit unit, {int max = 14}) {
  final seen = <String>{};
  final out = <(String, String)>[];
  void add(String en, String tr) {
    final k = en.toLowerCase().trim();
    if (k.isEmpty || tr.trim().isEmpty || !seen.add(k)) return;
    out.add((en.trim(), tr.trim()));
  }

  for (final n in unit.nodes) {
    for (final ex in n.exercises) {
      switch (ex.type) {
        case ExerciseType.match:
          for (final (a, b) in ex.pairs) {
            add(a, b);
          }
        case ExerciseType.select:
          if (ex.answer != null && ex.prompt != null) add(ex.answer!, ex.prompt!);
        default:
          break;
      }
      if (out.length >= max) return out;
    }
  }
  return out;
}

/// Bottom sheet with the unit's steps and key phrases ("Ünite rehberi").
Future<void> showUnitGuide(
  BuildContext context, {
  required Unit unit,
  required int index,
  required NodeState Function(PathNode) stateOf,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useRootNavigator: true,
  builder: (c) {
    final t = Theme.of(c).textTheme;
    final color = Brand.tone(unit.color);
    final phrases = unitPhrases(unit);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (_, scroll) => ListView(
        key: const Key('unit-guide'),
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            'ÜNİTE $index REHBERİ',
            style: TextStyle(color: color, fontWeight: FontWeight.w900, letterSpacing: 1),
          ),
          const SizedBox(height: 4),
          Text(unit.title, style: t.headlineSmall),
          const SizedBox(height: 4),
          Text(unit.description, style: TextStyle(color: Brand.muted, height: 1.4)),
          const SizedBox(height: 18),
          if (phrases.isNotEmpty) ...[
            Text('Anahtar ifadeler', style: t.titleMedium),
            const SizedBox(height: 8),
            TapCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(
                children: [
                  for (final (en, tr) in phrases)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(en, style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(tr, style: TextStyle(color: Brand.muted)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          Text('Bu ünitedeki adımlar', style: t.titleMedium),
          const SizedBox(height: 8),
          for (final n in unit.nodes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(switch (stateOf(n)) {
                NodeState.done => Icons.check_circle_rounded,
                NodeState.active => nodeIcon(n.type),
                NodeState.locked => Icons.lock_outline_rounded,
              }, color: stateOf(n) == NodeState.locked ? Brand.muted : color),
              title: Text(n.title),
              subtitle: n.description.isEmpty ? null : Text(n.description),
            ),
        ],
      ),
    );
  },
);
