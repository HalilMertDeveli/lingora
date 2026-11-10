import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../services/speech.dart';
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
    return Material(
      color: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? Theme.of(context).colorScheme.primary : const Color(0xFFE7E5EF),
          width: 2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(choice.emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 10),
            Text(choice.text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
