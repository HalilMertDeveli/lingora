import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Looping animations (pulses, idle mascot) are skipped when the system asks
/// for reduced motion. Tests turn this on so `pumpAndSettle` can finish.
bool loopsEnabled(BuildContext context) => !MediaQuery.disableAnimationsOf(context);

abstract final class Haptics {
  static void tap() => HapticFeedback.selectionClick();
  static void success() => HapticFeedback.lightImpact();
  static void error() => HapticFeedback.heavyImpact();
}

/// Darker shade of [c] used for the 3D "edge" under buttons and cards.
Color edgeOf(Color c) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness - 0.14).clamp(0.0, 1.0)).toColor();
}

/// Turkish-aware sentence case for all-caps labels: "ŞİMDİLİK ÇIK" →
/// "Şimdilik çık". Labels that aren't all caps are returned unchanged.
String sentenceCase(String s) {
  if (s.isEmpty || s != s.toUpperCase() || s == s.toLowerCase()) return s;
  // Loanwords written with a dotless capital I (PREMIUM) keep their English i.
  String lower(String x) =>
      x.startsWith('PREMIUM') ? x.toLowerCase() : x.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
  // Keep short acronyms such as XP, LGS, YDS.
  final words = s
      .split(' ')
      .map((w) => RegExp(r'^(XP|LGS|YDS|YÖKDİL|A1|A2|B1|B2|C1)$').hasMatch(w) ? w : lower(w));
  final out = words.join(' ');
  final first = switch (out[0]) {
    'i' => 'İ',
    'ı' => 'I',
    final c => c.toUpperCase(),
  };
  return first + out.substring(1);
}

/// Primary action button. Kid mode: chunky button with a darker bottom edge
/// that sinks when pressed. Adult mode: flat, refined button in sentence case.
class PressableButton extends StatefulWidget {
  const PressableButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.foreground,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? foreground;
  final bool outlined;

  @override
  State<PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<PressableButton> {
  static const _depth = 5.0;
  bool _down = false;

  void _set(bool v) {
    if (widget.onPressed != null && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lingora;
    final p = lt.palette;
    final enabled = widget.onPressed != null;
    final base = widget.color ?? p.primary;
    final onBase =
        widget.foreground ?? (widget.color == null ? p.onPrimary : (lt.isKid ? Colors.white : onColor(base)));
    final disabledFace = p.isDark ? p.surface : p.line;
    final disabledFg = p.muted;
    final kid = lt.isKid;

    final Widget body;
    if (kid) {
      final face = widget.outlined ? p.card : (enabled ? base : disabledFace);
      final edge = widget.outlined
          ? p.edge
          : (enabled ? edgeOf(base) : Color.alphaBlend(p.edge, disabledFace));
      final fg = widget.outlined ? base : (enabled ? onBase : disabledFg);
      final offset = _down ? _depth : 0.0;
      body = SizedBox(
        height: 54 + _depth,
        child: Stack(
          children: [
            Positioned.fill(
              top: _depth,
              child: DecoratedBox(
                decoration: BoxDecoration(color: edge, borderRadius: BorderRadius.circular(Radii.lg)),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 70),
              left: 0,
              right: 0,
              top: offset,
              height: 54,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: face,
                  borderRadius: BorderRadius.circular(Radii.lg),
                  border: widget.outlined ? Border.all(color: edge, width: 2) : null,
                ),
                child: Text(
                  widget.label,
                  style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.6),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      final face = widget.outlined
          ? (_down ? p.surface : Colors.transparent)
          : (enabled
                ? (_down ? Color.alphaBlend(Colors.black.withValues(alpha: 0.12), base) : base)
                : disabledFace);
      final fg = widget.outlined ? (enabled ? p.ink : disabledFg) : (enabled ? onBase : disabledFg);
      body = AnimatedContainer(
        duration: AppDurations.fast,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: face,
          borderRadius: BorderRadius.circular(Radii.md),
          border: widget.outlined ? Border.all(color: p.line) : null,
        ),
        child: Text(
          sentenceCase(widget.label),
          style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.1),
        ),
      );
    }

    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: enabled
            ? () {
                Haptics.tap();
                widget.onPressed!();
              }
            : null,
        child: body,
      ),
    );
  }
}

/// Shakes its child horizontally every time [trigger] changes.
class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child, this.distance = 10});
  final int trigger;
  final Widget child;
  final double distance;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(Shake old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) {
      final t = _c.value;
      final dx = sin(t * pi * 6) * widget.distance * (context.isKid ? 1 : 0.5) * (1 - t);
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
    child: widget.child,
  );
}

