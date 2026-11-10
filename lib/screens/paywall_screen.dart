import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/billing/premium.dart';
import '../services/growth/analytics.dart';
import '../services/growth/remote_flags.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';

enum GateResult {
  /// The user has Premium (already, or bought/restored it on the paywall).
  premium,

  /// The user chose the free alternative offered on the paywall.
  free,

  /// The paywall was closed without Premium.
  closed,
}

/// Lets the user through when they have Premium; otherwise opens the paywall
/// for [feature]. [freeAlternative] adds a button such as "Demo ile dene".
Future<GateResult> requirePremium(
  BuildContext context,
  WidgetRef ref,
  PremiumFeature feature, {
  String? freeAlternative,
  String? placement,
}) async {
  if (ref.read(premiumProvider)) return GateResult.premium;
  final choseFree = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => PaywallScreen(feature: feature, freeAlternative: freeAlternative, placement: placement),
    ),
  );
  if (!context.mounted) return GateResult.closed;
  if (ref.read(premiumProvider)) return GateResult.premium;
  return choseFree == true ? GateResult.free : GateResult.closed;
}

/// What stays free, so the paywall is honest about it.
const freeItems = [
  'Tüm dersler, gramer yolu ve notlar',
  'Okuma, telaffuz ve kelime tekrarı',
  'Sınav konu pratiği + günde $freeMockExamsPerDay mini deneme',
  'Sohbet senaryoları (demo modu)',
  'Hata dedektörü ve en sık 3 hatan',
];

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.feature, this.freeAlternative, this.placement});

  /// The feature the user tried to open (highlighted), if any.
  final PremiumFeature? feature;

  /// Label of a free fallback (pops the paywall with `true`).
  final String? freeAlternative;

  /// Where it was opened from (analytics), see [PaywallPlacement]. Derived
  /// from [feature] when null.
  final String? placement;

  String get resolvedPlacement =>
      placement ??
      switch (feature) {
        PremiumFeature.aiConversation => PaywallPlacement.aiChat,
        PremiumFeature.unlimitedMockExams => PaywallPlacement.mockExam,
        PremiumFeature.errorAnalytics => PaywallPlacement.errorAnalysis,
        null => PaywallPlacement.profile,
      };

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  PremiumPlan _plan = PremiumPlan.yearly;
  late final AnalyticsService _analytics;
  late final String _variant;
  bool _wasPremium = false;

  @override
  void initState() {
    super.initState();
    _analytics = ref.read(analyticsProvider);
    _variant = ref.read(remoteFlagsProvider).paywallVariant;
    _wasPremium = ref.read(premiumProvider);
    if (!_wasPremium) {
      _analytics.log(AnalyticsEvent.paywallView(placement: widget.resolvedPlacement, variant: _variant));
    }
    Future.microtask(() => ref.read(premiumControllerProvider.notifier).loadProducts());
  }

  @override
  void dispose() {
    if (!_wasPremium && !_purchased) {
      _analytics.log(AnalyticsEvent.paywallClose(placement: widget.resolvedPlacement, variant: _variant));
    }
    super.dispose();
  }

  bool _purchased = false;

  void _buy() {
    _analytics.log(AnalyticsEvent.purchaseStart(plan: _plan.name, placement: widget.resolvedPlacement));
    ref.read(premiumControllerProvider.notifier).buy(_plan);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(premiumControllerProvider.select((s) => s.justPurchased), (_, now) {
      if (!now) return;
      _purchased = true;
      ref.read(premiumControllerProvider.notifier).acknowledge();
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Premium açıldı. İyi çalışmalar! 🎉')));
      Navigator.of(context).maybePop();
    });
    final s = ref.watch(premiumControllerProvider);
    final premium = ref.watch(premiumProvider);
    final flags = ref.watch(remoteFlagsProvider);
    // Variant "b" (Remote Config A/B test): plans before the feature list.
    final plansFirst = _variant == 'b' && !premium;
    final features = [
      Text('Premium ile', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      for (final f in PremiumFeature.values) _FeatureRow(f, highlighted: f == widget.feature),
      const SizedBox(height: 14),
      _FreeBox(),
      const SizedBox(height: 18),
    ];
    final buy = premium ? [_activeBox(s)] : _purchase(context, s, flags);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kapat',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Lingora Premium'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _header(context, premium),
            const SizedBox(height: 18),
            if (plansFirst) ...[
              ...buy,
              const SizedBox(height: 18),
              ...features,
            ] else ...[
              ...features,
              ...buy,
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, bool premium) => Row(
    children: [
      Mascot(mood: premium ? Mood.cheer : Mood.happy, size: 80),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              premium
                  ? 'Premium aktif 🎉'
                  : _variant == 'b'
                  ? 'Konuşarak öğren, sınırsız deneme çöz'
                  : 'Daha fazla konuş, daha çok deneme çöz',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              widget.feature == null || premium
                  ? 'Temel öğrenme her zaman ücretsiz. Premium, maliyeti yüksek ekstraları açar.'
                  : '“${widget.feature!.title}” Premium ile açılır. Temel öğrenme her zaman ücretsiz.',
              style: const TextStyle(color: Brand.muted),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _activeBox(PremiumState s) {
    final plan = PremiumPlan.byId(s.productId);
    final until = s.expiresAt;
    if (s.productId == referralProductId) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Brand.successBg, borderRadius: BorderRadius.circular(16)),
        child: Text(
          'Davet ödülü Premium\'un aktif'
          '${until == null ? '' : ' (${until.day}.${until.month}.${until.year} tarihine kadar)'}. '
          'Süre bitince ücretsiz sürüme kendiliğinden dönersin; ödeme alınmaz.',
          style: const TextStyle(height: 1.35),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Brand.successBg, borderRadius: BorderRadius.circular(16)),
      child: Text(
        '${plan == null ? 'Premium' : '${plan.label} Premium'} aboneliğin aktif. '
        'Aboneliğini Google Play > Ödemeler ve abonelikler > Abonelikler bölümünden yönetebilir '
        'veya iptal edebilirsin.',
        style: const TextStyle(height: 1.35),
      ),
    );
  }

  List<Widget> _purchase(BuildContext context, PremiumState s, RemoteFlags flags) {
    final ctrl = ref.read(premiumControllerProvider.notifier);
    final available = s.storeAvailable;
    final selected = s.product(_plan);
    // A trial is mentioned only when Remote Config allows it and Google Play
    // really offers one to this user; the length always comes from Play.
    final trialDays = flags.trialDays > 0 ? (selected?.freeTrialDays ?? 0) : 0;
    return [
      if (available == null)
        const Center(
          child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
        )
      else if (!available)
        const _Notice(
          icon: Icons.storefront_rounded,
          text:
              'Satın alma bu cihazda şu an kullanılamıyor. Google Play yüklü ve hesabın açık olduğundan '
              'emin ol; Premium satın alındıysa aşağıdan geri yükleyebilirsin.',
        )
      else
        for (final plan in PremiumPlan.values)
          if (s.product(plan) case final product?)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PlanCard(
                plan: plan,
                product: product,
                monthly: s.product(PremiumPlan.monthly),
                priceCopy: flags.priceCopy,
                showTrial: flags.trialDays > 0,
                selected: plan == _plan,
                onTap: () => setState(() => _plan = plan),
              ),
            ),
      if (s.pending)
        const _Notice(
          icon: Icons.hourglass_top_rounded,
          text: 'Ödemen onay bekliyor. Onaylanınca Premium kendiliğinden açılır; uygulamayı kapatabilirsin.',
        ),
      if (s.error != null) _Notice(icon: Icons.error_outline_rounded, text: s.error!, color: Brand.errorBg),
      if (s.message != null) _Notice(icon: Icons.info_outline_rounded, text: s.message!),
      const SizedBox(height: 6),
      PressableButton(
        key: const ValueKey('paywall-buy'),
        label: s.busy
            ? 'BEKLENİYOR…'
            : selected == null
            ? 'PREMIUM\'A GEÇ'
            : trialDays > 0
            ? '$trialDays GÜN ÜCRETSİZ DENE'
            : '${_plan.label.toUpperCase()} · ${selected.price}',
        color: Brand.primary,
        onPressed: available == true && selected != null && !s.busy && !s.pending ? _buy : null,
      ),
      if (trialDays > 0 && selected != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Deneme bitince ${selected.price} / ${_plan.period}. Deneme süresince iptal edersen ücret alınmaz.',
            style: TextStyle(color: Brand.muted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      if (widget.freeAlternative case final label?) ...[
        const SizedBox(height: 10),
        PressableButton(
          label: label,
          outlined: true,
          color: Brand.primary,
          foreground: Brand.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      const SizedBox(height: 10),
      Center(
        child: TextButton(
          onPressed: s.busy ? null : ctrl.restore,
          child: const Text('Satın alımları geri yükle'),
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'Abonelik, iptal edilmedikçe her dönem sonunda Google Play hesabından otomatik yenilenir. '
        'İstediğin zaman Google Play > Abonelikler bölümünden iptal edebilirsin; iptal edersen '
        'ödediğin dönemin sonuna kadar Premium kalır. Fiyatlara vergiler dahildir.',
        style: TextStyle(color: Brand.muted, fontSize: 12, height: 1.35),
        textAlign: TextAlign.center,
      ),
    ];
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow(this.feature, {required this.highlighted});
  final PremiumFeature feature;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: highlighted ? Brand.primary.withValues(alpha: 0.08) : Colors.white,
      border: Border.all(color: highlighted ? Brand.primary : Brand.line, width: 2),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(feature.emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(feature.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(feature.description, style: const TextStyle(color: Brand.muted, fontSize: 13)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _FreeBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Her zaman ücretsiz', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final item in freeItems)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_rounded, size: 18, color: Brand.success),
                const SizedBox(width: 6),
                Expanded(child: Text(item, style: const TextStyle(fontSize: 13))),
              ],
            ),
          ),
        const Text(
          'Can/kalp yok, ceza yok: hata yapmak öğrenmenin parçası.',
          style: TextStyle(color: Brand.muted, fontSize: 12),
        ),
      ],
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.product,
    required this.monthly,
    required this.selected,
    required this.onTap,
    this.priceCopy = PriceCopy.savings,
    this.showTrial = false,
  });
  final PremiumPlan plan;
  final StoreProduct product;
  final StoreProduct? monthly;
  final PriceCopy priceCopy;
  final bool showTrial;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Savings are computed from the store's real prices, never made up.
    final saving =
        priceCopy == PriceCopy.savings &&
            plan == PremiumPlan.yearly &&
            monthly != null &&
            monthly!.rawPrice > 0
        ? (100 - product.rawPrice * 100 / (monthly!.rawPrice * 12)).round()
        : 0;
    return TapCard(
      key: ValueKey('plan-${plan.name}'),
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
            color: selected ? Brand.primary : Brand.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(plan.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    if (saving > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Brand.accent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '%$saving tasarruf',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ],
                ),
                Text('${product.price} / ${plan.period}', style: const TextStyle(color: Brand.muted)),
                if (priceCopy == PriceCopy.monthlyEquivalent && plan == PremiumPlan.yearly)
                  if (formatPerMonth(product.price, product.rawPrice / 12) case final perMonth?)
                    Text('Aylık yalnızca $perMonth', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (showTrial && product.freeTrialDays > 0)
                  Text(
                    '${product.freeTrialDays} gün ücretsiz deneme',
                    style: TextStyle(color: Brand.success, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.color = const Color(0xFFFFF4DC)});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Icon(icon, color: Brand.ink),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

/// Writes [value] in the same style as the store's [price] string, e.g.
/// ("₺799,99", 66.666) → "₺66,67". Returns null if [price] has no number.
String? formatPerMonth(String price, double value) {
  final m = RegExp(r'\d[\d.,\s ]*').firstMatch(price);
  if (m == null) return null;
  final number = m.group(0)!.trimRight();
  final decimalComma =
      RegExp(r',\d{1,2}$').hasMatch(number) || (!number.contains('.') && number.contains(','));
  final fixed = value.toStringAsFixed(2);
  final text = decimalComma ? fixed.replaceAll('.', ',') : fixed;
  return price.replaceRange(m.start, m.start + number.length, text);
}
