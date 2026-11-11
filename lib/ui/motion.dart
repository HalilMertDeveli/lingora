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

/// Answer and celebration feedback: a light vibration always, plus the
/// platform's own short click when sounds are on (Profil > Görünüm). Dilbaz
/// ships no sound files; without a platform sound only the vibration runs.
abstract final class SessionFx {
  /// Mirrors `AppSettings.sound`; set by the app root on every build.
  static bool sound = true;

  static void _click() {
    if (sound) SystemSound.play(SystemSoundType.click);
  }

  static void correct() {
    HapticFeedback.lightImpact();
    _click();
  }

  static void wrong() {
    HapticFeedback.mediumImpact();
  }

  static void celebrate() {
    HapticFeedback.mediumImpact();
    _click();
  }
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
  static const _adultDepth = 4.0;
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

    // Both modes: a rounded pill standing on a darker lip that sinks while
    // pressed. Kid mode is chunkier and keeps capitals.
    final depth = kid ? _depth : _adultDepth;
    final height = kid ? 54.0 : 50.0;
    final face = widget.outlined ? p.card : (enabled ? base : disabledFace);
    final edge = widget.outlined
        ? (p.isDark ? p.edge : p.line)
        : (enabled ? edgeOf(base) : Color.alphaBlend(p.edge.withValues(alpha: 0.6), disabledFace));
    final fg = widget.outlined
        ? (enabled ? (kid ? base : p.ink) : disabledFg)
        : (enabled ? onBase : disabledFg);
    final radius = BorderRadius.circular(height / 2);
    final offset = _down ? depth : 0.0;
    final body = SizedBox(
      height: height + depth,
      child: Stack(
        children: [
          Positioned.fill(
            top: depth,
            child: DecoratedBox(
              decoration: BoxDecoration(color: edge, borderRadius: radius),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 70),
            left: 0,
            right: 0,
            top: offset,
            height: height,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: face,
                borderRadius: radius,
                border: widget.outlined ? Border.all(color: edge, width: 2) : null,
              ),
              child: Text(
                kid ? widget.label : sentenceCase(widget.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: kid
                    ? TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.6)
                    : TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.2),
              ),
            ),
          ),
        ],
      ),
    );

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
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 425));

  /// Keyframes of the wrong-answer shake (5 steps of 85 ms).
  static const _keys = [0.0, 15.0, -12.0, 9.0, -6.0, 0.0];

  @override
  void didUpdateWidget(Shake old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !MediaQuery.disableAnimationsOf(context)) _c.forward(from: 0);
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
      final pos = t * (_keys.length - 1);
      final i = pos.floor().clamp(0, _keys.length - 2);
      final k = _keys[i] + (_keys[i + 1] - _keys[i]) * (pos - i);
      final dx = k / 15 * widget.distance * (context.isKid ? 1 : 0.6);
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
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
      return;
    }
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
    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration,
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => Text('$prefix${v.round()}$suffix', style: style),
  );
}

/// One-shot confetti burst drawn over [child] (our own painter, no assets).
///
/// Paper pieces shoot up from just below the top centre, spread out, then
/// fall and flutter (each piece flips by squashing its width). Colours come
/// from the active palette. Nothing is drawn when animations are reduced.
class Confetti extends StatefulWidget {
  const Confetti({super.key, required this.child, this.active = true, this.pieces = 110});
  final Widget child;
  final bool active;
  final int pieces;

  /// Length of one burst.
  static const duration = Duration(milliseconds: 2800);

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Confetti.duration);
  final _pieces = <ConfettiPiece>[];
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.active || MediaQuery.disableAnimationsOf(context)) return;
    final p = context.palette;
    final colors = [p.primary, p.success, p.accent, p.info, p.streak, p.mascot, p.error];
    final r = Random();
    for (var i = 0; i < widget.pieces; i++) {
      final angle = -pi / 2 + (r.nextDouble() - 0.5) * pi * 0.9;
      final speed = 0.55 + r.nextDouble() * 0.75;
      _pieces.add(
        ConfettiPiece(
          x: 0.5 + (r.nextDouble() - 0.5) * 0.3,
          vx: cos(angle) * speed * 0.7,
          vy: sin(angle) * speed,
          spin: (r.nextDouble() - 0.5) * 12,
          flip: 4 + r.nextDouble() * 8,
          size: 7 + r.nextDouble() * 7,
          color: colors[r.nextInt(colors.length)],
          delay: r.nextDouble() * 0.12,
          shape: r.nextInt(3),
        ),
      );
    }
    _c.forward();
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
      if (_pieces.isNotEmpty)
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) => _c.isAnimating
                  ? CustomPaint(key: const Key('confetti'), painter: ConfettiPainter(_pieces, _c.value))
                  : const SizedBox.shrink(),
            ),
          ),
        ),
    ],
  );
}

class ConfettiPiece {
  ConfettiPiece({
    required this.x,
    required this.vx,
    required this.vy,
    required this.spin,
    required this.flip,
    required this.size,
    required this.color,
    required this.delay,
    required this.shape,
  });
  final double x, vx, vy, spin, flip, size, delay;
  final Color color;

  /// 0: ribbon, 1: square, 2: dot.
  final int shape;
}

/// Paints confetti pieces at time [t] (0..1) of a burst.
class ConfettiPainter extends CustomPainter {
  ConfettiPainter(this.pieces, this.t);
  final List<ConfettiPiece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in pieces) {
      final lt = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (lt <= 0) continue;
      // Launch from 28 % down the screen, decelerate (drag), then fall.
      final drag = 1 - pow(1 - lt, 2.2).toDouble();
      final x = (p.x + p.vx * drag * 0.6 + sin(lt * p.flip) * 0.015) * size.width;
      final y = (0.28 + p.vy * drag * 0.45 + 1.1 * lt * lt) * size.height;
      final fade = lt > 0.75 ? (1 - lt) * 4 : 1.0;
      paint.color = p.color.withValues(alpha: fade.clamp(0.0, 1.0));
      final squash = cos(lt * p.flip * 2).abs().clamp(0.15, 1.0);
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(p.spin * lt);
      switch (p.shape) {
        case 0:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: p.size * 0.45 * squash, height: p.size * 1.4),
              const Radius.circular(2),
            ),
            paint,
          );
        case 1:
          canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: p.size * squash, height: p.size * 0.7),
            paint,
          );
        default:
          canvas.drawOval(
            Rect.fromCenter(center: Offset.zero, width: p.size * 0.7 * squash, height: p.size * 0.7),
            paint,
          );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter old) => old.t != t;
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
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 320),
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
