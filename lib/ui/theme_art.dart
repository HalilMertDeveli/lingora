import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/topic_themes.dart';
import '../theme.dart';

/// Drawing the topic themes (lib/data/topic_themes.dart): one SVG per object
/// under `assets/themes/<theme>/`, with the node states derived in code
/// (locked: a faded grey silhouette; current: the theme's motion).

/// Turns colours into greys (locked nodes).
const greyscale = ColorFilter.matrix([
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

/// [greyscale] with its alpha scaled by [opacity], in a single filter.
ColorFilter fadedGreyscale(double opacity) => ColorFilter.matrix([
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, opacity, 0,
]);

/// One theme object. [grey] draws it as a faded silhouette; [tint] paints it
/// in one colour (band patterns). Pictures are parsed once and cached by
/// flutter_svg, so a theme costs one load per object.
class ThemeObject extends StatelessWidget {
  const ThemeObject({
    super.key,
    required this.theme,
    required this.object,
    this.size = 48,
    this.grey = false,
    this.tint,
    this.semanticLabel,
    this.opacity = 1,
  });

  final TopicTheme theme;
  final String object;
  final double size;
  final bool grey;
  final Color? tint;
  final String? semanticLabel;

  /// Fades the picture through its colour filter (no offscreen layer).
  final double opacity;

  @override
  Widget build(BuildContext context) {
    // Grey is one colour matrix on the picture itself (greyscale + fade):
    // Opacity + ColorFiltered would each need an offscreen layer per node.
    final filter = tint != null
        ? ColorFilter.mode(tint!, BlendMode.srcIn)
        : grey
        ? fadedGreyscale((context.palette.isDark ? 0.45 : 0.55) * opacity)
        : opacity < 1
        ? ColorFilter.matrix([1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, opacity, 0])
        : null;
    final art = SvgPicture.asset(
      theme.asset(object),
      width: size,
      height: size,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      colorFilter: filter,
      placeholderBuilder: (_) => SizedBox(width: size, height: size),
    );
    return KeyedSubtree(key: ValueKey('theme-object-${theme.id}-$object'), child: art);
  }
}

/// Loads the pictures of [theme] ahead of time (the visible unit's theme;
/// the others load as they scroll into view).
Future<void> precacheTheme(TopicTheme theme) async {
  for (final o in theme.objects) {
    final loader = SvgAssetLoader(theme.asset(o));
    try {
      await svg.cache.putIfAbsent(loader.cacheKey(null), () => loader.loadBytes(null));
    } catch (_) {
      // A missing picture only shows as an empty node.
    }
  }
}

/// Applies a [ThemeMotion] to [child] for animation value [t] (0..1).
Widget applyMotion(ThemeMotion motion, double t, Widget child, Color accent) {
  final s = sin(t * pi * 2);
  return switch (motion) {
    ThemeMotion.sway => Transform.rotate(angle: s * 0.12, alignment: Alignment.bottomCenter, child: child),
    ThemeMotion.bob => Transform.translate(offset: Offset(0, -3 - s * 3), child: child),
    ThemeMotion.pulse => Transform.scale(scale: 1 + max(0.0, s) * 0.09, child: child),
    ThemeMotion.wiggle => Transform.rotate(
      // Two quick shakes, then a rest.
      angle: t < 0.3 ? sin(t / 0.3 * pi * 4) * 0.1 : 0,
      child: child,
    ),
    ThemeMotion.blink => Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Opacity(
          opacity: (0.25 + 0.45 * (s * 0.5 + 0.5)).clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: accent, blurRadius: 16, spreadRadius: 2)],
            ),
            child: const SizedBox(width: 30, height: 30),
          ),
        ),
        child,
      ],
    ),
  };
}

