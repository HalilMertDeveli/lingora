import 'dart:typed_data';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'motion.dart';

/// Dilbaz's own drawings, all vector (no assets): the thin-waisted tea glass
/// used as a path node, the double teapot (reward), the tulip (unit test), a
/// rising steam curl, the İznik tile motif and the small district scenes on
/// section cards. See docs/tasarim.md, "Çay kimliği".

/// Deep "tavşan kanı" tea, top and bottom of the glass.
const teaTop = Color(0xFFD0532A);
const teaDeep = Color(0xFF8A2810);

/// Gold rim of a finished glass and the brass of the teapot.
const teaGold = Color(0xFFD9A441);

/// Tulip red.
const tulipRed = Color(0xFFD7263D);

// ---------------------------------------------------------------------------
// Tea glass
// ---------------------------------------------------------------------------

/// Outline of the thin-waisted Turkish tea glass inside [r]: a wide rim, a
/// narrow waist, a round belly and a flat foot.
Path teaGlassPath(Rect r) {
  final cx = r.center.dx, w = r.width, y0 = r.top, h = r.height;
  double x(double f) => cx + f * w;
  double y(double f) => y0 + f * h;
  final p = Path()..moveTo(x(-0.5), y(0));
  p
    ..lineTo(x(0.5), y(0))
    ..cubicTo(x(0.46), y(0.3), x(0.24), y(0.44), x(0.24), y(0.58))
    ..cubicTo(x(0.24), y(0.7), x(0.37), y(0.76), x(0.36), y(0.89))
    ..cubicTo(x(0.35), y(0.97), x(0.3), y(1), x(0.25), y(1))
    ..lineTo(x(-0.25), y(1))
    ..cubicTo(x(-0.3), y(1), x(-0.35), y(0.97), x(-0.36), y(0.89))
    ..cubicTo(x(-0.37), y(0.76), x(-0.24), y(0.7), x(-0.24), y(0.58))
    ..cubicTo(x(-0.24), y(0.44), x(-0.46), y(0.3), x(-0.5), y(0))
    ..close();
  return p;
}

/// A tea glass on its saucer. [level] is how full it is (0 empty, 1 full),
/// [wave] (0..1) moves the tea surface, [color] tints the saucer.
class TeaGlassPainter extends CustomPainter {
  TeaGlassPainter({
    required this.level,
    required this.color,
    required this.palette,
    this.wave = 0,
    this.goldRim = false,
    this.dim = false,
  });

  final double level;
  final Color color;
  final Palette palette;
  final double wave;
  final bool goldRim;

  /// Locked: a plain, faded glass and saucer.
  final bool dim;

  /// Glass box inside a node of [size] (the saucer sits under it).
  static Rect glassRect(Size size) =>
      Rect.fromLTWH(size.width * 0.19, size.height * 0.04, size.width * 0.62, size.height * 0.78);

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final glass = glassRect(size);
    // Saucer.
    final saucerC = Offset(size.width / 2, glass.bottom + size.height * 0.02);
    final saucer = Rect.fromCenter(center: saucerC, width: size.width * 0.96, height: size.height * 0.17);
    final saucerColor = dim ? (p.isDark ? p.surface : p.line) : color;
    canvas
      ..drawOval(saucer.shift(const Offset(0, 2)), Paint()..color = Colors.black.withValues(alpha: 0.10))
      ..drawOval(saucer, Paint()..color = saucerColor)
      ..drawOval(
        Rect.fromCenter(
          center: saucerC.translate(0, -1),
          width: saucer.width * 0.62,
          height: saucer.height * 0.5,
        ),
        Paint()..color = Color.lerp(saucerColor, Colors.white, dim ? 0.25 : 0.3)!,
      );

