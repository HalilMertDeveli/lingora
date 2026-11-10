import 'dart:math';

import 'package:flutter/material.dart';

import '../models/grammar_lesson.dart';

/// Past–now–future line showing when the action happens. Draws itself in.
class TenseTimeline extends StatelessWidget {
  const TenseTimeline({super.key, required this.kind, this.color = const Color(0xFF6C4CF1)});
  final TimelineKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 1100),
    curve: Curves.easeOutCubic,
    builder: (_, t, _) =>
        CustomPaint(size: const Size(double.infinity, 120), painter: _TimelinePainter(kind, t, color)),
  );
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.kind, this.t, this.color);
  final TimelineKind kind;
  final double t;
  final Color color;

  static const _muted = Color(0xFF8A8799);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final y = size.height * 0.45;
    double x(double f) => 12 + (w - 24) * f;

    // Axis with arrow head, drawn left to right.
    final axis = Paint()
      ..color = const Color(0xFFD3D1DC)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final end = x(min(1, t * 1.4));
    canvas.drawLine(Offset(x(0), y), Offset(end, y), axis);
    if (t > 0.7) {
      canvas.drawPath(
        Path()
          ..moveTo(x(1) + 4, y)
          ..lineTo(x(1) - 8, y - 7)
          ..lineTo(x(1) - 8, y + 7)
          ..close(),
        Paint()..color = const Color(0xFFD3D1DC),
      );
    }

    // "Now" marker.
    final nowPaint = Paint()
      ..color = const Color(0xFFFF7A1A)
      ..strokeWidth = 3;
    canvas.drawLine(Offset(x(0.5), y - 26), Offset(x(0.5), y + 26), nowPaint);

    for (final (label, f) in [('GEÇMİŞ', 0.18), ('ŞİMDİ', 0.5), ('GELECEK', 0.82)]) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: label == 'ŞİMDİ' ? const Color(0xFFFF7A1A) : _muted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x(f) - tp.width / 2, y + 32));
    }

    final p = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
    if (p == 0) return;
    final main = Paint()..color = color;
    final soft = Paint()..color = color.withValues(alpha: 0.35);
    final bar = Paint()
      ..color = color
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    void dot(double f, {Paint? paint, double r = 9}) =>
        canvas.drawCircle(Offset(x(f), y), r * p, paint ?? main);
    void span(double a, double b) => canvas.drawLine(Offset(x(a), y), Offset(x(a + (b - a) * p), y), bar);
    void arrow(double a, double b) {
      final to = x(a + (b - a) * p);
      final pen = Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(x(a), y - 6)
        ..quadraticBezierTo((x(a) + to) / 2, y - 34, to, y - 8);
      canvas.drawPath(path, pen);
    }

    switch (kind) {
      case TimelineKind.pastPoint:
        dot(0.25);
      case TimelineKind.pastSpan:
        span(0.12, 0.38);
        dot(0.25, r: 6, paint: Paint()..color = Colors.white);
      case TimelineKind.now:
        span(0.43, 0.57);
      case TimelineKind.habit:
        for (final f in [0.08, 0.22, 0.36, 0.5, 0.64, 0.78, 0.92]) {
          dot(f, r: 6);
        }
      case TimelineKind.pastToNow:
        span(0.2, 0.5);
        dot(0.2, r: 7);
      case TimelineKind.beforePast:
        dot(0.36, paint: soft);
        dot(0.16);
        arrow(0.16, 0.36);
      case TimelineKind.futurePoint:
        dot(0.75);
      case TimelineKind.futureSpan:
        span(0.62, 0.88);
      case TimelineKind.beforeFuture:
        dot(0.86, paint: soft);
        dot(0.68);
        arrow(0.68, 0.86);
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => old.t != t || old.kind != kind;
}
