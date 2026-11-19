import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings.dart';
import '../data/progress.dart';
import '../goals/learn_goal.dart';
import '../services/billing/premium.dart' show premiumProvider;
import '../services/billing/premium_perks.dart' show paywallPacerProvider;
import '../services/growth/exam_campaign.dart';
import '../theme.dart';
import 'paywall_screen.dart';

/// Öğren: the exam-season countdown and, while the learner may be offered
/// Premium (PaywallPacer), the "Sınava kadar Premium" card. Nothing outside
/// a campaign window or in Çocuk modu.
class ExamSeasonCard extends ConsumerStatefulWidget {
  const ExamSeasonCard({super.key});

  /// Closing the offer hides it for this many days (the countdown stays).
  static const snoozeDays = 7;
  static const dismissedKey = 'growth.exam_season.dismissed_ms';

  @override
  ConsumerState<ExamSeasonCard> createState() => _ExamSeasonCardState();
}

class _ExamSeasonCardState extends ConsumerState<ExamSeasonCard> {
  bool _snoozed() {
    final ms = ref.read(prefsProvider).getInt(ExamSeasonCard.dismissedKey);
    if (ms == null) return false;
    final now = ref.read(clockProvider)();
    return now.difference(DateTime.fromMillisecondsSinceEpoch(ms)) < const Duration(days: ExamSeasonCard.snoozeDays);
  }

  void _dismiss() {
    ref.read(prefsProvider).setInt(ExamSeasonCard.dismissedKey, ref.read(clockProvider)().millisecondsSinceEpoch);
    setState(() {});
  }

  Future<void> _open(ExamSeasonWindow w) => Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => PaywallScreen(
        placement: examSeasonPlacement,
        pitch: '${w.countdown}. Sınava kadar sınırsız deneme, hata analizi ve günlük plan.',
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (ref.watch(appSettingsProvider.select((s) => s.isKid))) return const SizedBox.shrink();
    final w = ref.watch(examSeasonProvider);
    if (w == null) return const SizedBox.shrink();
    ref.watch(premiumProvider);
    final offer = ref.read(paywallPacerProvider).canOffer && !_snoozed();
    if (!offer) {
      // The goal card already counts down to the learner's own exam day.
      final goal = ref.watch(learnGoalProvider);
      if (goal?.daysLeft(ref.read(clockProvider)()) case final d? when d > 0) return const SizedBox.shrink();
      return _CountdownRow(window: w);
    }
    const gold = Color(0xFFC88A00);
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        key: const ValueKey('exam-season-offer'),
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        decoration: BoxDecoration(
          color: Color.alphaBlend(gold.withValues(alpha: p.isDark ? 0.16 : 0.08), p.card),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: gold.withValues(alpha: 0.55), width: 1.5),
        ),
        child: Row(
          children: [
            _DaysBadge(days: w.daysLeft),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () => _open(w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w.countdown,
                      key: const ValueKey('exam-season-countdown'),
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: p.ink),
                    ),
                    Text(
                      'Sınava kadar Premium: sınırsız deneme ve hata analizi',
                      style: TextStyle(color: p.muted, fontSize: 13, height: 1.3),
                    ),
                  ],
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('exam-season-cta'),
              onPressed: () => _open(w),
              child: const Text('İncele', style: TextStyle(color: gold, fontWeight: FontWeight.w900)),
            ),
            IconButton(
              key: const ValueKey('exam-season-dismiss'),
              tooltip: 'Kapat',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: p.muted),
              onPressed: _dismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownRow extends StatelessWidget {
  const _CountdownRow({required this.window});
  final ExamSeasonWindow window;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: TapCard(
      key: const ValueKey('exam-season-countdown-only'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          _DaysBadge(days: window.daysLeft),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              window.countdown,
              key: const ValueKey('exam-season-countdown'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DaysBadge extends StatelessWidget {
  const _DaysBadge({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    padding: const EdgeInsets.symmetric(vertical: 4),
    decoration: BoxDecoration(color: Brand.primary, borderRadius: BorderRadius.circular(12)),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$days',
          style: TextStyle(color: Brand.onPrimary, fontWeight: FontWeight.w900, fontSize: 18, height: 1.1),
        ),
        Text('gün', style: TextStyle(color: Brand.onPrimary, fontSize: 11)),
      ],
    ),
  );
}