    final outline = teaGlassPath(glass);
    // Glass body: opaque enough that the lane behind does not show through.
    canvas
      ..drawPath(outline, Paint()..color = p.card)
      ..drawPath(outline, Paint()..color = Colors.white.withValues(alpha: p.isDark ? 0.08 : 0.5));
    // Tea.
    final lv = level.clamp(0.0, 1.0);
    if (lv > 0) {
      canvas
        ..save()
        ..clipPath(outline);
      final top = glass.bottom - glass.height * 0.94 * lv;
      final surface = Path()..moveTo(glass.left, top);
      for (var i = 0; i <= 12; i++) {
        final f = i / 12;
        surface.lineTo(glass.left + glass.width * f, top + sin((f + wave) * pi * 2) * 1.6);
      }
      surface
        ..lineTo(glass.right, glass.bottom)
        ..lineTo(glass.left, glass.bottom)
        ..close();
      canvas
        ..drawPath(
          surface,
          Paint()..shader = ui.Gradient.linear(Offset(0, top), Offset(0, glass.bottom), [teaTop, teaDeep]),
        )
        ..restore();
    }
    // Outline and a highlight on the left.
    final edge = dim ? p.muted.withValues(alpha: 0.55) : Color.lerp(color, p.ink, 0.35)!;
    canvas
      ..drawPath(
        outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = edge,
      )
      ..drawPath(
        Path()
          ..moveTo(glass.left + glass.width * 0.16, glass.top + glass.height * 0.1)
          ..quadraticBezierTo(
            glass.left + glass.width * 0.22,
            glass.top + glass.height * 0.32,
            glass.left + glass.width * 0.34,
            glass.top + glass.height * 0.44,
          ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: p.isDark ? 0.35 : 0.85),
      );
    if (goldRim) {
      canvas.drawLine(
        Offset(glass.left + 1, glass.top + 1.5),
        Offset(glass.right - 1, glass.top + 1.5),
        Paint()
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = teaGold,
      );
    }
  }

  @override
  bool shouldRepaint(TeaGlassPainter old) =>
      old.level != level ||
      old.wave != wave ||
      old.color != color ||
      old.palette != palette ||
      old.goldRim != goldRim ||
      old.dim != dim;
}

// ---------------------------------------------------------------------------
// Double teapot (çaydanlık): the reward node
// ---------------------------------------------------------------------------

class TeapotPainter extends CustomPainter {
  TeapotPainter({required this.color, required this.palette, this.open = false, this.dim = false});
  final Color color;
  final Palette palette;

  /// Opened reward: the lid is lifted and two sugar cubes sit by the pot.
  final bool open;
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final w = size.width, h = size.height;
    final body = dim ? (p.isDark ? p.surface : p.line) : color;
    final shade = Color.lerp(body, Colors.black, 0.18)!;
    final edge = dim ? p.muted.withValues(alpha: 0.6) : Color.lerp(body, p.ink, 0.45)!;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = edge
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = body;

