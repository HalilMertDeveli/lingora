import 'package:flutter/material.dart';

import '../core/spoken_match.dart';
import '../services/speech.dart';
import '../theme.dart';

/// The target sentence with the words that were not heard in red: what to
/// say again, not a score.
class SpokenWordsView extends StatelessWidget {
  const SpokenWordsView({super.key, required this.match});
  final SpokenMatch match;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 6,
    runSpacing: 2,
    children: [
      for (final w in match.words)
        Text(
          w.text,
          key: w.heard ? null : ValueKey('missed-${w.text}'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: w.heard ? Brand.success : Brand.error,
            decoration: w.heard ? null : TextDecoration.underline,
            decorationColor: Brand.error,
          ),
        ),
    ],
  );
}

/// What to tell the learner under the microphone.
String spokenStatus({
  required bool listening,
  required String heard,
  required SpokenMatch? match,
  required String? issue,
  required String idle,
}) {
  if (listening) return heard.isEmpty ? 'Şimdi söyle.' : '“$heard”';
  if (issue != null) return issue;
  if (match == null) return idle;
  if (match.heard.isEmpty) return SpeechIssues.notHeard;
  if (match.perfect) return 'Harika, hepsini duydum!';
  if (match.passed) return 'Güzel! Kırmızı kelimeyi bir kez daha dinleyebilirsin.';
  return 'Kırmızı kelimeleri duyamadım. Dinle, sonra biraz daha yavaş ve net söyle.';
}

/// Failed tries after which "Şu an konuşamıyorum" is offered up front.
const skipOfferAfter = 2;

/// The skip button: a quiet link at first, a clear way out once speaking
/// has not worked [skipOfferAfter] times.
class SpeakSkipButton extends StatelessWidget {
  const SpeakSkipButton({super.key, required this.failures, required this.onSkip});
  final int failures;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    const label = Text('Şu an konuşamıyorum');
    if (failures < skipOfferAfter) return TextButton(onPressed: onSkip, child: label);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Olmadıysa sorun değil, bu soruyu geçebilirsin; canın gitmez.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Brand.muted),
        ),
        const SizedBox(height: 6),
        FilledButton.tonal(key: const Key('speak-skip-offer'), onPressed: onSkip, child: label),
      ],
    );
  }
}
