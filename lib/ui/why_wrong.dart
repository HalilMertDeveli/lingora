import 'package:flutter/material.dart';

import '../core/tr_errors.dart';
import '../theme.dart';

/// "Neden yanlış?": the Türk hata dedektörü's explanations for a wrong
/// answer. Without a matching rule it falls back to the missing and extra
/// words, and shows nothing when there is no difference to point at.
class WhyWrongSection extends StatelessWidget {
  const WhyWrongSection({
    super.key,
    required this.errors,
    this.missing = const [],
    this.extra = const [],
    this.maxErrors = 3,
  });

  final List<TrError> errors;

  /// Words of the accepted answer the user left out, and words they added.
  final List<String> missing;
  final List<String> extra;
  final int maxErrors;

  bool get isEmpty => errors.isEmpty && missing.isEmpty && extra.isEmpty;

  @override
  Widget build(BuildContext context) {
    if (isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Brand.card.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Glyph(emoji: '🔍', icon: Icons.manage_search_rounded, size: 18),
              SizedBox(width: 6),
              Text('Neden yanlış?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 6),
          if (errors.isEmpty)
            Text(
              [
                if (missing.isNotEmpty) 'Eksik: ${missing.join(', ')}',
                if (extra.isNotEmpty) 'Fazla: ${extra.join(', ')}',
              ].join(' · '),
              style: TextStyle(color: Brand.ink, height: 1.3),
            )
          else
            for (final e in errors.take(maxErrors)) _ErrorTile(e),
        ],
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile(this.error);
  final TrError error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Brand.errorBg, borderRadius: BorderRadius.circular(8)),
              child: Text(
                error.category.label,
                style: TextStyle(color: Brand.error, fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
            Text(
              error.wrong,
              style: TextStyle(
                decoration: TextDecoration.lineThrough,
                color: Brand.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(error.explanation, style: TextStyle(color: Brand.ink, height: 1.3)),
      ],
    ),
  );
}
