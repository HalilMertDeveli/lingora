import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pronunciation_feedback.dart';
import '../exercises/common.dart' show SpeakerButton;
import '../services/billing/premium.dart';
import '../services/growth/analytics_events.dart' show PaywallPlacement;
import '../theme.dart';
import 'premium_offer.dart';

/// Problem words shown to free users before the Premium card.
const freePronunciationPreview = 1;

Color verdictColor(WordVerdict v) => switch (v) {
  WordVerdict.ok => Brand.success,
  WordVerdict.hardSound => Brand.accent,
  WordVerdict.unclear => Brand.error,
};

/// Telaffuz puanı under a spoken attempt: how many words came through as
/// doğru / şu ses zor / anlaşılmadı (counts, never a percentage) and, for
/// each problem word, what the phone heard, the likely Turkish-speaker
/// sound behind it and the right pronunciation (recorded voice when there is
/// one, else the phone's speech engine). Premium sees every problem word;
/// free users see the first one and a Premium card.
class PronunciationScoreCard extends ConsumerWidget {
  const PronunciationScoreCard({super.key, required this.feedback, this.onOpenUnit});

  final PronunciationFeedback feedback;

  /// Opens the Telaffuz koçu unit for a sound (null: no button).
  final void Function(String unitId)? onOpenUnit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (feedback.nothingHeard || feedback.words.isEmpty) return const SizedBox.shrink();
    final premium = ref.watch(premiumProvider);
    final problems = feedback.problems;
    final shown = premium ? problems : problems.take(freePronunciationPreview).toList();
    final counts = {
      for (final v in WordVerdict.values) v: feedback.words.where((w) => w.verdict == v).length,
    };
    return Container(
      key: const Key('pron-score'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Brand.card.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Glyph(emoji: '🎯', icon: Icons.graphic_eq_rounded, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Telaffuz puanı', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final v in WordVerdict.values)
                if (counts[v]! > 0)
                  _Chip(
                    key: Key('pron-count-${v.name}'),
                    text: '${counts[v]} ${v.label.toLowerCase()}',
                    color: verdictColor(v),
                  ),
            ],
          ),
          if (feedback.allClear) ...[
            const SizedBox(height: 6),
            Text(
              'Bütün kelimeler net anlaşıldı. 👏',
              style: TextStyle(color: Brand.success, fontWeight: FontWeight.w700),
            ),
          ],
          if (feedback.lowConfidence) ...[
            const SizedBox(height: 6),
            Text(
              'Telefon bu cümlede genel olarak emin olamadı; sessiz bir yerde bir daha dene.',
              key: const Key('pron-low-confidence'),
              style: TextStyle(color: Brand.muted, fontSize: 13),
            ),
          ],
          for (final w in shown) ...[const SizedBox(height: 10), _ProblemWord(w, onOpenUnit: onOpenUnit)],
          if (!premium && problems.length > shown.length) ...[
            const SizedBox(height: 10),
            PremiumOfferCard(
              placement: PaywallPlacement.pronunciationScore,
              dense: true,
              icon: Icons.graphic_eq_rounded,
              title: '${problems.length - shown.length} kelime daha: hangi ses zor, nasıl söylenir?',
              body: "Premium'da her kelime için Türkçe ses ipucu ve doğru telaffuz.",
            ),
          ] else if (!premium && problems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              "Premium'da her zor kelimede ses ipucu ve koç dersi açılır.",
              style: TextStyle(color: Brand.muted, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProblemWord extends ConsumerWidget {
  const _ProblemWord(this.w, {this.onOpenUnit});
  final WordFeedback w;
  final void Function(String unitId)? onOpenUnit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = ref.watch(premiumProvider);
    final color = verdictColor(w.verdict);
    final issue = w.issue;
    final clean = w.word.replaceAll(RegExp(r"[^A-Za-z0-9'’-]"), '');
    return Row(
      key: Key('pron-word-$clean'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SpeakerButton(text: clean, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    clean,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Brand.ink),
                  ),
                  _Chip(text: w.verdict.label, color: color),
                ],
              ),
              if (w.heardAs.isNotEmpty)
                Text(
                  'Telefon “${w.heardAs}” diye anladı.',
                  style: TextStyle(color: Brand.muted, fontSize: 13),
                ),
              if (premium && issue != null) ...[
                const SizedBox(height: 3),
                Text(
                  '${w.issueIsGuess ? 'Olası neden' : 'Zor ses'}: ${issue.title}',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color),
                ),
                Text(issue.tip, style: TextStyle(color: Brand.ink, fontSize: 13, height: 1.3)),
                if (onOpenUnit != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: Key('pron-unit-$clean'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.record_voice_over_rounded, size: 18),
                      label: const Text('Koçta bu sesi çalış'),
                      onPressed: () => onOpenUnit!(issue.unitId),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
    ),
  );
}
