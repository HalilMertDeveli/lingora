import 'package:flutter/material.dart';

import '../models/course.dart';
import '../theme.dart';
import 'common.dart';

class FillBlankExercise extends StatefulWidget {
  const FillBlankExercise({super.key, required this.ex, required this.locked, required this.onReady});
  final Exercise ex;
  final bool locked;
  final ReadyCallback onReady;

  @override
  State<FillBlankExercise> createState() => _FillBlankExerciseState();
}

class _FillBlankExerciseState extends State<FillBlankExercise> {
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final ex = widget.ex;
    final parts = ex.text!.split('___');
    final base = TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Brand.ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExerciseTitle('Boşluğu doldur'),
        Text.rich(
          TextSpan(
            style: base,
            children: [
              TextSpan(text: parts.first),
              TextSpan(
                text: _picked ?? ' ______ ',
                style: TextStyle(
                  color: Brand.primary,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.underline,
                  decorationThickness: 2,
                ),
              ),
              if (parts.length > 1) TextSpan(text: parts[1]),
            ],
          ),
        ),
        if (ex.translation != null) ...[
          const SizedBox(height: 8),
          Text(ex.translation!, style: TextStyle(color: Brand.muted, fontSize: 16)),
        ],
        const SizedBox(height: 32),
        for (final w in stableShuffle(ex.wordChoices, ex.text!))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TapCard(
              selected: _picked == w,
              onTap: widget.locked
                  ? null
                  : () {
                      setState(() => _picked = w);
                      widget.onReady(() => _picked == ex.answer);
                    },
              child: Text(
                w,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
}
