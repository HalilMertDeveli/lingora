import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/text.dart';
import '../data/progress.dart' show clockProvider;
import '../goals/goal_paywall_copy.dart';
import '../goals/learn_goal.dart';
import '../services/billing/family.dart';
import '../services/billing/premium.dart';
import '../services/billing/premium_perks.dart';
import '../services/growth/analytics.dart';
import '../services/growth/remote_flags.dart';
import '../services/growth/review_prompt.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import 'family_screen.dart';

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
  String? pitch,
}) async {
  if (ref.read(premiumProvider)) return GateResult.premium;
  final choseFree = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => PaywallScreen(
        feature: feature,
        freeAlternative: freeAlternative,
        placement: placement,
        pitch: pitch,
      ),
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
  'Telaffuz puanı özeti ve kilometre taşı paylaşım kartı',
  'Sınav konu pratiği + günde $freeMockExamsPerDay mini deneme',
  'Günde $freeWhyWrongPerDay "Neden yanlış?" açıklaması',
  'Sohbet senaryoları (demo modu)',
  'Hata dedektörü ve en sık 3 hatan',
  'Hesapla bulut yedekleme ve cihazlar arası devam',
];

/// Feature rows drawn in full on the paywall; later ones (not the opened
/// feature nor the goal's focus) are one title line.
const paywallFullFeatureRows = 6;

