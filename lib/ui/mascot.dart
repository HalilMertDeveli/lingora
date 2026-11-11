import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'motion.dart';

/// Pofu's mood decides its pose and how it moves.
enum Mood { idle, happy, cheer, sad, think, calm, joy }

/// Pofu's drawn poses (owner-supplied Lexigo set, see docs/assets.md).
enum PofuPose {
  hello,
  cool,
  calm,
  sad,
  dance,
  point;

  String get asset => 'assets/mascot/$name.png';

  static PofuPose of(Mood mood) => switch (mood) {
    Mood.idle || Mood.happy => PofuPose.hello,
    Mood.cheer => PofuPose.cool,
    Mood.sad => PofuPose.sad,
    Mood.think => PofuPose.point,
    Mood.calm => PofuPose.calm,
    Mood.joy => PofuPose.dance,
  };
}

/// Dilbaz's guide, Pofu: an orange cushion. Kid mode shows Pofu big and
/// animated; adult mode shows a small, still Pofu (or nothing when
/// [decorative]), so every screen adapts without changes.
class Mascot extends StatelessWidget {
  const Mascot({super.key, this.mood = Mood.idle, this.size = 120, this.decorative = false});
  final Mood mood;
  final double size;

  /// Purely decorative placements (hero banners) show nothing in adult mode.
  final bool decorative;

  /// Pofu's size in adult mode: small and quiet.
  static double adultSize(double size) => (size * 0.5).clamp(44.0, 72.0);

  @override
  Widget build(BuildContext context) {
    if (context.isKid) return Pofu(mood: mood, size: size);
    if (decorative) return const SizedBox.shrink();
    return Pofu(mood: mood, size: adultSize(size), animate: false);
  }
}

/// Pofu, the Dilbaz mascot. In dark themes it sits on a soft cream spot so
/// its dark arms and legs stay visible.
class Pofu extends StatefulWidget {
  const Pofu({super.key, this.mood = Mood.idle, this.size = 120, this.animate = true});
  final Mood mood;
  final double size;

  /// Idle bob and mood reactions (also off when the system reduces motion).
  final bool animate;

  PofuPose get pose => PofuPose.of(mood);

  @override
  State<Pofu> createState() => _PofuState();
}

class _PofuState extends State<Pofu> with TickerProviderStateMixin {
  /// Idle bob / cheer jump, looping.
  late final _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  /// One-shot reaction when the mood changes.
  late final _react = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _react.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLoop();
  }

  void _syncLoop() {
    if (widget.animate && loopsEnabled(context)) {
      if (!_loop.isAnimating) _loop.repeat();
    } else {
      _loop.stop();
    }
  }

  @override
  void didUpdateWidget(Pofu old) {
    super.didUpdateWidget(old);
    _syncLoop();
    if (old.mood != widget.mood && widget.animate) _react.forward(from: 0);
  }

  @override
  void dispose() {
    _loop.dispose();
    _react.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final dark = context.palette.isDark;
    final image = Image.asset(
      widget.pose.asset,
      width: s,
      height: s,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      semanticLabel: 'Pofu',
      errorBuilder: (_, _, _) => SizedBox(width: s, height: s),
    );
    final body = !widget.animate
        ? image
        : AnimatedBuilder(
            animation: Listenable.merge([_loop, _react]),
            child: image,
            builder: (_, child) {
              final t = _loop.value;
              final r = Curves.easeOut.transform(_react.value);
              var dy = 0.0;
              var tilt = 0.0;
              switch (widget.mood) {
                case Mood.cheer || Mood.joy:
                  dy = -sin(t * pi * 2).abs() * s * 0.06;
                case Mood.happy:
                  dy = -sin(r * pi) * s * 0.1 + sin(t * 2 * pi) * s * 0.012;
                case Mood.sad:
                  tilt = sin(r * pi * 3) * 0.05 * (1 - r);
                case Mood.think:
                  tilt = sin(t * 2 * pi) * 0.03;
                case Mood.calm:
                  dy = sin(t * 2 * pi) * s * 0.025;
                case Mood.idle:
                  dy = sin(t * 2 * pi) * s * 0.015;
              }
              return Transform.translate(
                offset: Offset(0, dy),
                child: Transform.rotate(angle: tilt, child: child),
              );
            },
          );
    return SizedBox(
      key: ValueKey('pofu-${widget.pose.name}'),
      width: s,
      height: s,
      child: dark
          ? DecoratedBox(
              decoration: const BoxDecoration(color: Palette.mascotSpot, shape: BoxShape.circle),
              child: Padding(padding: EdgeInsets.all(s * 0.08), child: body),
            )
          : body,
    );
  }
}

/// Empty list / nothing-to-do message with Pofu above it.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.mood = Mood.calm, this.size = 120});
  final String message;
  final Mood mood;
  final double size;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      key: const ValueKey('empty-state'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Mascot(mood: mood, size: size),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.palette.muted, fontSize: 15, height: 1.4),
        ),
      ],
    ),
  );
}