    // Lower kettle.
    final kettle = Rect.fromLTWH(w * 0.14, h * 0.52, w * 0.72, h * 0.38);
    final kettleR = RRect.fromRectAndCorners(
      kettle,
      topLeft: Radius.circular(w * 0.2),
      topRight: Radius.circular(w * 0.2),
      bottomLeft: Radius.circular(w * 0.1),
      bottomRight: Radius.circular(w * 0.1),
    );
    // Spout.
    final spout = Path()
      ..moveTo(kettle.right - 2, kettle.top + kettle.height * 0.45)
      ..quadraticBezierTo(w * 0.98, kettle.top + kettle.height * 0.4, w * 0.97, kettle.top - h * 0.04)
      ..lineTo(w * 0.92, kettle.top)
      ..quadraticBezierTo(
        w * 0.9,
        kettle.top + kettle.height * 0.3,
        kettle.right - 2,
        kettle.top + kettle.height * 0.25,
      );
    canvas
      ..drawPath(spout, fill)
      ..drawPath(spout, stroke)
      ..drawRRect(kettleR, fill)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            kettle.left,
            kettle.bottom - kettle.height * 0.28,
            kettle.width,
            kettle.height * 0.28,
          ),
          Radius.circular(w * 0.1),
        ),
        Paint()..color = shade,
      )
      ..drawRRect(kettleR, stroke);

    // Upper teapot (demlik).
    final pot = Rect.fromLTWH(w * 0.28, h * 0.24, w * 0.44, h * 0.3);
    final potR = RRect.fromRectAndRadius(pot, Radius.circular(w * 0.14));
    final lidLift = open ? h * 0.1 : 0.0;
    final lid = Rect.fromLTWH(w * 0.33, h * 0.17 - lidLift, w * 0.34, h * 0.09);
    canvas
      ..drawRRect(potR, fill)
      ..drawRRect(potR, stroke)
      ..drawOval(lid, fill)
      ..drawOval(lid, stroke)
      ..drawCircle(Offset(w / 2, lid.top - h * 0.02), w * 0.045, Paint()..color = dim ? body : teaGold)
      ..drawCircle(Offset(w / 2, lid.top - h * 0.02), w * 0.045, stroke);
    // Brass band.
    canvas.drawLine(
      Offset(kettle.left + 6, kettle.top + kettle.height * 0.25),
      Offset(kettle.right - 6, kettle.top + kettle.height * 0.25),
      Paint()
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = dim ? edge.withValues(alpha: 0.3) : teaGold,
    );
    if (open) {
      for (final (dx, dy) in [(0.04, 0.84), (0.13, 0.9)]) {
        final cube = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w * dx + 4, h * dy), width: w * 0.14, height: w * 0.14),
          const Radius.circular(2),
        );
        canvas
          ..drawRRect(cube, Paint()..color = Colors.white)
          ..drawRRect(cube, stroke..strokeWidth = 1.2);
      }
    }
  }

  @override
  bool shouldRepaint(TeapotPainter old) =>
      old.color != color || old.open != open || old.dim != dim || old.palette != palette;
}

// ---------------------------------------------------------------------------
// Tulip (lale): the unit test badge
// ---------------------------------------------------------------------------

class TulipPainter extends CustomPainter {
  TulipPainter({required this.color, required this.palette, this.bloom = 1, this.dim = false});
  final Color color;
  final Palette palette;

  /// 0: closed bud, 1: open flower.
  final double bloom;
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final w = size.width, h = size.height;
    final cx = w / 2;
    final petal = dim ? (p.isDark ? p.surface : p.line) : color;
    final leaf = dim ? (p.isDark ? p.surface : p.line) : const Color(0xFF3E8E4E);
    final edge = dim ? p.muted.withValues(alpha: 0.6) : Color.lerp(petal, p.ink, 0.4)!;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = edge;
    // Stem and leaves.
    canvas.drawLine(
      Offset(cx, h * 0.5),
      Offset(cx, h * 0.96),
      Paint()
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = leaf,
    );
    for (final s in [-1.0, 1.0]) {
      final l = Path()
        ..moveTo(cx, h * 0.95)
        ..quadraticBezierTo(cx + s * w * 0.42, h * 0.82, cx + s * w * 0.36, h * 0.55)
        ..quadraticBezierTo(cx + s * w * 0.14, h * 0.72, cx, h * 0.95);
      canvas.drawPath(l, Paint()..color = leaf);
    }
    // Three pointed petals: sides open with [bloom].
    final open = 0.08 + 0.1 * bloom;
    for (final s in [-1.0, 1.0]) {
      final side = Path()
        ..moveTo(cx, h * 0.56)
        ..quadraticBezierTo(cx + s * w * (0.3 + open), h * 0.5, cx + s * w * (0.2 + open), h * 0.12)
        ..quadraticBezierTo(cx + s * w * 0.1, h * 0.3, cx, h * 0.56);
      canvas
        ..drawPath(side, Paint()..color = Color.lerp(petal, Colors.black, 0.12)!)
        ..drawPath(side, stroke);
    }
    final mid = Path()
      ..moveTo(cx, h * 0.58)
      ..quadraticBezierTo(cx - w * 0.24, h * 0.42, cx - w * 0.1, h * 0.14)
      ..lineTo(cx, h * 0.24)
      ..lineTo(cx + w * 0.1, h * 0.14)
      ..quadraticBezierTo(cx + w * 0.24, h * 0.42, cx, h * 0.58);
    canvas
      ..drawPath(mid, Paint()..color = petal)
      ..drawPath(mid, stroke);
  }

  @override
  bool shouldRepaint(TulipPainter old) =>
      old.color != color || old.bloom != bloom || old.dim != dim || old.palette != palette;
}