/// Premium bullets that are not a [PremiumFeature] (no gate of their own),
/// drawn after the feature rows: (emoji, title, description).
const extraPremiumBullets = <(String, String, String)>[
  (
    '🎙️',
    'Sesli konuşma koçu + konuşma karnesi',
    'Garson, mülakatçı, resepsiyon: sesli konuş, cevabı sesli duy. Sonunda hatalı cümlelerin ve telefonun zor anladığı kelimelerle karnen hazır.',
  ),
];

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({
    super.key,
    this.feature,
    this.freeAlternative,
    this.placement,
    this.showFamily = false,
    this.pitch,
  });

  /// One highlighted line under the hero, from where it was opened
  /// (e.g. "Bugünkü 3 ücretsiz mesajını kullandın.").
  final String? pitch;

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
        PremiumFeature.interviewRehearsal => PaywallPlacement.interviewRehearsal,
        PremiumFeature.unlimitedMockExams => PaywallPlacement.mockExam,
        PremiumFeature.errorAnalytics => PaywallPlacement.errorAnalysis,
        PremiumFeature.whyWrong => PaywallPlacement.whyWrong,
        PremiumFeature.premiumAvatars => PaywallPlacement.shop,
        PremiumFeature.levelReport => PaywallPlacement.levelReport,
        PremiumFeature.pronunciationScore => PaywallPlacement.pronunciationScore,
        PremiumFeature.explainMore => PaywallPlacement.explainMore,
        PremiumFeature.weeklyCoach => PaywallPlacement.weeklyCoach,
        PremiumFeature.monthlyShareCard => PaywallPlacement.shareCard,
        PremiumFeature.streakFreezes || PremiumFeature.doubleGold || null => PaywallPlacement.profile,
      };

  /// Preselects the family plan (opened from the family screen).
  final bool showFamily;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  late PremiumPlan _plan = widget.showFamily ? PremiumPlan.familyYearly : PremiumPlan.recommended;
  late final AnalyticsService _analytics;
  late final PaywallPacer _pacer;
  late final String _variant;
  bool _wasPremium = false;

  @override
  void initState() {
    super.initState();
    _analytics = ref.read(analyticsProvider);
    _pacer = ref.read(paywallPacerProvider);
    _variant = ref.read(remoteFlagsProvider).paywallVariant;
    _wasPremium = ref.read(premiumProvider);
    // No review prompt right after a paywall.
    ref.read(reviewPolicyProvider).markPaywall(ref.read(clockProvider)());
    if (!_wasPremium) {
      _analytics.log(AnalyticsEvent.paywallView(placement: widget.resolvedPlacement, variant: _variant));
    }
    Future.microtask(() => ref.read(premiumControllerProvider.notifier).loadProducts());
  }

  @override
  void dispose() {
    if (!_wasPremium && !_purchased) {
      _analytics.log(AnalyticsEvent.paywallClose(placement: widget.resolvedPlacement, variant: _variant));
      // Closed without buying: it does not open by itself for a few days.
      _pacer.recordClosed();
    }
    super.dispose();
  }

  bool _purchased = false;

  void _buy(PremiumPlan plan) {
    _analytics.log(AnalyticsEvent.purchaseStart(plan: plan.name, placement: widget.resolvedPlacement));
    ref.read(premiumControllerProvider.notifier).buy(plan);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(premiumControllerProvider.select((s) => s.justPurchased), (_, now) {
      if (!now) return;
      _purchased = true;
      ref.read(premiumControllerProvider.notifier).acknowledge();
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Premium açıldı. İyi çalışmalar!')));
      Navigator.of(context).maybePop();
    });
    final s = ref.watch(premiumControllerProvider);
    final premium = ref.watch(premiumProvider);
    final flags = ref.watch(remoteFlagsProvider);
    // Variant "b" (Remote Config A/B test): plans before the feature list.
    final plansFirst = _variant == 'b' && !premium;
    final copy = goalPaywallCopy(
      ref.watch(learnGoalProvider),
      ref.read(clockProvider)(),
      variantB: _variant == 'b',
    );
    final features = [
      Text('Premium ile', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      for (final (i, f) in [
        ...copy.focus,
        ...PremiumFeature.values.where((f) => !copy.focus.contains(f)),
      ].indexed)
        _FeatureRow(
          f,
          highlighted: f == widget.feature || (widget.feature == null && copy.focus.contains(f)),
          // The list is long: after the first ones, a title line is enough.
          compact: i >= paywallFullFeatureRows && f != widget.feature && !copy.focus.contains(f),
        ),
      for (final (emoji, title, description) in extraPremiumBullets)
        _BulletRow(emoji: emoji, title: title, description: description),
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
        title: const Text('Çenebaz Premium'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _header(context, premium, copy),
            if (!premium) ...[
              for (final line in copy.outcomes) _Outcome(line),
              if (widget.pitch case final p? when p != paywallValueLine) ...[
                const SizedBox(height: 10),
                _Pitch(p, key: const ValueKey('paywall-pitch')),
              ],
              const SizedBox(height: 10),
              const _Pitch(paywallValueLine, key: ValueKey('paywall-value-line')),
            ],
            if (!premium)
              if (personalLine(whyWrongWeek(ref.watch(whyWrongQuotaProvider))) case final line?) ...[
                const SizedBox(height: 12),
                _Personal(line),
              ],
            if (!premium && _trialFromPlay(s, flags) > 0) ...[
              const SizedBox(height: 12),
              _TrialBanner(days: _trialFromPlay(s, flags)),
            ],
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

  Widget _header(BuildContext context, bool premium, GoalPaywallCopy copy) => Row(
    children: [
      Mascot(mood: premium ? Mood.cheer : Mood.happy, size: 80),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              premium ? 'Premium aktif' : copy.title,
              key: const ValueKey('paywall-title'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              premium
                  ? 'Temel öğrenme her zaman ücretsiz. Premium, maliyeti yüksek ekstraları açar.'
                  : widget.feature == null
                  ? copy.subtitle
                  : '“${widget.feature!.title}” Premium ile açılır. Temel öğrenme her zaman ücretsiz.',
              style: TextStyle(color: Brand.muted),
            ),
          ],
        ),
      ),
    ],
  );

  /// Free trial days of the yearly plan as Google Play returns them (0 when
  /// Play offers none, or Remote Config turns trials off).
  static int _trialFromPlay(PremiumState s, RemoteFlags flags) {
    if (flags.trialDays <= 0) return 0;
    return s.product(PremiumPlan.yearly)?.freeTrialDays ?? 0;
  }

  void _openFamily(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FamilyScreen()));

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
    if (plan == PremiumPlan.familyYearly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Brand.successBg, borderRadius: BorderRadius.circular(16)),
            child: const Text(
              "Aile planı Premium'un aktif. Aileni yönetmek, davet kodu oluşturmak ya da aileden "
              'ayrılmak için aile planı ekranını aç. Aboneliği yalnızca satın alan kişi Google Play '
              '> Abonelikler bölümünden yönetebilir.',
              style: TextStyle(height: 1.35),
            ),
          ),
          const SizedBox(height: 10),
          PressableButton(label: 'AİLE PLANI', color: Brand.primary, onPressed: () => _openFamily(context)),
        ],
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
    final familyReady = ref.watch(familyBackendProvider) != null;
    final offered = [
      for (final p in [...PremiumPlan.personal, if (familyReady) PremiumPlan.familyYearly])
        if (s.product(p) != null) p,
    ];
    // Yearly stays preselected; if Play did not return it, the first plan it did.
    final plan = offered.contains(_plan) ? _plan : offered.firstOrNull ?? _plan;
    final selected = s.product(plan);
    // A trial is mentioned only when Remote Config allows it and Google Play
    // really returns a free-trial offer for this product to this user; the
    // length always comes from Play, never from this app.
    final trialDays = flags.trialDays > 0 ? (selected?.freeTrialDays ?? 0) : 0;
    return [
      if (available != true) _PriceAnchor(trialDays: flags.trialDays),
      if (available == null)
        const Center(
          child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
        )
      else if (!available)
        _Unavailable(onRetry: s.busy ? null : ctrl.loadProducts)
      else
        for (final p in offered)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PlanCard(
              plan: p,
              product: s.product(p)!,
              monthly: s.product(PremiumPlan.monthly),
              priceCopy: flags.priceCopy,
              showTrial: flags.trialDays > 0,
              selected: p == plan,
              onTap: () => setState(() => _plan = p),
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
            : '${trUpper(plan.label)} · ${selected.price}',
        color: Brand.primary,
        onPressed: available == true && selected != null && !s.busy && !s.pending ? () => _buy(plan) : null,
      ),
      if (trialDays > 0 && selected != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Deneme bitince ${selected.price} / ${plan.period}. Deneme süresince iptal edersen ücret alınmaz.',
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
      Center(
        child: TextButton(
          key: const ValueKey('paywall-family-code'),
          onPressed: () => _openFamily(context),
          child: const Text('Aile davet kodum var'),
        ),
      ),
      if (!familyReady)
        Text(
          'Aile planı ($familySeats kişiye kadar) hesap ve sunucu bağlantısı gerektirir; bu sürümde satın alınamaz.',
          style: TextStyle(color: Brand.muted, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      const SizedBox(height: 4),
      Text(
        'Abonelik, iptal edilmedikçe her dönem sonunda Google Play hesabından otomatik yenilenir. '
        'İstediğin zaman Google Play > Abonelikler bölümünden iptal edebilirsin; iptal edersen '
        'ödediğin dönemin sonuna kadar Premium kalır. Fiyatlara vergiler dahildir.',
        style: TextStyle(color: Brand.muted, fontSize: 12, height: 1.35),
        textAlign: TextAlign.center,
      ),
    ];
  }
}

/// "Bu hafta 12 yanlışın var; 9 tanesinin açıklaması Premium'da." from the
/// learner's own week ([WhyWrongQuota.week]); null when there is nothing to say.
String? personalLine(({int wrong, int locked}) week) {
  if (week.locked > 0) {
    return "Bu hafta ${week.wrong} yanlışın var; ${week.locked} tanesinin açıklaması Premium'da.";
  }
  if (week.wrong >= freeWhyWrongPerDay) {
    return "Bu hafta ${week.wrong} yanlışının açıklamasını gördün. Premium'da günlük sınır yok.";
  }
  return null;
}

/// One goal outcome under the hero ("Sınava kadar her gün ne çalışacağın belli").
class _Outcome extends StatelessWidget {
  const _Outcome(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_rounded, size: 18, color: Brand.success),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
        ),
      ],
    ),
  );
}

