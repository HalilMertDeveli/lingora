import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../services/speech.dart';
import '../theme.dart';
import 'common.dart';

class SelectExercise extends ConsumerStatefulWidget {
  const SelectExercise({super.key, required this.ex, required this.locked, required this.onReady});
  final Exercise ex;
  final bool locked;
  final ReadyCallback onReady;

  @override
  ConsumerState<SelectExercise> createState() => _SelectExerciseState();
}

class _SelectExerciseState extends ConsumerState<SelectExercise> {
  String? _picked;

  void _pick(Choice c) {
    if (widget.locked) return;
    setState(() => _picked = c.text);
    ref.read(speechProvider).say(c.text);
    widget.onReady(() => _picked == widget.ex.answer);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExerciseTitle('“${widget.ex.prompt}” hangisi?'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.95,
          children: [
            for (final c in widget.ex.choices)
              _ChoiceCard(choice: c, selected: _picked == c.text, onTap: () => _pick(c)),
          ],
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.choice, required this.selected, required this.onTap});
  final Choice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapCard(
      selected: selected,
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: selected ? 1.18 : 1,
            duration: const Duration(milliseconds: 380),
            curve: Curves.elasticOut,
            child: Text(choice.emoji, style: const TextStyle(fontSize: 56)),
          ),
          const SizedBox(height: 10),
          Text(
            choice.text,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: selected ? Brand.primary : Brand.ink,
            ),
          ),
        ],
      ),
    );
  }
}
