import 'package:flutter/material.dart';

import '../core/text.dart';
import '../models/course.dart';
import '../theme.dart';
import '../ui/motion.dart';
import 'common.dart';

/// Build the translation by tapping words from a shuffled word bank.
class TranslateExercise extends StatefulWidget {
  const TranslateExercise({
    super.key,
    required this.ex,
    required this.locked,
    required this.onReady,
    this.onText,
  });
  final Exercise ex;
  final bool locked;
  final ReadyCallback onReady;

  /// Reports the sentence built so far (for the "Neden yanlış?" panel).
  final ValueChanged<String>? onText;

  @override
  State<TranslateExercise> createState() => _TranslateExerciseState();
}

class _TranslateExerciseState extends State<TranslateExercise> {
  late final List<String> _bank = [...widget.ex.tokens]..shuffle();
  final List<int> _chosen = [];

  void _update(VoidCallback change) {
    if (widget.locked) return;
    setState(change);
    final text = _chosen.map((i) => _bank[i]).join(' ');
    widget.onText?.call(text);
    widget.onReady(_chosen.isEmpty ? null : () => matchesAny(text, widget.ex.answers));
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.ex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExerciseTitle('Bu cümleyi çevir'),
        Row(
          children: [
            SpeakerButton(text: ex.text!, lang: ex.lang),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Brand.line, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(ex.text!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          constraints: const BoxConstraints(minHeight: 110),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Brand.line, width: 2),
              bottom: BorderSide(color: Brand.line, width: 2),
            ),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final i in _chosen)
                PopIn(
                  key: ValueKey(i),
                  from: 0.7,
                  child: WordChip(_bank[i], onTap: () => _update(() => _chosen.remove(i))),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 10,
          children: [
            for (var i = 0; i < _bank.length; i++)
              WordChip(_bank[i], hidden: _chosen.contains(i), onTap: () => _update(() => _chosen.add(i))),
          ],
        ),
      ],
    );
  }
}
