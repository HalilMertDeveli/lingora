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

/// Primary action button, the "jelibon": a soft, glossy pill on a warm
/// shadow that squashes while held and springs back with a wobble. Kid mode
/// is chunkier and keeps capitals; adult mode uses sentence case.
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
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final lt = context.lingora;
    final p = lt.palette;
    final enabled = widget.onPressed != null;
    final base = widget.color ?? p.primary;
    final onBase =
        widget.foreground ??
        (widget.color == null ? p.onPrimary : (lt.isKid ? onColor(base) : onColor(base)));
    final disabledFace = p.isDark ? p.surface : p.line;
    final kid = lt.isKid;
    final height = kid ? 54.0 : 50.0;
    final face = widget.outlined ? p.card : (enabled ? base : disabledFace);
    final fg = widget.outlined ? (enabled ? (kid ? base : p.ink) : p.muted) : (enabled ? onBase : p.muted);
    final radius = BorderRadius.circular(height / 2);
    final glossy = enabled && !widget.outlined;
    final body = Container(
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: face,
        borderRadius: radius,
        // Jelly gloss: lighter at the top, a touch deeper at the bottom.
        gradient: glossy
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.lerp(face, Colors.white, 0.16)!, face, Color.lerp(face, Colors.black, 0.08)!],
                stops: const [0, 0.55, 1],
              )
            : null,
        border: widget.outlined
            ? Border.all(color: enabled ? p.line : disabledFace, width: kid ? 2 : 1.5)
            : null,
        boxShadow: enabled ? softShadow(p, tint: widget.outlined ? null : base, pressed: _down) : null,
      ),
      child: Text(
        kid ? widget.label : sentenceCase(widget.label),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: kid
            ? TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.6)
            : TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: Padding(
        // Room for the shadow, so neighbours do not cover it.
        padding: const EdgeInsets.only(bottom: 4),
        child: enabled
            ? JellyPress(
                onTap: widget.onPressed,
                onDown: (v) {
                  if (v != _down) setState(() => _down = v);
                },
                child: body,
              )
            : body,
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

/// Dilbaz's one-shot celebration over [child]: steam rises from the bottom
/// like from a fresh glass, sugar cubes tumble down and tulip petals drift.
/// Our own painter, no assets. Nothing is drawn when animations are reduced.
class TeaCelebration extends StatefulWidget {
  const TeaCelebration({super.key, required this.child, this.active = true, this.pieces = 60});
  final Widget child;
  final bool active;
  final int pieces;

  /// Length of one celebration.
  static const duration = Duration(milliseconds: 2800);

  @override
  State<TeaCelebration> createState() => _TeaCelebrationState();
}

class _TeaCelebrationState extends State<TeaCelebration> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: TeaCelebration.duration);
  final _pieces = <CelebrationPiece>[];
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.active || MediaQuery.disableAnimationsOf(context)) return;
    final p = context.palette;
    final r = Random();
    const petals = [Color(0xFFD7263D), Color(0xFFE85D75), Color(0xFFF29E4C), Color(0xFFB5179E)];
    for (var i = 0; i < widget.pieces; i++) {
      final kind = i % 3 == 0 ? PieceKind.steam : (i % 3 == 1 ? PieceKind.sugar : PieceKind.petal);
      _pieces.add(
        CelebrationPiece(
          kind: kind,
          x: kind == PieceKind.steam ? 0.15 + r.nextDouble() * 0.7 : r.nextDouble(),
          drift: (r.nextDouble() - 0.5) * 0.25,
          sway: 2 + r.nextDouble() * 4,
          spin: (r.nextDouble() - 0.5) * 8,
          size: switch (kind) {
            PieceKind.steam => 26 + r.nextDouble() * 26,
            PieceKind.sugar => 9 + r.nextDouble() * 6,
            PieceKind.petal => 10 + r.nextDouble() * 8,
          },
          color: switch (kind) {
            PieceKind.steam => p.isDark ? Colors.white : const Color(0xFFB9A796),
            PieceKind.sugar => Colors.white,
            PieceKind.petal => petals[r.nextInt(petals.length)],
          },
          delay: r.nextDouble() * 0.35,
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
                  ? CustomPaint(
                      key: const Key('tea-celebration'),
                      painter: CelebrationPainter(_pieces, _c.value, edge: context.palette.line),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
    ],
  );
}

enum PieceKind { steam, sugar, petal }

class CelebrationPiece {
  CelebrationPiece({
    required this.kind,
    required this.x,
    required this.drift,
    required this.sway,
    required this.spin,
    required this.size,
    required this.color,
    required this.delay,
  });
  final PieceKind kind;
  final double x, drift, sway, spin, size, delay;
  final Color color;
}

/// Paints the celebration at time [t] (0..1).
class CelebrationPainter extends CustomPainter {
  CelebrationPainter(this.pieces, this.t, {required this.edge});
  final List<CelebrationPiece> pieces;
  final double t;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final p in pieces) {
      final lt = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (lt <= 0 || lt >= 1) continue;
      final fade = lt < 0.15 ? lt / 0.15 : (lt > 0.7 ? (1 - lt) / 0.3 : 1.0);
      switch (p.kind) {
        case PieceKind.steam:
          // A curl that rises from the bottom edge, widens and fades.
          final x = (p.x + p.drift * lt) * size.width;
          final y = size.height * (1.02 - 0.75 * Curves.easeOut.transform(lt));
          final h = p.size * (1 + lt);
          stroke
            ..color = p.color.withValues(alpha: 0.42 * fade)
            ..strokeWidth = 3 + 3 * lt;
          final path = Path()..moveTo(x, y + h);
          for (var k = 1; k <= 8; k++) {
            final f = k / 8;
            path.lineTo(x + sin(f * pi * 2 + lt * p.sway * 2) * h * 0.18, y + h - f * h * 2);
          }
          canvas.drawPath(path, stroke);
        case PieceKind.sugar:
          // A sugar cube tumbling down.
          final x = (p.x + p.drift * lt) * size.width;
          final y = (-0.05 + 1.1 * lt * lt + 0.08 * lt) * size.height;
          canvas
            ..save()
            ..translate(x, y)
            ..rotate(p.spin * lt);
          final rect = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size),
            Radius.circular(p.size * 0.2),
          );
          fill.color = p.color.withValues(alpha: fade);
          canvas.drawRRect(rect, fill);
          stroke
            ..color = edge.withValues(alpha: fade)
            ..strokeWidth = 1.2;
          canvas
            ..drawRRect(rect, stroke)
            ..restore();
        case PieceKind.petal:
          // A tulip petal drifting down, swinging side to side.
          final x = (p.x + p.drift * lt + sin(lt * p.sway * pi) * 0.04) * size.width;
          final y = (-0.05 + 0.95 * lt) * size.height;
          final squash = cos(lt * p.sway * 2).abs().clamp(0.3, 1.0);
          canvas
            ..save()
            ..translate(x, y)
            ..rotate(sin(lt * p.sway * 2) * 0.9 + p.spin * 0.1);
          final w = p.size * 0.62 * squash, h = p.size;
          final petal = Path()
            ..moveTo(0, h / 2)
            ..cubicTo(-w, h * 0.2, -w * 0.8, -h * 0.45, 0, -h / 2)
            ..cubicTo(w * 0.8, -h * 0.45, w, h * 0.2, 0, h / 2)
            ..close();
          fill.color = p.color.withValues(alpha: fade);
          canvas
            ..drawPath(petal, fill)
            ..restore();
      }
    }
  }

  @override
  bool shouldRepaint(CelebrationPainter old) => old.t != t;
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
