import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Hearts are a warm red (the app's "wrong" colour is a calm blue).
const heartColor = Color(0xFFE5484D);

/// The hearts of a skip exam ("Atlama sınavı"). Only skip exams have
/// hearts; normal lessons never do. A heart that is lost pops off with a
/// small wobble and turns into an outline.
class HeartsBar extends StatelessWidget {
  const HeartsBar({super.key, required this.left, required this.total, this.size = 22});

  final int left;
  final int total;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$total candan $left kaldı',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: _Heart(key: Key('heart-$i'), full: i < left, size: size),
            ),
        ],
      ),
    ),
  );
}

class _Heart extends StatefulWidget {
  const _Heart({super.key, required this.full, required this.size});
  final bool full;
  final double size;

  @override
  State<_Heart> createState() => _HeartState();
}

class _HeartState extends State<_Heart> with SingleTickerProviderStateMixin {
  late final AnimationController _lose = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void didUpdateWidget(covariant _Heart old) {
    super.didUpdateWidget(old);
    if (old.full && !widget.full && !MediaQuery.disableAnimationsOf(context)) {
      _lose.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _lose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Icon(
      widget.full ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      color: widget.full ? heartColor : Brand.muted,
      size: widget.size,
    );
    return AnimatedBuilder(
      animation: _lose,
      builder: (context, _) {
        final t = _lose.value;
        if (!_lose.isAnimating) return base;
        // The outline wobbles in place while the lost heart floats up and fades.
        final wobble = sin(t * pi * 5) * 0.35 * (1 - t);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Transform.rotate(angle: wobble, child: base),
            Transform.translate(
              offset: Offset(0, -widget.size * 0.9 * t),
              child: Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 1 + 0.6 * t,
                  child: Icon(Icons.favorite_rounded, color: heartColor, size: widget.size),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
