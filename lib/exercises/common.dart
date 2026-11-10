import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/speech.dart';
import '../theme.dart';

/// Called by an exercise whenever its answer changes. A null grader means
/// there is nothing to check yet; otherwise it returns whether the current
/// answer is correct.
typedef Grader = bool Function();
typedef ReadyCallback = void Function(Grader? grader);

class ExerciseTitle extends StatelessWidget {
  const ExerciseTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
  );
}

/// Round button that reads [text] aloud.
class SpeakerButton extends ConsumerWidget {
  const SpeakerButton({super.key, required this.text, this.lang = 'en', this.size = 48, this.slow = false});

  final String text;
  final String lang;
  final double size;
  final bool slow;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Material(
    color: Brand.primary,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: () => ref.read(speechProvider).say(text, lang: lang, slow: slow),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          slow ? Icons.slow_motion_video_rounded : Icons.volume_up_rounded,
          color: Brand.onPrimary,
          size: size * 0.5,
        ),
      ),
    ),
  );
}

/// Compact word chip used in word banks and answers.
class WordChip extends StatelessWidget {
  const WordChip(this.word, {super.key, this.onTap, this.hidden = false, this.color});
  final String word;
  final VoidCallback? onTap;
  final bool hidden;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      word,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: hidden ? Colors.transparent : (color ?? Brand.ink),
      ),
    );
    if (hidden) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: Brand.line, borderRadius: BorderRadius.circular(12)),
        child: label,
      );
    }
    return TapCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: label,
    );
  }
}