// ---------------------------------------------------------------------------
// Steam
// ---------------------------------------------------------------------------

/// Three soft curls rising from a fresh glass. Loops only while animations
/// are allowed; with reduced motion it draws nothing.
class Steam extends StatefulWidget {
  const Steam({super.key, this.width = 40, this.height = 30, this.color});
  final double width;
  final double height;
  final Color? color;

  @override
  State<Steam> createState() => _SteamState();
}

class _SteamState extends State<Steam> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loopsEnabled(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!loopsEnabled(context)) return SizedBox(width: widget.width, height: widget.height);
    final p = context.palette;
    final color = widget.color ?? (p.isDark ? Colors.white : p.muted);
    return SizedBox(
      key: const Key('steam'),
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(painter: _SteamPainter(_c.value, color)),
      ),
    );
  }
}

class _SteamPainter extends CustomPainter {
  _SteamPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (var k = 0; k < 3; k++) {
      final lt = (t + k / 3) % 1;
      final x = size.width * (0.25 + 0.25 * k);
      final y = size.height * (1 - lt * 0.6);
      final len = size.height * 0.55;
      final path = Path()..moveTo(x, y);
      for (var i = 1; i <= 10; i++) {
        final f = i / 10;
        path.lineTo(x + sin(f * pi * 2 + lt * pi * 2 + k) * size.width * 0.07, y - f * len);
      }
      final a = sin(lt * pi) * 0.55;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: a),
      );
    }
  }

  @override
  bool shouldRepaint(_SteamPainter old) => old.t != t || old.color != color;
}

// ---------------------------------------------------------------------------
// İznik tile motif
// ---------------------------------------------------------------------------

/// A row of four-petal İznik tile motifs, drawn faintly over a band.
class CiniPainter extends CustomPainter {
  CiniPainter({required this.color, this.cell = 26, this.start = 0});
  final Color color;
  final double cell;

  /// Share of the width (from the left) left empty; motifs fade in after it.
  final double start;

  @override
  void paint(Canvas canvas, Size size) {
    for (var x = cell / 2; x < size.width + cell; x += cell) {
      final f = start >= 1 ? 1.0 : ((x / size.width - start) / (1 - start)).clamp(0.0, 1.0);
      if (f <= 0) continue;
      final c0 = color.withValues(alpha: color.a * f);
      final fill = Paint()..color = c0;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = c0;
      for (var y = cell / 2; y < size.height + cell; y += cell) {
        final c = Offset(x, y);
        for (var k = 0; k < 4; k++) {
          final a = k * pi / 2 + pi / 4;
          final tip = c + Offset(cos(a), sin(a)) * cell * 0.38;
          final petal = Path()
            ..moveTo(c.dx, c.dy)
            ..quadraticBezierTo(
              c.dx + cos(a + 0.6) * cell * 0.3,
              c.dy + sin(a + 0.6) * cell * 0.3,
              tip.dx,
              tip.dy,
            )
            ..quadraticBezierTo(
              c.dx + cos(a - 0.6) * cell * 0.3,
              c.dy + sin(a - 0.6) * cell * 0.3,
              c.dx,
              c.dy,
            );
          canvas.drawPath(petal, fill);
        }
        canvas.drawCircle(c, cell * 0.08, ring);
        canvas.drawCircle(Offset(x + cell / 2, y + cell / 2), cell * 0.06, fill);
      }
    }
  }

