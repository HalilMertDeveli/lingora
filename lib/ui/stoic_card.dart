import 'package:flutter/material.dart';

import '../data/stoic.dart';
import '../theme.dart';
import 'motion.dart';

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

/// The mid-session card: what the learner did today, then a quote. Any tap
/// closes it; the lesson waits underneath unchanged.
class StoicInterlude extends StatelessWidget {
  const StoicInterlude({
    super.key,
    required this.stats,
    required this.quote,
    required this.onContinue,
    this.title = 'Kısa bir mola',
    this.note,
  });

  final StoicStats stats;
  final StoicQuote quote;
  final VoidCallback onContinue;
  final String title;

  /// One line under the title (after a mistake: they come back later).
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return GestureDetector(
      key: const ValueKey('stoic-interlude'),
      behavior: HitTestBehavior.opaque,
      onTap: onContinue,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: t.titleLarge),
              if (note != null) ...[
                const SizedBox(height: 4),
                Text(note!, style: TextStyle(color: Brand.muted)),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Stat(
                    Icons.check_circle_rounded,
                    Brand.success,
                    'Bu derste ${stats.sessionCorrect}/${stats.sessionAnswered} doğru',
                  ),
                  _Stat(Icons.menu_book_rounded, Brand.info, 'Bugün ${stats.lessonsToday} ders'),
                  if (stats.streak > 0)
                    _Stat(Icons.local_fire_department, Brand.streak, '${stats.streak} günlük seri'),
                  _Stat(Icons.emoji_events_rounded, Brand.xp, 'Toplam ${stats.correctTotal} doğru cevap'),
                ],
              ),
              const SizedBox(height: 18),
              StoicQuoteBlock(quote: quote),
              const SizedBox(height: 20),
              PressableButton(key: const ValueKey('stoic-continue'), label: 'DEVAM', onPressed: onContinue),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
          ),
        ],
      ),
    );
  }
}

/// Shows [StoicInterlude] as a bottom sheet; closes on any tap, the
/// barrier or the back button.
Future<void> showStoicInterlude(
  BuildContext context, {
  required StoicStats stats,
  required StoicQuote quote,
  String title = 'Kısa bir mola',
  String? note,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => StoicInterlude(
      stats: stats,
      quote: quote,
      title: title,
      note: note,
      onContinue: () => Navigator.of(sheet).pop(),
    ),
  );
}
