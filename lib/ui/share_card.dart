import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_links.dart';
import '../data/progress.dart';
import '../data/share_card.dart';
import '../screens/onboarding_screen.dart' show LingoraLogo;
import '../services/billing/premium.dart';
import '../services/growth/analytics_events.dart' show PaywallPlacement;
import '../theme.dart';
import 'level_certificate.dart' show certificateSize, sharePng;
import 'premium_offer.dart';

/// The shareable progress image (4:5, rendered at 3× = 1080 × 1350 px).
/// Fixed colours so every share looks the same; Çocuk modu shows Pofuduk
/// instead of the Çenebaz mark.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.data, this.kid = false});

  final ShareCardData data;
  final bool kid;

  static const _ink = Color(0xFF14213D);
  static const _orange = Color(0xFFFF7A1A);
  static const _sun = Color(0xFFFFC94D);
  static const _sky = Color(0xFF2EC4B6);
  static const _paper = Color(0xFFFFFAF2);

  @override
  Widget build(BuildContext context) {
    final d = data;
    return SizedBox.fromSize(
      size: certificateSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: d.monthly
                ? const [Color(0xFF1B2A6B), Color(0xFF6C4CF1)]
                : const [_orange, Color(0xFFFF4D6D)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: DecoratedBox(
            decoration: BoxDecoration(color: _paper, borderRadius: BorderRadius.circular(22)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: DefaultTextStyle(
                style: const TextStyle(color: _ink, fontFamilyFallback: ['Roboto']),
                child: Column(
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 34,
                          height: 34,
                          child: kid
                              ? Image.asset('assets/mascot/pofuduk_selam.png', semanticLabel: 'Pofuduk')
                              : const ClipRRect(
                                  borderRadius: BorderRadius.all(Radius.circular(9)),
                                  child: LingoraLogo(size: 34),
                                ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          appDisplayName,
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: _orange),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: d.month == null
                              ? const SizedBox.shrink()
                              : Text(
                                  d.month!.toUpperCase(),
                                  textAlign: TextAlign.end,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (d.level != null)
                      _LevelBadge(level: d.level!.code, previous: d.leveledUp ? d.previousLevel?.code : null),
                    const SizedBox(height: 10),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        d.headline,
                        key: const Key('share-headline'),
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1.1),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _Stat(emoji: '🔥', value: '${d.streak}', label: 'günlük seri'),
                        ),
                        if (d.wordsLearned > 0) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: _Stat(emoji: '📚', value: '${d.wordsLearned}', label: 'kelime öğrendim'),
                          ),
                        ],
                        if (d.monthly) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: _Stat(emoji: '📅', value: '${d.activeDays}', label: 'gün çalıştım'),
                          ),
                        ],
                      ],
                    ),
                    if (d.monthly) ...[
                      const SizedBox(height: 12),
                      _MonthBars(daily: d.dailyXp),
                      const SizedBox(height: 4),
                      Text(
                        'Bu ay ${d.monthXp} XP',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ],
                    const Spacer(),
                    const Divider(height: 1, color: Color(0x2214213D)),
                    const SizedBox(height: 6),
                    const Text(
                      "Benimle İngilizce öğren: $appDisplayName · Google Play",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                    const Text(playStoreLinkShort, style: TextStyle(fontSize: 9.5, color: Color(0xFF5B6475))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, this.previous});
  final String level;
  final String? previous;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (previous != null) ...[
        Text(
          previous!,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0x8814213D)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward_rounded, color: ShareCard._orange, size: 28),
        ),
      ],
      Container(
        width: 92,
        height: 92,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [Color(0xFFFFE9A8), ShareCard._sun]),
          border: Border.all(color: ShareCard._ink, width: 3),
        ),
        child: Text(level, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, height: 1)),
      ),
    ],
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.emoji, required this.value, required this.label});
  final String emoji;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    decoration: BoxDecoration(
      color: ShareCard._sky.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        Text('$emoji $value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

/// One small bar per day of the month so far (XP, scaled to the best day).
class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.daily});
  final List<int> daily;

  @override
  Widget build(BuildContext context) {
    final top = daily.fold(1, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final x in daily)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  height: x == 0 ? 3 : 6 + 28 * x / top,
                  decoration: BoxDecoration(
                    color: x == 0 ? const Color(0x2214213D) : ShareCard._orange,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Preview of the share card with a switch between the milestone card
/// (free) and the monthly card (Premium), and the system share sheet.
class ShareCardScreen extends ConsumerStatefulWidget {
  const ShareCardScreen({super.key});

  @override
  ConsumerState<ShareCardScreen> createState() => _ShareCardScreenState();
}

class _ShareCardScreenState extends ConsumerState<ShareCardScreen> {
  final _key = GlobalKey();
  bool _monthly = false;
  bool _busy = false;

  Future<void> _share(ShareCardData data) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      await sharePng(
        _key,
        fileName: 'cenebaz_${data.monthly ? 'aylik' : 'basari'}.png',
        text: '${data.headline} $appDisplayName ile İngilizce öğreniyorum: $playStoreLink',
        origin: origin,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Görsel paylaşılamadı.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final premium = ref.watch(premiumProvider);
    final monthly = _monthly && premium;
    final data = buildShareCard(ref.watch(progressProvider), ref.watch(clockProvider)(), monthly: _monthly);
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Paylaşım kartı')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SegmentedButton<bool>(
                segments: [
                  const ButtonSegment(
                    value: false,
                    label: Text('Kilometre taşı'),
                    icon: Icon(Icons.flag_rounded),
                  ),
                  ButtonSegment(
                    value: true,
                    label: const Text('Aylık kart'),
                    icon: Icon(premium ? Icons.calendar_month_rounded : Icons.lock_rounded),
                  ),
                ],
                selected: {_monthly},
                onSelectionChanged: (s) => setState(() => _monthly = s.first),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FittedBox(
                    child: Stack(
                      children: [
                        RepaintBoundary(
                          key: _key,
                          child: ShareCard(key: const Key('share-card'), data: data, kid: context.isKid),
                        ),
                        if (_monthly && !premium)
                          Positioned.fill(child: ColoredBox(color: p.surface.withValues(alpha: 0.55))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_monthly && !premium)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: PremiumOfferCard(
                  placement: PaywallPlacement.shareCard,
                  dense: true,
                  icon: Icons.calendar_month_rounded,
                  title: 'Aylık kart Premium\'da',
                  body: 'Ayın aktif günleri, XP grafiğin ve seviye değişiminle zengin kart.',
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('share-card-share'),
                    onPressed: _busy ? null : () => _share(data),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(monthly ? 'Aylık kartı paylaş' : 'Görseli paylaş'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