/// A highlighted line: the value line or a caller's pitch.
class _Pitch extends StatelessWidget {
  const _Pitch(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Brand.accentBg, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Icon(Icons.record_voice_over_rounded, color: Brand.ink),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
        ),
      ],
    ),
  );
}

/// Display-only prices while Google Play's are not loaded. Buying always
/// uses the store's own prices.
class _PriceAnchor extends StatelessWidget {
  const _PriceAnchor({required this.trialDays});
  final int trialDays;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('paywall-price-anchor'),
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Brand.card,
      border: Border.all(color: Brand.primary, width: 2),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Yıllık plan önerilir', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 2),
        Text(paywallPriceAnchor, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (trialDays > 0)
          Text(
            'Yıllık planda $trialDays gün ücretsiz dene; deneme bitmeden iptal edersen ücret alınmaz.',
            style: TextStyle(color: Brand.success, fontWeight: FontWeight.w800),
          ),
        const SizedBox(height: 4),
        Text(
          'Kesin fiyatı Google Play gösterir; ödeme ondan önce alınmaz.',
          style: TextStyle(color: Brand.muted, fontSize: 12),
        ),
      ],
    ),
  );
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.emoji, required this.title, required this.description});
  final String emoji;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Brand.card,
      border: Border.all(color: Brand.line, width: 2),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Glyph(emoji: emoji, icon: Icons.check_circle_outline_rounded, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(description, style: TextStyle(color: Brand.muted, fontSize: 13)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Personal extends StatelessWidget {
  const _Personal(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('paywall-personal'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Brand.errorBg.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(Icons.lightbulb_rounded, color: Brand.error),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
        ),
      ],
    ),
  );
}

class _TrialBanner extends StatelessWidget {
  const _TrialBanner({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('paywall-trial'),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: Brand.successBg, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Icon(Icons.card_giftcard_rounded, color: Brand.success),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Yıllık planda ilk $days gün ücretsiz. Deneme bitmeden iptal edersen hiç ücret ödemezsin.',
            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3),
          ),
        ),
      ],
    ),
  );
}

