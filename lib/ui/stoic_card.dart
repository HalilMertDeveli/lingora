import 'package:flutter/material.dart';

import '../data/stoic.dart';
import '../theme.dart';

/// A Stoic quote: the English text (part of the lesson too), our Turkish and
/// the source.
class StoicQuoteBlock extends StatelessWidget {
  const StoicQuoteBlock({super.key, required this.quote, this.compact = false});

  final StoicQuote quote;

  /// Smaller type for the lesson result screen.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey('stoic-quote-${quote.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '“${quote.en}”',
          style: TextStyle(
            fontSize: compact ? 15 : 18,
            height: 1.35,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w700,
            color: Brand.ink,
          ),
        ),
        SizedBox(height: compact ? 4 : 8),
        Text(
          quote.tr,
          style: TextStyle(fontSize: compact ? 13 : 15, height: 1.35, color: Brand.muted),
        ),
        SizedBox(height: compact ? 4 : 8),
        Text(
          '— ${quote.source}',
          style: TextStyle(fontSize: compact ? 12 : 13, fontWeight: FontWeight.w700, color: Brand.primary),
        ),
      ],
    );
  }
}

/// Lesson result card: what the learner has done so far, then a quote.
class StoicResultCard extends StatelessWidget {
  const StoicResultCard({super.key, required this.quote, this.stats});

  final StoicQuote quote;
  final StoicStats? stats;

  @override
  Widget build(BuildContext context) {
    final st = stats;
    return Container(
      key: const ValueKey('result-stoic'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (st != null) ...[
            Wrap(
              key: const ValueKey('result-stoic-stats'),
              spacing: 6,
              runSpacing: 6,
              children: [
                if (st.lessonsToday > 0)
                  _Stat(Icons.menu_book_rounded, Brand.info, 'Bugün ${st.lessonsToday} ders'),
                _Stat(Icons.emoji_events_rounded, Brand.xp, 'Toplam ${st.correctTotal} doğru'),
              ],
            ),
            const SizedBox(height: 10),
          ],
          StoicQuoteBlock(quote: quote, compact: true),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.color, this.text);
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Brand.ink),
          ),
        ],
      ),
    );
  }
}
