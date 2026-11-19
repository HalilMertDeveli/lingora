import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/paywall_screen.dart';
import '../services/billing/premium_perks.dart';
import '../services/growth/analytics.dart';
import '../theme.dart';

/// The call to action on Premium cards: the free trial first, when there is
/// one to offer (see [trialOfferDaysProvider]).
String premiumCta(int trialDays) => trialDays > 0 ? '$trialDays GÜN ÜCRETSİZ DENE' : "PREMIUM'U İNCELE";

/// Opens the paywall for [placement] (the learner asked: never paced).
Future<void> openPaywall(BuildContext context, String placement) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => PaywallScreen(placement: placement)));

/// A small, closable-by-ignoring Premium card inside a screen (not the full
/// paywall). Logs `premium_offer_view` once.
class PremiumOfferCard extends ConsumerStatefulWidget {
  const PremiumOfferCard({
    super.key,
    required this.placement,
    required this.title,
    this.body,
    this.icon = Icons.workspace_premium_rounded,
    this.dense = false,
  });

  /// See [PaywallPlacement].
  final String placement;
  final String title;
  final String? body;
  final IconData icon;
  final bool dense;

  @override
  ConsumerState<PremiumOfferCard> createState() => _PremiumOfferCardState();
}

class _PremiumOfferCardState extends ConsumerState<PremiumOfferCard> {
  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).log(AnalyticsEvent.premiumOfferView(placement: widget.placement));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final trial = ref.watch(trialOfferDaysProvider);
    final gold = const Color(0xFFC88A00);
    return Container(
      key: ValueKey('premium-offer-${widget.placement}'),
      padding: EdgeInsets.all(widget.dense ? 12 : 14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(gold.withValues(alpha: p.isDark ? 0.16 : 0.08), p.card),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gold.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(widget.icon, color: gold, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, height: 1.3, color: p.ink),
                ),
              ),
            ],
          ),
          if (widget.body != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(widget.body!, style: TextStyle(color: p.muted, fontSize: 13, height: 1.35)),
            ),
          ],
          const SizedBox(height: 10),
          FilledButton(
            key: ValueKey('premium-offer-cta-${widget.placement}'),
            style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.white),
            onPressed: () => openPaywall(context, widget.placement),
            child: Text(premiumCta(trial), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

/// "Neden yanlış?" after the day's free ones. The learning loop still
/// closes: [basic] (one Turkish line, the rule and the right form) is always
/// shown in clear; the full explanation (every option in Turkish and why it
/// does not fit) is a blurred stand-in (never the real text) under a small
/// Premium card. It is placed after the question's explanation, never
/// between the learner and the options. [compact] drops the blurred preview
/// (the lesson's feedback panel is short).
class LockedWhyWrong extends ConsumerWidget {
  const LockedWhyWrong({super.key, this.basic, this.compact = false});

  final String? basic;
  final bool compact;

  static const _placeholder = [
    'Bu şık cümlenin anlamına uymuyor, çünkü',
    'Doğru: bağlaçtan sonra gelen yan cümle',
    'Olmaz: zaman uyumu bozuluyor ve özne',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final trial = ref.watch(trialOfferDaysProvider);
    return Column(
      key: const Key('why-wrong-locked'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.translate_rounded, size: 16, color: p.primary),
            const SizedBox(width: 6),
            Text(
              'Neden yanlış?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.primary),
            ),
          ],
        ),
        if (basic case final b? when b.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            b,
            key: const Key('why-wrong-basic'),
            style: TextStyle(color: p.ink, height: 1.35),
          ),
        ],
        const SizedBox(height: 6),
        if (!compact)
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 4.5, sigmaY: 4.5),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  color: p.card,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in _placeholder)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            line,
                            style: TextStyle(color: p.muted, fontStyle: FontStyle.italic),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (!compact) const SizedBox(height: 8),
        PremiumOfferCard(
          placement: PaywallPlacement.whyWrong,
          dense: true,
          icon: Icons.lock_rounded,
          title: trial > 0
              ? "Her şıkkın Türkçesi ve neden olmadığı Premium'da · $trial gün ücretsiz dene"
              : "Her şıkkın Türkçesi ve neden olmadığı Premium'da",
          body: 'Bugünkü $freeWhyWrongPerDay ücretsiz açıklamanı kullandın. Yarın yenilenir.',
        ),
      ],
    );
  }
}

/// Opens the paywall by itself for [placement] when [PaywallPacer] allows
/// it (at most once a day, not for 3 days after one was closed). Returns
/// whether it opened.
Future<bool> maybeAutoPaywall(BuildContext context, WidgetRef ref, String placement) async {
  if (!ref.read(paywallPacerProvider).takeAuto()) return false;
  await openPaywall(context, placement);
  return true;
}
