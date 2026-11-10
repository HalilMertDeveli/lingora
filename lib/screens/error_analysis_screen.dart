import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tr_errors.dart';
import '../data/progress.dart';
import '../theme.dart';

/// Premium: every Türk hata dedektörü category with its share of all
/// mistakes and a study tip for each.
class ErrorAnalysisScreen extends ConsumerWidget {
  const ErrorAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final all = p.topErrorCategories(TrErrorCategory.values.length);
    final total = all.fold<int>(0, (sum, e) => sum + e.$2);
    final seen = {for (final e in all) e.$1};
    final clean = [
      for (final c in TrErrorCategory.values)
        if (!seen.contains(c)) c,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Detaylı hata analizi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            total == 0
                ? 'Henüz kayıtlı hata yok. Ders, günlük ve sohbette yaptığın hatalar burada toplanır.'
                : 'Toplam $total hata, ${all.length} kategoride. Büyükten küçüğe sıralı.',
            style: TextStyle(color: Brand.muted),
          ),
          const SizedBox(height: 14),
          for (final (category, count) in all)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TapCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(category.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        Text(
                          '$count kez · %${(count * 100 / total).round()}',
                          style: TextStyle(color: Brand.muted, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: count / total,
                        minHeight: 8,
                        color: Brand.error,
                        backgroundColor: Brand.line,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('💡 ${category.tip}', style: const TextStyle(height: 1.3, fontSize: 13)),
                  ],
                ),
              ),
            ),
          if (total > 0 && clean.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Temiz kategoriler ✅', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(clean.map((c) => c.label).join(' · '), style: TextStyle(color: Brand.muted)),
          ],
        ],
      ),
    );
  }
}
