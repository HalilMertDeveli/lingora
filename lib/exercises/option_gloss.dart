import 'package:flutter/material.dart';

import '../data/option_glosses.dart';
import '../theme.dart';

/// "Neden yanlış?" switch shown above a wrongly answered question's options
/// when it has glosses: folds the options' Turkish away and back. Starts open.
class OptionGlossToggle extends StatelessWidget {
  const OptionGlossToggle({super.key, required this.open, required this.onChanged});
  final bool open;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final kid = context.isKid;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        toggled: open,
        child: InkWell(
          key: const Key('option-gloss-toggle'),
          borderRadius: BorderRadius.circular(kid ? Radii.lg : Radii.md),
          onTap: () => onChanged(!open),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Color.alphaBlend(p.primary.withValues(alpha: p.isDark ? 0.16 : 0.08), p.card),
              borderRadius: BorderRadius.circular(kid ? Radii.lg : Radii.md),
              border: Border.all(color: p.primary.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.translate_rounded, size: 16, color: p.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Neden yanlış?',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: kid ? 14 : 13, fontWeight: FontWeight.w800, color: p.primary),
                  ),
                ),
                const SizedBox(width: 2),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(Icons.expand_more_rounded, size: 18, color: p.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Turkish of one option and, for the right answer or the learner's
/// wrong pick, a one-line reason. Goes under the option's text.
class OptionGlossLines extends StatelessWidget {
  const OptionGlossLines({super.key, this.tr, this.why, this.whyRight = false});

  /// What the option means in Turkish.
  final String? tr;

  /// Why it is right ([whyRight]) or does not fit.
  final String? why;
  final bool whyRight;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final kid = context.isKid;
    final whyColor = whyRight ? p.success : p.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tr != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              tr!,
              key: const Key('option-gloss-tr'),
              softWrap: true,
              style: TextStyle(
                fontSize: kid ? 14.5 : 13.5,
                height: 1.3,
                fontWeight: FontWeight.w500,
                fontStyle: FontStyle.italic,
                color: p.muted,
              ),
            ),
          ),
        if (why != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    whyRight ? Icons.lightbulb_rounded : Icons.do_not_disturb_alt_rounded,
                    size: 14,
                    color: whyColor,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    why!,
                    key: const Key('option-gloss-why'),
                    style: TextStyle(
                      fontSize: kid ? 14 : 13,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: Color.lerp(whyColor, p.ink, p.isDark ? 0.15 : 0.3),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The gloss lines of option [i] of an answered question: its Turkish, and
/// a reason for the right option ([answer]) and a wrong [picked] one.
/// Null when there is nothing to show.
Widget? optionGlossFor(OptionGloss? gloss, int i, {required int answer, int? picked}) {
  if (gloss == null) return null;
  final tr = gloss.trOf(i);
  final showWhy = i == answer || i == picked;
  final why = showWhy ? gloss.whyOf(i) : null;
  if (tr == null && why == null) return null;
  return OptionGlossLines(key: Key('option-gloss-$i'), tr: tr, why: why, whyRight: i == answer);
}

/// Compact list of every option with its Turkish (exam result review).
class OptionGlossList extends StatelessWidget {
  const OptionGlossList({
    super.key,
    required this.options,
    required this.gloss,
    required this.answer,
    this.picked,
    this.letters = const ['A', 'B', 'C', 'D', 'E'],
  });
  final List<String> options;
  final OptionGloss gloss;
  final int answer;
  final int? picked;
  final List<String> letters;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      key: const Key('option-gloss-list'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${letters[i % letters.length]})',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: i == answer ? p.success : (i == picked ? p.error : p.muted),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        options[i],
                        style: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
                      ),
                      ?optionGlossFor(gloss, i, answer: answer, picked: picked),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