/// Scales and fades its child in after [delay].
class PopIn extends StatefulWidget {
  const PopIn({super.key, required this.child, this.delay = Duration.zero, this.from = 0.6});
  final Widget child;
  final Duration delay;
  final double from;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Adult mode: a quick fade + short slide, with half the stagger.
    final delay = context.isKid ? widget.delay : widget.delay ~/ 2;
    if (!context.isKid) _c.duration = const Duration(milliseconds: 260);
    if (delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!context.isKid) {
      final t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: t,
        child: AnimatedBuilder(
          animation: t,
          builder: (_, child) => Transform.translate(offset: Offset(0, 8 * (1 - t.value)), child: child),
          child: widget.child,
        ),
      );
    }
    final scale = CurvedAnimation(parent: _c, curve: Curves.elasticOut);
    final fade = CurvedAnimation(parent: _c, curve: const Interval(0, 0.4));
    return FadeTransition(
      opacity: fade,
      child: AnimatedBuilder(
        animation: scale,
        builder: (_, child) =>
            Transform.scale(scale: widget.from + (1 - widget.from) * scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}

/// Gentle repeating "breathing" scale, used to draw the eye to the next step.
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.child, this.amount = 0.06, this.enabled = true});
  final Widget child;
  final double amount;
  final bool enabled;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Pulse old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.enabled && loopsEnabled(context) && context.isKid;
    if (run && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!run && _c.isAnimating) {
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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) =>
        Transform.scale(scale: 1 + widget.amount * Curves.easeInOut.transform(_c.value), child: child),
    child: widget.child,
  );
}

/// Number that counts up from [from] to [value].
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    this.from = 0,
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  final int value;
  final int from;
  final String prefix;
  final String suffix;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: from.toDouble(), end: value.toDouble()),
    duration: duration,
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => Text('$prefix${v.round()}$suffix', style: style),
  );
}

/// One-shot confetti burst drawn over [child].
class Confetti extends StatefulWidget {
  const Confetti({super.key, required this.child, this.active = true});
  final Widget child;
  final bool active;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  final _pieces = <_Piece>[];

  @override
  void initState() {
    super.initState();
    final r = Random();
    const colors = [
      Color(0xFF6C4CF1),
      Color(0xFFFFB020),
      Color(0xFF1FA971),
      Color(0xFFE5484D),
      Color(0xFF2FA4FF),
      Color(0xFFFF7A1A),
    ];
    for (var i = 0; i < 90; i++) {
      _pieces.add(
        _Piece(
          x: r.nextDouble(),
          vx: (r.nextDouble() - 0.5) * 0.5,
          vy: 0.6 + r.nextDouble() * 0.9,
          spin: (r.nextDouble() - 0.5) * 14,
          size: 6 + r.nextDouble() * 7,
          color: colors[r.nextInt(colors.length)],
          delay: r.nextDouble() * 0.25,
          round: r.nextBool(),
        ),
      );
    }
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Confetti is a Çocuk modu treat; adult mode celebrates quietly.
    if (!_started && widget.active && context.isKid) _c.forward();
    _started = true;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      if (context.isKid)
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) => _c.isAnimating
                  ? CustomPaint(painter: _ConfettiPainter(_pieces, _c.value))
                  : const SizedBox.shrink(),
            ),
          ),
        ),
    ],
  );
}

class _Piece {
  _Piece({
    required this.x,
    required this.vx,
    required this.vy,
    required this.spin,
    required this.size,
    required this.color,
    required this.delay,
    required this.round,
  });
  final double x, vx, vy, spin, size, delay;
  final Color color;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);
  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in pieces) {
      final lt = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (lt <= 0) continue;
      final x = (p.x + p.vx * lt) * size.width;
      // Start just above the screen and fall with a little gravity.
      final y = -20 + (p.vy * lt + 0.6 * lt * lt) * size.height;
      paint.color = p.color.withValues(alpha: lt > 0.8 ? (1 - lt) * 5 : 1);
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(p.spin * lt);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// Progress bar. Kid mode: thick rounded fill with a glossy highlight and a
/// springy growth. Adult mode: thin flat bar (at most 8 px) that eases in.
class GlossyProgress extends StatelessWidget {
  const GlossyProgress({super.key, required this.value, required this.color, this.height = 16});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (!context.isKid) {
      final h = height.clamp(4.0, 8.0);
      return TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Container(
          height: h,
          decoration: BoxDecoration(
            color: p.isDark ? p.surface : p.line,
            borderRadius: BorderRadius.circular(h),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: v.clamp(0.0, 1.0),
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(h)),
            ),
          ),
        ),
      );
    }
    return _kid(p);
  }

  Widget _kid(Palette p) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.clamp(0.0, 1.0)),
    duration: const Duration(milliseconds: 450),
    curve: Curves.easeOutBack,
    builder: (_, v, _) => Container(
      height: height,
      decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(height)),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: v.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height)),
          padding: EdgeInsets.fromLTRB(height * 0.5, height * 0.22, height * 0.5, 0),
          alignment: Alignment.topCenter,
          child: v > 0.04
              ? Container(
                  height: height * 0.22,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(height),
                  ),
                )
              : null,
        ),
      ),
    ),
  );
}
