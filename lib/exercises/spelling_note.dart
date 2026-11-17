import 'package:flutter/material.dart';

import '../core/spelling.dart';
import '../theme.dart';

/// "Küçük bir yazım hatası: teach**er**": a gentle note under an answer
/// that counted as correct despite a small slip, with the exact spelling
/// and the letters that differ highlighted.
class SpellingNote extends StatelessWidget {
  const SpellingNote({super.key, required this.match});
  final AnswerMatch match;

  @override
  Widget build(BuildContext context) {
    final fixes = match.fixes;
    final lead = match.turkishLetters
        ? 'Türkçe harflere dikkat: '
        : (fixes.length == 1 ? 'Küçük bir yazım hatası: ' : 'Küçük yazım hataları: ');
    final mark = TextStyle(
      fontWeight: FontWeight.w900,
      color: Brand.success,
      decoration: TextDecoration.underline,
    );
    return Container(
      key: const Key('spelling-note'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.spellcheck_rounded, size: 20, color: Brand.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(color: Brand.ink, fontSize: 15),
                children: [
                  TextSpan(text: lead),
                  for (final (i, f) in fixes.indexed) ...[
                    if (i > 0) const TextSpan(text: ', '),
                    for (final p in f.parts) TextSpan(text: p.text, style: p.mark ? mark : null),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
