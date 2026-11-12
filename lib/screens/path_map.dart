import 'dart:math';

import 'package:flutter/material.dart';

import '../data/topic_themes.dart';
import '../models/course.dart';
import '../theme.dart';
import '../ui/markdown_text.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import '../ui/tea_art.dart';
import '../ui/theme_art.dart';

/// Building blocks of the learning path, Dilbaz's tea-house walk (see
/// docs/tasarim.md, "Çay kimliği"): tea glass nodes on a winding lane, the
/// teapot reward, the tulip test, Çaycı Dayı's "bir çay daha" invite, the
/// unit band with its tile motif, the lesson card and the unit guide.

enum NodeState { done, active, locked }

/// Size of a path node (glass and saucer).
const pathNodeWidth = 66.0;
const pathNodeHeight = 84.0;

/// Extra room above the active node for its invite bubble and steam.
const balloonRoom = 74.0;

/// Horizontal offset of the [i]th node of a unit, as a share of the maximum
/// swing: a soft S-curve (a sine wave of eight steps). Odd units start the
/// other way, so the lane keeps winding from unit to unit.
double laneOffset(int i, {bool mirror = false}) {
  final v = (sin(i * pi / 4) * 1000).roundToDouble() / 1000;
  return mirror ? -v : v;
}

/// Maximum swing of the lane for a path [width].
double laneSwing(double width) => min(72.0, width * 0.2);

/// Row of the unit (0-based) next to which the host stands, or -1 when the
/// unit is too short. They wait where the lane swings away from them.
int mascotRow(Unit unit) => unit.nodes.length < 4 ? -1 : 2;

IconData nodeIcon(NodeType type) => switch (type) {
  NodeType.chest => Icons.coffee_maker_outlined,
  NodeType.story => Icons.auto_stories_rounded,
  NodeType.test => Icons.local_florist_rounded,
  NodeType.lesson => Icons.local_cafe_rounded,
  NodeType.mock => Icons.timer_rounded,
};

/// The host's invite over the current node, in the unit's topic.
String nodeInvite(NodeType type, [TopicTheme? theme]) {
  final t = theme ?? themeById(null);
  return switch (type) {
    NodeType.chest => t.chestInvite,
    NodeType.story => t.storyInvite,
    NodeType.test => t.testInvite,
    NodeType.lesson => t.lessonInvite,
    NodeType.mock => 'Deneme zamanı, hazırsın!',
  };
}

/// Theme of [unit] (the default for units without one).
TopicTheme themeOf(Unit unit) => themeById(unit.theme);

/// Object drawn for [node] of [unit]: lessons and stories walk through the
/// theme's story objects in order; tests and rewards have their own.
String nodeObject(Unit unit, PathNode node) {
  final t = themeOf(unit);
  return switch (node.type) {
    NodeType.chest => t.reward,
    NodeType.test || NodeType.mock => t.badge,
    _ => t.stepObject(
      unit.nodes.where((n) => n.type == NodeType.lesson || n.type == NodeType.story).toList().indexOf(node),
    ),
  };
}

/// Call to action of a node ("BAŞLA", "AÇ"…), in the current mode's case.
String nodeCta(NodeType type) {
  final s = switch (type) {
    NodeType.chest => 'AÇ',
    NodeType.story => 'OKU',
    NodeType.test => 'SINAV',
    NodeType.lesson => 'BAŞLA',
    NodeType.mock => 'DENEME',
  };
  return Brand.isKid ? s : sentenceCase(s);
}

/// How full a lesson glass is.
double glassLevel(NodeState s) => switch (s) {
  NodeState.done => 0.86,
  NodeState.active => 0.5,
  NodeState.locked => 0,
};

/// One node of the path. Lessons and stories are tea glasses: a finished one
/// is full of deep tea with a gold rim, the current one is half full,
/// steaming and gently breathing, a locked one is an empty glass. The reward
/// is a double teapot (opened: lid up, sugar cubes beside it) and the unit
/// test a tulip. Every node squashes like a jelly when pressed.
class TeaNode extends StatefulWidget {
  const TeaNode({
    super.key,
    required this.type,
    required this.state,
    required this.color,
    required this.onTap,
    this.semanticLabel,
    this.theme,
    this.object,
  });

  final NodeType type;
  final NodeState state;
  final Color color;
  final VoidCallback onTap;
  final String? semanticLabel;

  /// Topic of the unit; null (or the tea theme) draws the tea glass, teapot
  /// and tulip.
  final TopicTheme? theme;

  /// Theme object of this node (see [nodeObject]).
  final String? object;