  @override
  bool shouldRepaint(CiniPainter old) => old.color != color || old.cell != cell || old.start != start;
}

// ---------------------------------------------------------------------------
// Path road
// ---------------------------------------------------------------------------

/// A soft cobbled lane through [points] (node centres), drawn as a smooth
/// S-curve with a dashed middle line.
class LanePainter extends CustomPainter {
  LanePainter({required this.points, required this.lane, required this.dash, this.done = 0});
  final List<Offset> points;
  final Color lane;
  final Color dash;

  /// How many segments from the start are already walked (drawn in [dash]).
  final int done;

  static Path smooth(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      final my = (b.dy - a.dy) / 2;
      path.cubicTo(a.dx, a.dy + my, b.dx, b.dy - my, b.dx, b.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = smooth(points);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 30
        ..strokeCap = StrokeCap.round
        ..color = lane,
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = dash;
    // All dashes in one draw call: each dash is a short straight line, and
    // the endpoints are measured once per lane shape (not on every frame).
    canvas.drawRawPoints(ui.PointMode.lines, _dashes(points, path), stroke);
  }

  static final _dashCache = <String, Float32List>{};

  static Float32List _dashes(List<Offset> pts, Path path) {
    final key = pts.map((o) => '${o.dx.toStringAsFixed(1)},${o.dy.toStringAsFixed(1)}').join(';');
    return _dashCache[key] ??= () {
      if (_dashCache.length > 400) _dashCache.clear();
      final out = <double>[];
      for (final m in path.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 16) {
          final a = m.getTangentForOffset(d)?.position;
          final b = m.getTangentForOffset(min(d + 8, m.length))?.position;
          if (a == null || b == null) continue;
          out.addAll([a.dx, a.dy, b.dx, b.dy]);
        }
      }
      return Float32List.fromList(out);
    }();
  }

  @override
  bool shouldRepaint(LanePainter old) =>
      old.lane != lane || old.dash != dash || old.points.length != points.length || old.points != points;
}

// ---------------------------------------------------------------------------
// District scenes for section cards
// ---------------------------------------------------------------------------

/// Places the sections walk through: Bölüm 1 is the neighbourhood, 2 the
/// bazaar, 3 the ferry, and so on.
enum District {
  mahalle('Mahalle'),
  carsi('Çarşı'),
  vapur('Vapur'),
  ofis('Ofis'),
  yolculuk('Yolculuk'),
  kutuphane('Kütüphane'),
  toplanti('Toplantı'),
  sahne('Sahne');

  const District(this.label);
  final String label;

  /// District of the 1-based section [index] (wraps after eight).
  static District of(int index) => values[(max(1, index) - 1) % values.length];
}