/// The rosette of a unit test: a ring in the theme's accent with two ribbon
/// tails and the theme's emblem in the middle.
class BadgePainter extends CustomPainter {
  BadgePainter({required this.color, required this.palette, this.dim = false, this.done = false});
  final Color color;
  final Palette palette;
  final bool dim;
  final bool done;

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final w = size.width, h = size.height;
    final c = Offset(w / 2, h * 0.42);
    final rad = min(w, h) * 0.36;
    final ring = dim ? (p.isDark ? p.surface : p.line) : color;
    final edge = dim ? p.muted.withValues(alpha: 0.6) : Color.lerp(ring, p.ink, 0.4)!;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = edge;
    // Ribbon tails.
    for (final s in [-1.0, 1.0]) {
      final tail = Path()
        ..moveTo(c.dx + s * rad * 0.2, c.dy + rad * 0.5)
        ..lineTo(c.dx + s * rad * 0.75, h * 0.98)
        ..lineTo(c.dx + s * rad * 0.42, h * 0.9)
        ..lineTo(c.dx + s * rad * 0.15, h * 0.98)
        ..close();
      canvas
        ..drawPath(tail, Paint()..color = Color.lerp(ring, Colors.black, 0.15)!)
        ..drawPath(tail, stroke);
    }
    // Scalloped ring.
    final scallop = Path();
    const n = 14;
    for (var i = 0; i <= n * 2; i++) {
      final a = i * pi / n - pi / 2;
      final r = i.isEven ? rad : rad * 0.9;
      final pt = c + Offset(cos(a), sin(a)) * r;
      i == 0 ? scallop.moveTo(pt.dx, pt.dy) : scallop.lineTo(pt.dx, pt.dy);
    }
    scallop.close();
    canvas
      ..drawPath(scallop.shift(const Offset(0, 2)), Paint()..color = Colors.black.withValues(alpha: 0.1))
      ..drawPath(scallop, Paint()..color = ring)
      ..drawPath(scallop, stroke)
      ..drawCircle(c, rad * 0.72, Paint()..color = dim ? p.card : (done ? const Color(0xFFFFF4DE) : p.card))
      ..drawCircle(c, rad * 0.72, stroke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(BadgePainter old) =>
      old.color != color || old.dim != dim || old.done != done || old.palette != palette;
}

/// A soft plate under a lesson object, so it reads on light and dark paths.
class PlatePainter extends CustomPainter {
  PlatePainter({required this.color, required this.palette, this.dim = false, this.done = false});
  final Color color;
  final Palette palette;
  final bool dim;
  final bool done;

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final c = Offset(size.width / 2, size.height * 0.46);
    final r = size.width * 0.48;
    final face = dim
        ? (p.isDark ? p.surface : p.line.withValues(alpha: 0.6))
        : Color.alphaBlend(color.withValues(alpha: p.isDark ? 0.28 : (done ? 0.22 : 0.14)), p.card);
    canvas
      ..drawOval(
        Rect.fromCenter(center: Offset(c.dx, size.height * 0.93), width: r * 1.6, height: r * 0.3),
        Paint()..color = Colors.black.withValues(alpha: 0.10),
      )
      ..drawCircle(c, r, Paint()..color = face)
      ..drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = done ? 3 : 2
          ..color = dim ? p.muted.withValues(alpha: 0.35) : color.withValues(alpha: done ? 0.9 : 0.55),
      );
  }

  @override
  bool shouldRepaint(PlatePainter old) =>
      old.color != color || old.dim != dim || old.done != done || old.palette != palette;
}

/// The host's costume: a hat (and the like) laid over Çaycı Dayı's tile or
/// on Pofuduk's head, without touching their artwork.
class Costume extends StatelessWidget {
  const Costume({super.key, required this.theme, required this.size, required this.kid, required this.child});
  final TopicTheme theme;

  /// Size of the host the costume sits on.
  final double size;
  final bool kid;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hat = theme.hat;
    if (hat == null) return child;
    final w = size * (kid ? 0.5 : 0.62);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          key: Key('costume-${theme.id}'),
          // Dayi's cap sits at ~0.22–0.42 of his tile; Pofuduk's top edge at ~0.1.
          left: kid ? size * 0.2 : size * 0.16,
          top: kid ? -size * 0.2 : -size * 0.08,
          child: Transform.rotate(
            angle: kid ? -0.18 : -0.06,
            child: ThemeObject(theme: theme, object: hat, size: w),
          ),
        ),
      ],
    );
  }
}
