import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';
import 'motion.dart';

/// The Altın coin (assets/gold/altin.svg, our own drawing).
const goldCoinAsset = 'assets/gold/altin.svg';

/// Text colour for gold amounts.
const goldInk = Color(0xFFB07800);
const goldInkDark = Color(0xFFFFC93C);

Color goldText(BuildContext context) => context.palette.isDark ? goldInkDark : goldInk;

class GoldCoin extends StatelessWidget {
  const GoldCoin({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    goldCoinAsset,
    width: size,
    height: size,
    semanticsLabel: 'Altın',
    placeholderBuilder: (_) => SizedBox.square(dimension: size),
  );
}

/// A coin and an amount, e.g. the balance or a price.
class GoldAmount extends StatelessWidget {
  const GoldAmount(this.amount, {super.key, this.size = 18, this.color, this.prefix = ''});
  final int amount;
  final double size;
  final Color? color;
  final String prefix;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      GoldCoin(size: size + 2),
      SizedBox(width: size * 0.25),
      Text(
        '$prefix$amount',
        style: TextStyle(color: color ?? goldText(context), fontWeight: FontWeight.w800, fontSize: size),
      ),
    ],
  );
}

/// "+N altın" that pops in, counts up and settles (lesson result). With
/// reduced motion it just shows the number.
class GoldGain extends StatefulWidget {
  const GoldGain({super.key, required this.amount, this.delay = Duration.zero, this.label});
  final int amount;
  final Duration delay;

  /// Small line under the amount (e.g. "Ders 5 · Hatasız 3").
  final String? label;

  @override
  State<GoldGain> createState() => _GoldGainState();
}

class _GoldGainState extends State<GoldGain> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!loopsEnabled(context)) {
      _c.value = 1;
    } else {
      Future<void>.delayed(widget.delay, () {
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
    final ink = goldText(context);
    return Semantics(
      label: '${widget.amount} altın kazandın',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final pop = Curves.elasticOut.transform(Interval(0, 0.7).transform(t));
          final shown = (widget.amount * Curves.easeOut.transform(Interval(0.1, 0.8).transform(t))).round();
          return Opacity(
            opacity: Interval(0, 0.25).transform(t),
            child: Transform.translate(
              offset: Offset(0, 12 * (1 - Curves.easeOut.transform(t))),
              child: Transform.scale(
                scale: 0.6 + 0.4 * pop,
                child: Container(
                  key: const ValueKey('gold-gain'),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: ink.withValues(alpha: 0.45)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.rotate(angle: (1 - pop) * 0.8, child: const GoldCoin(size: 26)),
                          const SizedBox(width: 8),
                          Text(
                            '+$shown altın',
                            style: TextStyle(color: ink, fontWeight: FontWeight.w900, fontSize: 18),
                          ),
                        ],
                      ),
                      if (widget.label != null)
                        Text(widget.label!, style: TextStyle(color: Brand.muted, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