/// Shown when Google Play gives no products: why, and what to try.
class _Unavailable extends StatelessWidget {
  const _Unavailable({this.onRetry});
  final VoidCallback? onRetry;

  static const _tips = [
    'İnternet bağlantını kontrol et.',
    "Play Store'u aç ve Google hesabınla oturum açık olduğundan emin ol.",
    "Çenebaz'ı Play Store'dan yükle; başka yerden kurulan sürümlerde satın alma çalışmaz.",
    'Play Store güncel değilse güncelle, sonra tekrar dene.',
  ];

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('paywall-unavailable'),
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Brand.accentBg, borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.storefront_rounded, color: Brand.ink),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                "Google Play'e şu an ulaşılamadı, bu yüzden fiyatlar gösterilemiyor.",
                style: TextStyle(fontWeight: FontWeight.w800, height: 1.3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final t in _tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text('•  $t', style: const TextStyle(fontSize: 13, height: 1.3)),
          ),
        const SizedBox(height: 4),
        Text(
          'Premium\'u daha önce aldıysan aşağıdaki "Satın alımları geri yükle" ile açabilirsin. '
          'Hiçbir ücret alınmadı.',
          style: TextStyle(fontSize: 12.5, color: Brand.muted, height: 1.3),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const ValueKey('paywall-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tekrar dene'),
          ),
        ),
      ],
    ),
  );
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow(this.feature, {required this.highlighted, this.compact = false});
  final PremiumFeature feature;
  final bool highlighted;

  /// Title only (the description is read out by screen readers).
  final bool compact;

  @override
  Widget build(BuildContext context) => compact
      ? Semantics(
          label: '${feature.title}. ${feature.description}',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
            child: Row(
              children: [
                Glyph(emoji: feature.emoji, icon: Icons.check_circle_outline_rounded, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(feature.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        )
      : Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: highlighted ? Brand.primary.withValues(alpha: 0.08) : Brand.card,
            border: Border.all(color: highlighted ? Brand.primary : Brand.line, width: 2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Glyph(emoji: feature.emoji, icon: Icons.check_circle_outline_rounded, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(feature.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(feature.description, style: TextStyle(color: Brand.muted, fontSize: 13)),
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
                Icon(Icons.check_rounded, size: 18, color: Brand.success),
                const SizedBox(width: 6),
                Expanded(child: Text(item, style: const TextStyle(fontSize: 13))),
              ],
            ),
          ),
        Text(
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
    // Savings are computed from the store's real prices, never made up: with
    // no monthly price from Play there is no badge at all.
    final saving = plan == PremiumPlan.yearly ? yearlySavingPercent(product, monthly) : 0;
    final best = saving > 0 && priceCopy != PriceCopy.plain;
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
                    if (!best && plan == PremiumPlan.recommended) ...[
                      const SizedBox(width: 8),
                      _Badge(
                        key: const ValueKey('plan-recommended'),
                        text: 'Önerilen',
                        color: Brand.primary,
                        foreground: Colors.white,
                      ),
                    ],
                    if (best) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _Badge(
                              key: const ValueKey('plan-best'),
                              text: 'En avantajlı',
                              color: Brand.primary,
                              foreground: Colors.white,
                            ),
                            if (priceCopy == PriceCopy.savings)
                              _Badge(text: '%$saving tasarruf', color: Brand.accent),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  plan.isFamily
                      ? '${product.price} / ${plan.period} · $familySeats kişiye kadar'
                      : '${product.price} / ${plan.period}',
                  style: TextStyle(color: Brand.muted),
                ),
                if (priceCopy == PriceCopy.monthlyEquivalent && plan == PremiumPlan.yearly)
                  if (formatPerMonth(product.price, product.rawPrice / 12) case final perMonth?)
                    Text('Aylık yalnızca $perMonth', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (showTrial && product.freeTrialDays > 0)
                  Text(
                    '${product.freeTrialDays} gün ücretsiz, sonra ${product.price} / ${plan.period}',
                    key: ValueKey('plan-trial-${plan.name}'),
                    style: TextStyle(color: Brand.success, fontWeight: FontWeight.w800),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.text, required this.color, this.foreground});
  final String text;
  final Color color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: foreground),
    ),
  );
}

/// Whole percent the yearly plan saves against twelve months of the monthly
/// plan, both from Google Play's real prices. 0 when a price is missing or
/// yearly is not cheaper (then no badge is shown).
int yearlySavingPercent(StoreProduct yearly, StoreProduct? monthly) {
  if (monthly == null || monthly.rawPrice <= 0 || yearly.rawPrice <= 0) return 0;
  final p = (100 - yearly.rawPrice * 100 / (monthly.rawPrice * 12)).round();
  return p > 0 ? p : 0;
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color ?? Brand.accentBg, borderRadius: BorderRadius.circular(14)),
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
