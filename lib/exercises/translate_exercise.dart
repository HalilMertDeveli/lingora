import 'package:flutter/material.dart';

import '../core/text.dart';
import '../models/course.dart';
import '../theme.dart';
import 'common.dart';
import 'word_bank.dart';

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
  // Stable, so a lesson reopened after the app was killed looks the same.
  late final List<String> _bank = stableShuffle(
    widget.ex.tokens,
    'bank:${widget.ex.text ?? ''}:${widget.ex.tokens.join(' ')}',
  );
  List<int> _chosen = const [];

  void _changed(List<int> chosen) {
    if (widget.locked) return;
    setState(() => _chosen = chosen);
    final text = WordBank.sentence(_bank, chosen);
    widget.onText?.call(text);
    widget.onReady(chosen.isEmpty ? null : () => matchesAny(text, widget.ex.answers));
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.ex;
    final compact = MediaQuery.sizeOf(context).height < 700;
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
        SizedBox(height: compact ? 12 : 24),
        WordBank(words: _bank, chosen: _chosen, locked: widget.locked, onChanged: _changed),
      ],
    );
  }
}