  /// One breath of the current node (in and out).
  static const breath = Duration(milliseconds: 2600);

  @override
  State<TeaNode> createState() => _TeaNodeState();
}

class _TeaNodeState extends State<TeaNode> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: TeaNode.breath);

  bool get _active => widget.state == NodeState.active;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(TeaNode old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_active && loopsEnabled(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else if (_c.isAnimating || _c.value != 0) {
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

  CustomPainter _painter(Palette p, double t) {
    final dim = widget.state == NodeState.locked;
    final done = widget.state == NodeState.done;
    return switch (widget.type) {
      NodeType.chest => TeapotPainter(color: p.accent, palette: p, open: done, dim: dim),
      NodeType.test || NodeType.mock => TulipPainter(
        color: done ? tulipRed : widget.color,
        palette: p,
        bloom: done ? 1 : (_active ? 0.5 + 0.2 * sin(t * pi * 2).abs() : 0.2),
        dim: dim,
      ),
      _ => TeaGlassPainter(
        level: glassLevel(widget.state) + (_active ? sin(t * pi * 2) * 0.03 : 0),
        wave: t,
        color: widget.color,
        palette: p,
        goldRim: done,
        dim: dim,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final locked = widget.state == NodeState.locked;
    final done = widget.state == NodeState.done;
    Widget badge(IconData icon, Color bg, Color fg) => Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: p.card, width: 2),
      ),
      child: Icon(icon, size: 13, color: fg),
    );
    final theme = widget.theme;
    final themed = theme != null && !theme.tea && widget.object != null;
    final art = themed
        ? _ThemedArt(
            theme: theme,
            object: widget.object!,
            type: widget.type,
            state: widget.state,
            animation: _c,
          )
        : AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final t = _c.value;
              final breathe = _active ? 1 + sin(t * pi * 2) * 0.035 : 1.0;
              return Transform.scale(
                scale: breathe,
                alignment: Alignment.bottomCenter,
                child: CustomPaint(size: const Size(pathNodeWidth, pathNodeHeight), painter: _painter(p, t)),
              );
            },
          );
    final glow = themed ? theme.accent : widget.color;
    final node = SizedBox(
      width: pathNodeWidth,
      height: pathNodeHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_active)
            Positioned(
              left: -16,
              right: -16,
              top: -4,
              bottom: -10,
              child: DecoratedBox(
                key: const Key('active-glow'),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      glow.withValues(alpha: p.isDark ? 0.34 : 0.24),
                      glow.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          Positioned.fill(child: art),
          if (!themed && _active && (widget.type == NodeType.lesson || widget.type == NodeType.story))
            const Positioned(left: 13, top: -30, child: Steam(width: 40, height: 32)),
          if (done && widget.type != NodeType.chest)
            Positioned(right: -2, top: 2, child: badge(Icons.check_rounded, p.success, onColor(p.success))),
          if (locked)
            Positioned(
              right: 0,
              bottom: 6,
              child: badge(Icons.lock_rounded, p.isDark ? p.surface : p.line, p.muted),
            ),
          if (widget.type == NodeType.story && !locked)
            Positioned(
              left: -2,
              top: 2,
              child: badge(Icons.auto_stories_rounded, widget.color, onColor(widget.color)),
            ),
          if (widget.type == NodeType.mock && !locked)
            Positioned(
              key: const Key('mock-badge'),
              left: -2,
              top: 2,
              child: badge(Icons.timer_rounded, widget.color, onColor(widget.color)),
            ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      value: switch (widget.state) {
        NodeState.done => 'Bitti',
        NodeState.active => 'Sıradaki',
        NodeState.locked => 'Kilitli',
      },
      child: JellyPress(amount: 0.8, onTap: widget.onTap, child: node),
    );
  }
}

/// A themed node: the step's object on a soft plate, the test emblem in a
/// rosette, or the reward on its own. Locked objects are grey silhouettes;
/// the current one moves the theme's way.
class _ThemedArt extends StatelessWidget {
  const _ThemedArt({
    required this.theme,
    required this.object,
    required this.type,
    required this.state,
    required this.animation,
  });

  final TopicTheme theme;
  final String object;
  final NodeType type;
  final NodeState state;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dim = state == NodeState.locked;
    final done = state == NodeState.done;
    final active = state == NodeState.active;
    final accent = Brand.tone(theme.accent);
    const size = Size(pathNodeWidth, pathNodeHeight);
    Widget moving(Widget child) => active
        ? AnimatedBuilder(
            animation: animation,
            builder: (_, c) => applyMotion(theme.motion, animation.value, c!, accent),
            child: child,
          )
        : child;
    final obj = ThemeObject(
      theme: theme,
      object: object,
      size: switch (type) {
        NodeType.chest => 58,
        NodeType.test || NodeType.mock => 30,
        _ => 44,
      },
      grey: dim,
    );
    return switch (type) {
      NodeType.test || NodeType.mock => moving(
        Stack(
          alignment: Alignment.topCenter,
          children: [
            CustomPaint(
              size: size,
              painter: BadgePainter(color: accent, palette: p, dim: dim, done: done),
            ),
            Positioned(top: size.height * 0.42 - 15, child: obj),
          ],
        ),
      ),
      NodeType.chest => Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: size,
            painter: PlatePainter(color: accent, palette: p, dim: dim, done: done),
          ),
          Positioned(top: 4, child: moving(obj)),
          if (done)
            for (final (dx, dy, s) in [(-26.0, -30.0, 9.0), (24.0, -26.0, 7.0), (20.0, 18.0, 6.0)])
              Transform.translate(
                offset: Offset(dx, dy),
                child: Icon(Icons.auto_awesome, size: s * 1.6, color: const Color(0xFFF4C542)),
              ),
        ],
      ),
      _ => Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: size,
            painter: PlatePainter(color: accent, palette: p, dim: dim, done: done),
          ),
          Positioned(top: size.height * 0.46 - 22, child: moving(obj)),
        ],
      ),
    };
  }
}