/// A small flat illustration strip of a [district], in the card's [color].
class DistrictPainter extends CustomPainter {
  DistrictPainter({required this.district, required this.color, required this.palette});
  final District district;
  final Color color;
  final Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final w = size.width, h = size.height;
    final ground = h * 0.86;
    final c1 = color;
    final c2 = Color.lerp(color, p.card, 0.45)!;
    final c3 = Color.lerp(color, p.card, 0.75)!;
    final ink = Color.lerp(color, p.ink, 0.55)!;
    final f = Paint();
    // Sky wash and ground line.
    canvas
      ..drawRect(Offset.zero & size, f..color = Color.lerp(p.card, color, p.isDark ? 0.12 : 0.07)!)
      ..drawRect(Rect.fromLTWH(0, ground, w, h - ground), f..color = c3);
    void sun(double x) =>
        canvas.drawCircle(Offset(x, h * 0.28), h * 0.13, Paint()..color = teaGold.withValues(alpha: 0.7));
    switch (district) {
      case District.mahalle:
        sun(w * 0.85);
        for (var i = 0; i < 6; i++) {
          final x = i * w / 5.5;
          final bw = w / 7, bh = h * (0.36 + (i % 3) * 0.1);
          canvas.drawRect(Rect.fromLTWH(x, ground - bh, bw, bh), f..color = i.isEven ? c1 : c2);
          canvas.drawPath(
            Path()
              ..moveTo(x - 3, ground - bh)
              ..lineTo(x + bw / 2, ground - bh - h * 0.14)
              ..lineTo(x + bw + 3, ground - bh)
              ..close(),
            f..color = ink,
          );
          canvas.drawRect(
            Rect.fromLTWH(x + bw * 0.35, ground - bh * 0.6, bw * 0.3, bh * 0.25),
            f..color = teaGold,
          );
        }
      case District.carsi:
        for (var i = 0; i < 7; i++) {
          final x = i * w / 6.2;
          final bw = w / 7;
          canvas.drawRect(Rect.fromLTWH(x, ground - h * 0.4, bw, h * 0.4), f..color = c2);
          for (var s = 0; s < 4; s++) {
            canvas.drawRect(
              Rect.fromLTWH(x + s * bw / 4, ground - h * 0.52, bw / 4, h * 0.14),
              f..color = s.isEven ? c1 : p.card,
            );
          }
        }
        canvas.drawArc(
          Rect.fromCircle(center: Offset(w * 0.5, ground - h * 0.4), radius: h * 0.24),
          pi,
          pi,
          true,
          f..color = ink,
        );
      case District.vapur:
        sun(w * 0.15);
        final sea = Path()..moveTo(0, ground - h * 0.08);
        for (var x = 0.0; x <= w; x += 8) {
          sea.lineTo(x, ground - h * 0.08 + sin(x / 9) * 2.5);
        }
        sea
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
        canvas.drawPath(sea, f..color = p.info.withValues(alpha: 0.45));
        final bx = w * 0.42;
        canvas
          ..drawPath(
            Path()
              ..moveTo(bx, ground - h * 0.3)
              ..lineTo(bx + w * 0.32, ground - h * 0.3)
              ..lineTo(bx + w * 0.28, ground - h * 0.1)
              ..lineTo(bx + w * 0.04, ground - h * 0.1)
              ..close(),
            f..color = p.card,
          )
          ..drawRect(Rect.fromLTWH(bx + w * 0.06, ground - h * 0.44, w * 0.18, h * 0.14), f..color = c2)
          ..drawRect(Rect.fromLTWH(bx + w * 0.14, ground - h * 0.62, w * 0.04, h * 0.18), f..color = c1);
        for (final gx in [0.72, 0.8]) {
          canvas.drawArc(
            Rect.fromCenter(center: Offset(w * gx, h * 0.25), width: 10, height: 6),
            pi,
            pi,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = ink,
          );
        }
      case District.ofis:
        for (var i = 0; i < 5; i++) {
          final x = w * 0.04 + i * w / 5;
          final bh = h * (0.5 + ((i * 37) % 4) * 0.1);
          final bw = w / 6.5;
          canvas.drawRect(Rect.fromLTWH(x, ground - bh, bw, bh), f..color = i.isEven ? c1 : c2);
          for (var r = 0; r < 4; r++) {
            for (var c = 0; c < 2; c++) {
              canvas.drawRect(
                Rect.fromLTWH(x + bw * (0.18 + c * 0.42), ground - bh + 6 + r * bh / 4.5, bw * 0.22, bh / 9),
                f..color = (r + c + i).isEven ? teaGold : p.card.withValues(alpha: 0.7),
              );
            }
          }
        }
      case District.yolculuk:
        sun(w * 0.8);
        canvas.drawPath(
          Path()
            ..moveTo(0, ground)
            ..lineTo(w * 0.22, h * 0.3)
            ..lineTo(w * 0.42, ground)
            ..moveTo(w * 0.3, ground)
            ..lineTo(w * 0.5, h * 0.42)
            ..lineTo(w * 0.7, ground),
          f..color = c2,
        );
        final bus = Rect.fromLTWH(w * 0.56, ground - h * 0.3, w * 0.3, h * 0.24);
        canvas.drawRRect(RRect.fromRectAndRadius(bus, const Radius.circular(4)), f..color = c1);
        for (var i = 0; i < 3; i++) {
          canvas.drawRect(
            Rect.fromLTWH(
              bus.left + 4 + i * bus.width / 3.4,
              bus.top + 4,
              bus.width / 4.5,
              bus.height * 0.35,
            ),
            f..color = p.card,
          );
        }
        for (final wx in [0.62, 0.8]) {
          canvas.drawCircle(Offset(w * wx, ground - 1), h * 0.06, f..color = ink);
        }
      case District.kutuphane:
        canvas.drawRect(Rect.fromLTWH(w * 0.05, h * 0.18, w * 0.9, ground - h * 0.18), f..color = c3);
        final r = Random(7);
        for (var shelf = 0; shelf < 3; shelf++) {
          final sy = h * 0.18 + (shelf + 1) * (ground - h * 0.18) / 3;
          var x = w * 0.07;
          while (x < w * 0.92) {
            final bw = 4.0 + r.nextInt(5);
            final bh = (ground - h * 0.18) / 3 * (0.6 + r.nextDouble() * 0.3);
            canvas.drawRect(
              Rect.fromLTWH(x, sy - bh, bw, bh),
              f..color = [c1, c2, ink, teaGold, p.info][r.nextInt(5)],
            );
            x += bw + 1.5;
          }
          canvas.drawRect(Rect.fromLTWH(w * 0.05, sy - 1, w * 0.9, 2), f..color = ink);
        }
      case District.toplanti:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.2, ground - h * 0.28, w * 0.6, h * 0.08),
            const Radius.circular(3),
          ),
          f..color = ink,
        );
        for (var i = 0; i < 5; i++) {
          final x = w * (0.26 + i * 0.12);
          canvas
            ..drawCircle(Offset(x, ground - h * 0.48), h * 0.08, f..color = i.isEven ? c1 : c2)
            ..drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(x - h * 0.09, ground - h * 0.4, h * 0.18, h * 0.12),
                const Radius.circular(4),
              ),
              f..color = i.isEven ? c1 : c2,
            );
        }
        for (final (bx, by) in [(0.12, 0.2), (0.78, 0.14)]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(w * bx, h * by, w * 0.12, h * 0.18),
              const Radius.circular(5),
            ),
            f..color = p.card,
          );
        }
      case District.sahne:
        canvas
          ..drawRect(Rect.fromLTWH(w * 0.12, ground - h * 0.12, w * 0.76, h * 0.12), f..color = ink)
          ..drawPath(
            Path()
              ..moveTo(w * 0.5, 0)
              ..lineTo(w * 0.36, ground - h * 0.12)
              ..lineTo(w * 0.64, ground - h * 0.12)
              ..close(),
            f..color = teaGold.withValues(alpha: 0.35),
          );
        for (final s in [0.0, 1.0]) {
          final x = s == 0 ? 0.0 : w * 0.82;
          canvas.drawRect(Rect.fromLTWH(x, 0, w * 0.18, ground), f..color = c1);
          for (var k = 1; k < 4; k++) {
            canvas.drawLine(
              Offset(x + k * w * 0.045, 0),
              Offset(x + k * w * 0.045, ground),
              Paint()
                ..strokeWidth = 1
                ..color = ink.withValues(alpha: 0.4),
            );
          }
        }
        canvas.drawCircle(Offset(w * 0.5, ground - h * 0.3), h * 0.1, f..color = c2);
    }
  }

  @override
  bool shouldRepaint(DistrictPainter old) =>
      old.district != district || old.color != color || old.palette != palette;
}
