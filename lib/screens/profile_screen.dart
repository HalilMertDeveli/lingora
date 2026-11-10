import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tr_errors.dart';
import '../data/progress.dart';
import '../org/org_widgets.dart';
import '../services/billing/premium.dart';
import '../services/growth/analytics.dart';
import '../theme.dart';
import '../ui/appearance.dart';
import 'account_section.dart';
import 'error_analysis_screen.dart';
import 'growth_profile_section.dart';
import 'onboarding_screen.dart';
import 'paywall_screen.dart';
import 'placement_screen.dart';
import 'reminder_settings.dart';

const _weekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final premium = ref.watch(premiumProvider);
    final now = ref.watch(clockProvider)();
    final t = Theme.of(context).textTheme;
    final accuracy = p.answered == 0 ? 0 : (p.correct * 100 / p.answered).round();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            LingoraLogo(size: 64),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Öğrenci', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  Text('İngilizce öğreniyor', style: TextStyle(color: Brand.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('İstatistikler', style: t.titleLarge),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.2,
          children: [
            _StatCard(Icons.local_fire_department, Brand.streak, '${p.streakAt(now)}', 'Günlük seri'),
            _StatCard(Icons.bolt, Brand.xp, '${p.totalXp}', 'Toplam XP'),
            _StatCard(Icons.menu_book_rounded, Brand.primary, '${p.lessonsDone}', 'Bitirilen ders'),
            _StatCard(Icons.track_changes, Brand.success, '%$accuracy', 'Doğruluk'),
          ],
        ),
        const SizedBox(height: 24),
        Text('Sık yaptığın hatalar', style: t.titleLarge),
        const SizedBox(height: 12),
        TapCard(child: _ErrorStatsCard(progress: p)),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              final gate = await requirePremium(context, ref, PremiumFeature.errorAnalytics);
              if (gate == GateResult.premium && context.mounted) {
                logEventFrom(context, AnalyticsEvent.featureUse(AppFeature.errorAnalysis));
                await Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const ErrorAnalysisScreen()));
              }
            },
            icon: Icon(premium ? Icons.insights_rounded : Icons.lock_rounded, size: 18),
            label: const Text('Detaylı hata analizi'),
          ),
        ),
        const SizedBox(height: 12),
        Text('Lingora Premium', style: t.titleLarge),
        const SizedBox(height: 12),
        TapCard(
          key: const ValueKey('profile-premium'),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const PaywallScreen())),
          child: Row(
            children: [
              Text(premium ? '⭐' : '✨', style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  premium ? 'Premium aktif. Aboneliğini görüntüle veya geri yükle.' : 'Yapay zekâ sohbeti, sınırsız deneme ve detaylı hata analizi. Temel öğrenme ücretsiz.',
                  style: TextStyle(color: Brand.muted),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Brand.muted),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Son 7 gün', style: t.titleLarge),
        const SizedBox(height: 12),
        TapCard(
          child: _WeekChart(progress: p, now: now),
        ),
        const SizedBox(height: 24),
        Text('Seviye testi', style: t.titleLarge),
        const SizedBox(height: 12),
        const PlacementProfileCard(),
        const SizedBox(height: 24),
        Text('Günlük hedef', style: t.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final (xp, name, _) in dailyGoals)
              ChoiceChip(
                label: Text('$name · $xp XP'),
                selected: p.dailyGoal == xp,
                onSelected: (_) => ref.read(progressProvider.notifier).setDailyGoal(xp),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Bildirimler', style: t.titleLarge),
        const SizedBox(height: 12),
        const ReminderSettings(),
        const SizedBox(height: 24),
        const OrgSection(),
        Text('Hesap', style: t.titleLarge),
        const SizedBox(height: 12),
        const AccountSection(),
        const SizedBox(height: 24),
        Text('Görünüm', style: t.titleLarge),
        const SizedBox(height: 12),
        const AppearanceSettings(),
        const GrowthProfileSection(),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          icon: Icon(Icons.restart_alt, color: Brand.error),
          label: Text('İlerlemeyi sıfırla', style: TextStyle(color: Brand.error)),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('İlerleme sıfırlansın mı?'),
                content: const Text('Tüm XP, seri ve tamamlanan dersler silinir. Bu işlem geri alınamaz.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
                  TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: Text('Sıfırla', style: TextStyle(color: Brand.error)),
                  ),
                ],
              ),
            );
            if (ok == true) ref.read(progressProvider.notifier).reset();
          },
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.icon, this.color, this.value, this.label);
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => TapCard(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Brand.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.progress, required this.now});
  final Progress progress;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final days = [for (var i = 6; i >= 0; i--) now.subtract(Duration(days: i))];
    final values = [for (final d in days) progress.xpOn(d)];
    final top = [progress.dailyGoal, ...values].reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${values[i]}', style: TextStyle(fontSize: 11, color: Brand.muted)),
                  const SizedBox(height: 4),
                  Container(
                    height: 100 * values[i] / top + 4,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: values[i] >= progress.dailyGoal ? Brand.success : Brand.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _weekdays[days[i].weekday - 1],
                    style: TextStyle(fontSize: 12, fontWeight: i == 6 ? FontWeight.w900 : FontWeight.w500),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Sık yaptığın hatalar": the Türk hata dedektörü's most frequent
/// categories with a tip for the top one.
class _ErrorStatsCard extends StatelessWidget {
  const _ErrorStatsCard({required this.progress});
  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final top = progress.topErrorCategories();
    if (top.isEmpty) {
      return Row(
        children: [
          const Glyph(emoji: '🔍', icon: Icons.manage_search_rounded, size: 26),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Henüz kayıtlı hata yok. Ders, günlük ve sohbette yaptığın hatalar burada toplanır; '
              'en sık olanlara özel ipuçları göreceksin.',
              style: TextStyle(color: Brand.muted),
            ),
          ),
        ],
      );
    }
    final most = top.first.$2;
    final TrErrorCategory first = top.first.$1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (category, count) in top)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(category.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    Text('$count kez', style: TextStyle(color: Brand.muted, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: count / most,
                    minHeight: 8,
                    color: Brand.error,
                    backgroundColor: Brand.line,
                  ),
                ),
              ],
            ),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Brand.accentBg, borderRadius: BorderRadius.circular(12)),
          child: Text('${Brand.isKid ? '💡 ' : ''}İpucu: ${first.tip}', style: const TextStyle(height: 1.3)),
        ),
      ],
    );
  }
}
