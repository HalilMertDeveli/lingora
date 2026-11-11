import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'motion.dart';

/// The mascot's mood decides how it moves.
enum Mood { idle, happy, cheer, sad, think, calm, joy }

/// The Çaycı Dayı artwork (owner-supplied; source SVG next to it, see
/// docs/assets.md).
const mascotAsset = 'assets/mascot/cayci_dayi.png';

/// Dilbaz's guide, Çaycı Dayı. Kid mode shows him big and animated; adult
/// mode shows him small and still (or nothing when [decorative]), so every
/// screen adapts without changes.
class Mascot extends StatelessWidget {
  const Mascot({super.key, this.mood = Mood.idle, this.size = 120, this.decorative = false});
  final Mood mood;
  final double size;

  /// Purely decorative placements (hero banners) show nothing in adult mode.
  final bool decorative;

  /// The mascot's size in adult mode: small and quiet.
  static double adultSize(double size) => (size * 0.5).clamp(44.0, 72.0);

  @override
  Widget build(BuildContext context) {
    if (context.isKid) return Dayi(mood: mood, size: size);
    if (decorative) return const SizedBox.shrink();
    return Dayi(mood: mood, size: adultSize(size), animate: false);
  }
}

/// Çaycı Dayı, the Dilbaz mascot: a tea seller on an orange tile. The tile
/// carries its own background, so it reads on light and dark themes alike.
class Dayi extends StatefulWidget {
  const Dayi({super.key, this.mood = Mood.idle, this.size = 120, this.animate = true});
  final Mood mood;
  final double size;

  /// Idle bob and mood reactions (also off when the system reduces motion).
  final bool animate;

  @override
  State<Dayi> createState() => _DayiState();
}

class _DayiState extends State<Dayi> with TickerProviderStateMixin {
  /// Idle bob / cheer hop, looping.
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
  void didUpdateWidget(Dayi old) {
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
    final image = Image.asset(
      mascotAsset,
      width: s,
      height: s,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      semanticLabel: 'Çaycı Dayı',
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
              var scale = 1.0;
              switch (widget.mood) {
                case Mood.cheer || Mood.joy:
                  dy = -sin(t * pi * 2).abs() * s * 0.06;
                  scale = 1 + sin(r * pi) * 0.08;
                case Mood.happy:
                  dy = -sin(r * pi) * s * 0.1 + sin(t * 2 * pi) * s * 0.012;
                case Mood.sad:
                  tilt = sin(r * pi * 3) * 0.05 * (1 - r);
                  scale = 0.96;
                case Mood.think:
                  tilt = sin(t * 2 * pi) * 0.03;
                case Mood.calm:
                  dy = sin(t * 2 * pi) * s * 0.02;
                case Mood.idle:
                  dy = sin(t * 2 * pi) * s * 0.015;
              }
              return Transform.translate(
                offset: Offset(0, dy),
                child: Transform.rotate(
                  angle: tilt,
                  child: Transform.scale(scale: scale, child: child),
                ),
              );
            },
          );
    return SizedBox(key: ValueKey('dayi-${widget.mood.name}'), width: s, height: s, child: body);
  }
}

/// Empty list / nothing-to-do message with the mascot above it.
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
