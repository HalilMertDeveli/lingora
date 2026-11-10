import 'dart:math';

import 'package:flutter/material.dart';

import 'motion.dart';

/// Lino's mood decides its face and how it moves.
enum Mood { idle, happy, cheer, sad, think }

/// Lino: Lingora's own mascot, a round purple "speech bubble" creature with a
/// leaf sprout. Drawn entirely in code so there are no image assets.
class Mascot extends StatefulWidget {
  const Mascot({super.key, this.mood = Mood.idle, this.size = 120});
  final Mood mood;
  final double size;

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with TickerProviderStateMixin {
  /// Idle bob / cheer jump, looping.
  late final _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  /// Blink, fired at random intervals.
  late final _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));

  /// One-shot reaction when the mood changes.
  late final _react = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  final _rand = Random();
  bool _alive = true;

  @override
  void initState() {
    super.initState();
    _react.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loopsEnabled(context)) {
      if (!_loop.isAnimating) {
        _loop.repeat();
        _scheduleBlink();
      }
    } else {
      _loop.stop();
    }
  }

  void _scheduleBlink() {
    Future.delayed(Duration(milliseconds: 1800 + _rand.nextInt(2600)), () async {
      if (!_alive || !_loop.isAnimating) return;
      await _blink.forward(from: 0);
      if (_alive) await _blink.reverse();
      _scheduleBlink();
    });
  }

  @override
  void didUpdateWidget(Mascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _react.forward(from: 0);
  }

  @override
  void dispose() {
    _alive = false;
    _loop.dispose();
    _blink.dispose();
    _react.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: Listenable.merge([_loop, _blink, _react]),
        builder: (_, _) {
          final t = _loop.value;
          final r = Curves.easeOut.transform(_react.value);
          var dy = 0.0;
          var squash = 1.0;
          var tilt = 0.0;
          switch (widget.mood) {
            case Mood.cheer:
              final j = sin(t * pi * 4).abs();
              dy = -j * s * 0.12;
              squash = 1 + (1 - j) * 0.05;
            case Mood.happy:
              dy = -sin(r * pi) * s * 0.12 + sin(t * 2 * pi) * s * 0.015;
            case Mood.sad:
              dy = s * 0.03;
              tilt = sin(r * pi * 3) * 0.06 * (1 - r);
            case Mood.think:
              tilt = sin(t * 2 * pi) * 0.04;
            case Mood.idle:
              dy = sin(t * 2 * pi) * s * 0.02;
          }
          return Transform.translate(
            offset: Offset(0, dy),
            child: Transform.rotate(
              angle: tilt,
              child: Transform.scale(
                scaleX: 1 / squash,
                scaleY: squash,
                alignment: Alignment.bottomCenter,
                child: CustomPaint(
                  painter: _MascotPainter(mood: widget.mood, blink: _blink.value, wave: t),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  _MascotPainter({required this.mood, required this.blink, required this.wave});
  final Mood mood;
  final double blink;
  final double wave;

  static const _body = Color(0xFF7B5CF5);
  static const _bodyDark = Color(0xFF5A3BD6);
  static const _belly = Color(0xFFB9A8FF);
  static const _leaf = Color(0xFF34C77B);
  static const _ink = Color(0xFF231C3D);
  static const _cheek = Color(0xFFFF8FB1);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final c = Offset(w / 2, w * 0.56);
    final r = w * 0.36;

    // Shadow.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w / 2, w * 0.96), width: r * 1.5, height: w * 0.07),
      Paint()..color = Colors.black.withValues(alpha: 0.10),
    );

    // Sprout.
    final stem = Paint()
      ..color = _leaf
      ..strokeWidth = w * 0.03
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final top = Offset(w / 2, c.dy - r);
    canvas.drawLine(top, top.translate(0, -w * 0.1), stem);
    final sway = sin(wave * 2 * pi) * 0.15;
    for (final side in [-1.0, 1.0]) {
      canvas
        ..save()
        ..translate(top.dx, top.dy - w * 0.1)
        ..rotate(side * (0.7 + sway));
      canvas.drawOval(Rect.fromLTWH(0, -w * 0.035, w * 0.13, w * 0.07), Paint()..color = _leaf);
      canvas.restore();
    }

    // Feet.
    final feet = Paint()..color = _bodyDark;
    for (final side in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w / 2 + side * r * 0.45, c.dy + r * 0.95),
          width: r * 0.5,
          height: r * 0.28,
        ),
        feet,
      );
    }

    // Body with a soft gradient.
    final body = Rect.fromCircle(center: c, radius: r);
    canvas.drawOval(
      body,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.45),
          radius: 1.1,
          colors: [Color(0xFF9B83FF), _body, _bodyDark],
          stops: [0, 0.55, 1],
        ).createShader(body),
    );
    // Belly.
    canvas.drawOval(
      Rect.fromCenter(center: c.translate(0, r * 0.42), width: r * 1.1, height: r * 0.8),
      Paint()..color = _belly.withValues(alpha: 0.55),
    );

    // Arms: raised when cheering, tucked otherwise.
    final arm = Paint()
      ..color = _body
      ..strokeWidth = w * 0.07
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final side in [-1.0, 1.0]) {
      final shoulder = c.translate(side * r * 0.9, r * 0.15);
      final Offset hand;
      switch (mood) {
        case Mood.cheer:
          final flap = sin(wave * pi * 8) * 0.08;
          hand = shoulder.translate(side * r * 0.35, -r * (0.75 + flap));
        case Mood.happy:
          hand = shoulder.translate(side * r * 0.4, -r * 0.35);
        case Mood.sad:
          hand = shoulder.translate(side * r * 0.12, r * 0.45);
        case Mood.think:
          hand = side < 0
              ? shoulder.translate(r * 0.45, -r * 0.35)
              : shoulder.translate(side * r * 0.2, r * 0.35);
        case Mood.idle:
          hand = shoulder.translate(side * r * 0.25, r * 0.3);
      }
      canvas.drawLine(shoulder, hand, arm);
    }

    // Eyes.
    final eyeY = c.dy - r * 0.12;
    final eyeDx = r * 0.36;
    final eyeOpen = 1 - blink;
    for (final side in [-1.0, 1.0]) {
      final e = Offset(c.dx + side * eyeDx, eyeY);
      if (mood == Mood.happy || mood == Mood.cheer) {
        // Closed happy arcs.
        canvas.drawArc(
          Rect.fromCenter(center: e.translate(0, r * 0.05), width: r * 0.34, height: r * 0.3),
          pi,
          pi,
          false,
          Paint()
            ..color = _ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.03
            ..strokeCap = StrokeCap.round,
        );
        continue;
      }
      final eyeH = r * 0.42 * max(eyeOpen, 0.08);
      canvas.drawOval(
        Rect.fromCenter(center: e, width: r * 0.34, height: eyeH),
        Paint()..color = Colors.white,
      );
      if (eyeOpen > 0.3) {
        final look = mood == Mood.think ? Offset(r * 0.05, -r * 0.07) : Offset(0, r * 0.03);
        canvas.drawCircle(e + look, r * 0.1, Paint()..color = _ink);
        canvas.drawCircle(
          e + look.translate(-r * 0.035, -r * 0.04),
          r * 0.035,
          Paint()..color = Colors.white,
        );
      }
      if (mood == Mood.sad) {
        // Worried brows.
        canvas.drawLine(
          e.translate(-side * r * 0.15, -r * 0.4),
          e.translate(side * r * 0.12, -r * 0.3),
          Paint()
            ..color = _ink
            ..strokeWidth = w * 0.022
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Cheeks.
    for (final side in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(c.dx + side * r * 0.62, eyeY + r * 0.3),
          width: r * 0.24,
          height: r * 0.13,
        ),
        Paint()..color = _cheek.withValues(alpha: 0.7),
      );
    }

    // Mouth.
    final m = Offset(c.dx, eyeY + r * 0.36);
    final mouth = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.028
      ..strokeCap = StrokeCap.round;
    switch (mood) {
      case Mood.cheer:
      case Mood.happy:
        final open = Path()
          ..moveTo(m.dx - r * 0.22, m.dy - r * 0.04)
          ..quadraticBezierTo(m.dx, m.dy + r * 0.34, m.dx + r * 0.22, m.dy - r * 0.04)
          ..close();
        canvas.drawPath(open, Paint()..color = _ink);
        canvas.drawOval(
          Rect.fromCenter(center: m.translate(0, r * 0.12), width: r * 0.18, height: r * 0.08),
          Paint()..color = _cheek,
        );
      case Mood.sad:
        canvas.drawArc(
          Rect.fromCenter(center: m.translate(0, r * 0.1), width: r * 0.3, height: r * 0.2),
          pi * 1.1,
          pi * 0.8,
          false,
          mouth,
        );
      case Mood.think:
        canvas.drawLine(m.translate(-r * 0.1, 0), m.translate(r * 0.12, -r * 0.03), mouth);
      case Mood.idle:
        canvas.drawArc(
          Rect.fromCenter(center: m, width: r * 0.32, height: r * 0.22),
          0.15 * pi,
          0.7 * pi,
          false,
          mouth,
        );
    }
  }

  @override
  bool shouldRepaint(_MascotPainter old) => old.mood != mood || old.blink != blink || old.wave != wave;
}