/// Çaycı Dayı (Pofuduk in Çocuk modu) holding out the next glass: a speech
/// bubble over the current node, "Hadi, bir çay daha!". It sways gently
/// (unless animations are reduced); tapping it starts the step at once.
class TeaInvite extends StatefulWidget {
  const TeaInvite({super.key, required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  /// One leg of the sway.
  static const leg = Duration(milliseconds: 1200);

  /// How far the bubble rises.
  static const amplitude = 5.0;

  @override
  State<TeaInvite> createState() => _TeaInviteState();
}

class _TeaInviteState extends State<TeaInvite> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: TeaInvite.leg);

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
    final kid = context.isKid;
    final border = widget.color.withValues(alpha: 0.45);
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
            padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: border, width: 1.5),
              boxShadow: softShadow(p, tint: widget.color),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.asset(
                    kid ? pofudukAvatar : mascotAsset,
                    width: 28,
                    height: 28,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) => const SizedBox(width: 28, height: 28),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: widget.color, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          CustomPaint(
            size: const Size(14, 8),
            painter: _PointerPainter(fill: p.card, border: border),
          ),
        ],
      ),
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, -TeaInvite.amplitude * Curves.easeInOut.transform(_c.value)),
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
          ..strokeWidth = 1.5,
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
    final theme = themeOf(unit);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: (deco.borderRadius ?? BorderRadius.circular(Radii.lg)) as BorderRadius,
        boxShadow: softShadow(lt.palette, tint: base),
      ),
      child: Container(
        padding: EdgeInsets.fromLTRB(18, compact ? 10 : 16, 10, compact ? 10 : 16),
        decoration: deco,
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: theme.tea ? CiniPainter(color: Colors.white.withValues(alpha: 0.16), start: 0.45) : null,
          child: Stack(
            children: [
              if (!theme.tea) Positioned.fill(child: _BandPattern(theme: theme)),
              _bandRow(compact, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bandRow(bool compact, TopicTheme theme) => Row(
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
              style: TextStyle(color: Colors.white, fontSize: compact ? 17 : 22, fontWeight: FontWeight.w900),
            ),
            if (!compact) ...[
              const SizedBox(height: 2),
              Text(unit.description, style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
            ],
          ],
        ),
      ),
      if (!compact && !theme.tea) ...[
        const SizedBox(width: 4),
        // The band's illustration: the unit's first story object, tilted.
        Transform.rotate(
          angle: -0.12,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: ThemeObject(
                key: Key('band-art-${unit.id}'),
                theme: theme,
                object: theme.steps.first,
                size: 40,
              ),
            ),
          ),
        ),
      ],
      const SizedBox(width: 8),
      _GuideButton(key: Key('unit-guide-${unit.id}${compact ? '-pinned' : ''}'), onTap: onGuide),
    ],
  );
}

