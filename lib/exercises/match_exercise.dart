import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../services/speech.dart';
import '../theme.dart';
import '../ui/motion.dart';
import 'common.dart';

/// Tap a Turkish word, then its English pair. Wrong taps only flash red.
class MatchExercise extends ConsumerStatefulWidget {
  const MatchExercise({super.key, required this.ex, required this.locked, required this.onReady});
  final Exercise ex;
  final bool locked;
  final ReadyCallback onReady;

  @override
  ConsumerState<MatchExercise> createState() => _MatchExerciseState();
}

class _MatchExerciseState extends ConsumerState<MatchExercise> {
  late final List<int> _left = List.generate(widget.ex.pairs.length, (i) => i)..shuffle();
  late final List<int> _right = List.generate(widget.ex.pairs.length, (i) => i)..shuffle();
  final Set<int> _matched = {};
  int? _selLeft;
  int? _selRight;
  (int, int)? _wrong;
  final Map<int, int> _shakeLeft = {};
  final Map<int, int> _shakeRight = {};

  void _tap({int? left, int? right}) {
    if (widget.locked) return;
    if (right != null) ref.read(speechProvider).say(widget.ex.pairs[right].$2);
    setState(() {
      _wrong = null;
      if (left != null) _selLeft = left;
      if (right != null) _selRight = right;
    });
    final l = _selLeft, r = _selRight;
    if (l == null || r == null) return;

    if (l == r) {
      Haptics.success();
      setState(() {
        _matched.add(l);
        _selLeft = _selRight = null;
      });
      if (_matched.length == widget.ex.pairs.length) widget.onReady(() => true);
    } else {
      setState(() {
        _wrong = (l, r);
        _shakeLeft[l] = (_shakeLeft[l] ?? 0) + 1;
        _shakeRight[r] = (_shakeRight[r] ?? 0) + 1;
        _selLeft = _selRight = null;
      });
      Haptics.error();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _wrong == (l, r)) setState(() => _wrong = null);
      });
    }
  }

  Widget _cell(String text, int pair, {required bool isLeft}) {
    final matched = _matched.contains(pair);
    final selected = isLeft ? _selLeft == pair : _selRight == pair;
    final wrong = _wrong != null && (isLeft ? _wrong!.$1 == pair : _wrong!.$2 == pair);
    final color = wrong ? Brand.error : (matched ? Brand.success : Brand.primary);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Shake(
        trigger: (isLeft ? _shakeLeft : _shakeRight)[pair] ?? 0,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: matched ? 0.4 : 1,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            scale: matched ? 0.94 : 1,
            child: TapCard(
              selected: selected || wrong || matched,
              color: color,
              onTap: matched ? null : () => isLeft ? _tap(left: pair) : _tap(right: pair),
              child: SizedBox(
                height: 28,
                child: Center(
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: wrong ? Brand.error : Brand.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pairs = widget.ex.pairs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExerciseTitle('Eşleri bul'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(children: [for (final i in _left) _cell(pairs[i].$1, i, isLeft: true)])),
            const SizedBox(width: 12),
            Expanded(child: Column(children: [for (final i in _right) _cell(pairs[i].$2, i, isLeft: false)])),
          ],
        ),
      ],
    );
  }
}
