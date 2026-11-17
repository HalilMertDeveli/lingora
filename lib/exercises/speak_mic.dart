import 'package:flutter/material.dart';

import '../core/spoken_match.dart';
import '../services/speech.dart';
import '../theme.dart';

/// Round microphone button with a ring that grows with the voice while
/// listening, so the learner sees they are being heard.
class MicButton extends StatelessWidget {
  const MicButton({
    super.key,
    required this.listening,
    required this.onTap,
    this.size = 96,
    this.color,
    this.inkKey,
  });
  final bool listening;
  final VoidCallback? onTap;
  final double size;
  final Color? color;

  /// Key of the tappable area (tests find the button by it).
  final Key? inkKey;

  @override
  Widget build(BuildContext context) {
    final fill = listening ? Brand.error : (color ?? Brand.primary);
    final ring = size * 0.45;
    return SizedBox(
      width: size + ring,
      height: size + ring,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (listening)
            ValueListenableBuilder<double>(
              valueListenable: speechLevel,
              builder: (context, level, _) => AnimatedContainer(
                key: const Key('mic-level'),
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                width: size + ring * level,
                height: size + ring * level,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill.withValues(alpha: 0.12 + 0.18 * level),
                ),
              ),
            ),
          Material(
            color: fill,
            shape: const CircleBorder(),
            child: InkWell(
              key: inkKey,
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(
                  listening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: color == null || listening ? Brand.onPrimary : onColor(fill),
                  size: size / 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
  if (listening) return heard.isEmpty ? 'Dinliyorum… Şimdi söyle.' : '“$heard”';
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