/// The band's pattern: the theme's decorations as faint white stamps,
/// fading in from the middle of the band.
class _BandPattern extends StatelessWidget {
  const _BandPattern({required this.theme});
  final TopicTheme theme;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const cell = 30.0;
      final stamps = <Widget>[];
      var k = 0;
      for (var y = -6.0; y < box.maxHeight; y += cell) {
        final row = (y / cell).round();
        for (var x = box.maxWidth * 0.42 + (row.isOdd ? cell / 2 : 0); x < box.maxWidth; x += cell) {
          final f = ((x / box.maxWidth - 0.42) / 0.4).clamp(0.0, 1.0);
          stamps.add(
            Positioned(
              left: x,
              top: y,
              child: ThemeObject(
                theme: theme,
                object: theme.decor[k++ % theme.decor.length],
                size: 18,
                tint: Colors.white.withValues(alpha: 0.08 + 0.12 * f),
              ),
            ),
          );
        }
      }
      return ExcludeSemantics(
        child: Stack(key: Key('band-pattern-${theme.id}'), clipBehavior: Clip.hardEdge, children: stamps),
      );
    },
  );
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
    this.theme,
    this.note,
  });

  /// Extra line under the step's kind (e.g. the last mock exam's result).
  final String? note;

  /// Topic of the unit (names the badge and the reward).
  final TopicTheme? theme;

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
    final t = theme ?? themeById(null);
    final kind = switch (node.type) {
      NodeType.lesson => 'Ders $position / $count',
      NodeType.story => node.listenFirst ? 'Dinleme hikâyesi' : 'Hikâye',
      NodeType.test => t.tea ? 'Ünite sınavı · lale rozeti' : 'Ünite sınavı · ${t.badgeName} rozeti',
      NodeType.chest => t.tea ? 'Çaydanlık · şeker ödülü' : '${t.rewardName} · sürpriz ödül',
      NodeType.mock =>
        'Bölüm denemesi · ${node.size > 0 ? '${node.size} soru' : 'karışık sorular'}'
            '${node.minutes > 0 ? ' · ${node.minutes} dk' : ''}',
    };
    final (String label, bool enabled) = switch ((state, node.type)) {
      (NodeState.locked, _) => ('', false),
      (NodeState.done, NodeType.chest) => ('AÇILDI', false),
      (NodeState.done, _) => ('TEKRAR ET', true),
      (NodeState.active, NodeType.chest) => ('AÇ', true),
      (NodeState.active, NodeType.test) => ('SINAVA BAŞLA', true),
      // A listen-first story is heard before its text is shown.
      (NodeState.active, NodeType.story) => (node.listenFirst ? 'DİNLE' : 'OKU', true),
      (NodeState.active, NodeType.mock) => ('DENEMEYE BAŞLA', true),
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
              boxShadow: softShadow(p, tint: locked ? null : color, lift: 1.4),
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
                if (note != null && !locked) ...[
                  const SizedBox(height: 4),
                  Text(
                    note!,
                    key: const Key('lesson-card-note'),
                    style: TextStyle(color: fg, fontWeight: FontWeight.w800),
                  ),
                ],
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
                    foreground: edgeOf(color),
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

/// The host beside the lane: Çaycı Dayı (still) for adults, Pofuduk
/// (bigger, moving) in Çocuk modu.
class PathMascot extends StatelessWidget {
  const PathMascot({super.key, required this.mood, this.theme});
  final Mood mood;

  /// Topic of the unit: some topics dress the host up (a chef's hat, a
  /// captain's cap…).
  final TopicTheme? theme;

  @override
  Widget build(BuildContext context) {
    final kid = context.isKid;
    final size = kid ? 104.0 : 84.0;
    final host = kid ? Pofuduk(mood: mood, size: size) : Dayi(mood: mood, size: size, animate: false);
    return KeyedSubtree(
      key: const Key('path-mascot'),
      child: theme == null ? host : Costume(theme: theme!, size: size, kid: kid, child: host),
    );
  }
}

/// Small roadside decorations of a theme, beside the lane.
class RoadsideDecor extends StatelessWidget {
  const RoadsideDecor({super.key, required this.theme, required this.object});
  final TopicTheme theme;
  final String object;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Opacity(
      opacity: context.palette.isDark ? 0.7 : 0.85,
      child: ThemeObject(theme: theme, object: object, size: 34),
    ),
  );
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
          // Match pairs are [native, learning].
          for (final (tr, en) in ex.pairs) {
            add(en, tr);
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
          if (unit.hasGuide) ...[
            Text('Konu anlatımı', style: t.titleMedium),
            const SizedBox(height: 4),
            KeyedSubtree(key: const Key('unit-guide-text'), child: MarkdownText(unit.guide!)),
            const SizedBox(height: 18),
          ],
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
