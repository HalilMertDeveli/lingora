import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings.dart';
import '../data/placement.dart';
import '../data/progress.dart';
import '../services/growth/analytics.dart';
import '../theme.dart';
import '../ui/flag.dart';
import '../ui/mascot.dart';
import 'placement_screen.dart';

const dailyGoals = [
  (10, 'Rahat', 'Günde ~5 dakika'),
  (20, 'Normal', 'Günde ~10 dakika'),
  (30, 'Ciddi', 'Günde ~15 dakika'),
  (50, 'Yoğun', 'Günde ~25 dakika'),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  int _goal = 20;
  LearnReason _reason = LearnReason.general;

  static const _pageCount = 5;

  void _next() => _pages.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);

  /// Applies the chosen plan (track + known nodes), then leaves onboarding.
  void _finish(PlacementRecommendation plan, {required String method}) {
    final progress = ref.read(progressProvider.notifier);
    applyPlacement(progress, plan);
    progress.finishOnboarding(_goal);
    logEvent(ref, AnalyticsEvent.trackChosen(plan.trackId, source: 'onboarding'));
    logEvent(ref, AnalyticsEvent.onboardingComplete(method: method, dailyGoal: _goal, track: plan.trackId));
  }

  void _fromScratch() => _finish(
    recommend(level: null, reason: _reason, courseUnits: const [], lessons: const []),
    method: 'scratch',
  );

  void _startTest() {
    logEvent(ref, AnalyticsEvent.placementStart());
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlacementTestScreen(
          reason: _reason,
          onDone: (ctx, plan) {
            Navigator.of(ctx).popUntil((r) => r.isFirst);
            _finish(plan, method: 'placement');
          },
        ),
      ),
    );
  }

  /// Page names for `onboarding_step`; extra pages are logged as `step_<i>`.
  static const _stepNames = ['welcome', 'audience', 'course', 'goal', 'level'];

  void _logStep(int i) =>
      logEvent(ref, AnalyticsEvent.onboardingStep(i < _stepNames.length ? _stepNames[i] : 'step_$i', i));

  @override
  void initState() {
    super.initState();
    _logStep(0);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  if (_page > 0)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => _pages.previousPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut,
                      ),
                    )
                  else
                    const SizedBox(width: 48),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: (_page + 1) / _pageCount,
                        minHeight: Brand.isKid ? 10 : 6,
                        backgroundColor: Brand.line,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) {
                    setState(() => _page = i);
                    _logStep(i);
                  },
                  children: [
                    const _Welcome(),
                    const _AudiencePick(),
                    const _CoursePick(),
                    _GoalPick(goal: _goal, onChanged: (g) => setState(() => _goal = g)),
                    _LevelStep(reason: _reason, onChanged: (r) => setState(() => _reason = r)),
                  ],
                ),
              ),
              if (_page < _pageCount - 1)
                FilledButton(onPressed: _next, child: const Text('Devam'))
              else ...[
                FilledButton(onPressed: _startTest, child: const Text('Seviyeni ölç')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _fromScratch, child: const Text('Sıfırdan başla')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Dilbaz brand mark: Çaycı Dayı on his orange tile, the same art as the
/// app icon.
class LingoraLogo extends StatelessWidget {
  const LingoraLogo({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    mascotAsset,
    key: const ValueKey('dilbaz-logo'),
    width: size,
    height: size,
    semanticLabel: 'Dilbaz',
    errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Kid mode: Çaycı Dayı greets you, big and lively. Adult: the still brand mark.
        if (context.isKid) const Dayi(mood: Mood.happy, size: 180) else const LingoraLogo(size: 112),
        const SizedBox(height: 28),
        Text('Dilbaz', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Text(
          context.isKid
              ? 'Hoş geldin, ben Çaycı Dayı!\nÇayını al, her gün birkaç dakika birlikte öğrenelim.'
              : 'Her gün birkaç dakika,\nadım adım yeni bir dil.',
          textAlign: TextAlign.center,
          style: t.titleMedium?.copyWith(color: Brand.muted, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _CoursePick extends StatelessWidget {
  const _CoursePick();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.only(top: 32),
      children: [
        Text('Ne öğrenmek istiyorsun?', style: t.headlineSmall),
        const SizedBox(height: 20),
        TapCard(
          selected: true,
          child: ListTile(
            leading: const FlagIcon('assets/flags/gb.png', width: 36),
            title: Text('İngilizce', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Türkçe konuşanlar için'),
            trailing: Icon(Icons.check_circle, color: Brand.primary),
          ),
        ),
        const SizedBox(height: 12),
        for (final (flag, name) in const [('🇩🇪', 'Almanca'), ('🇪🇸', 'İspanyolca')])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Opacity(
              opacity: 0.45,
              child: TapCard(
                child: ListTile(
                  leading: Glyph(emoji: flag, icon: Icons.language_rounded, size: 32, color: Brand.muted),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Yakında'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _GoalPick extends StatelessWidget {
  const _GoalPick({required this.goal, required this.onChanged});
  final int goal;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.only(top: 32),
      children: [
        const Center(child: Mascot(mood: Mood.joy, size: 100, decorative: true)),
        Text('Günlük hedefin ne olsun?', style: t.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'İstediğin zaman profilden değiştirebilirsin.',
          style: t.bodyMedium?.copyWith(color: Brand.muted),
        ),
        const SizedBox(height: 20),
        for (final (xp, name, hint) in dailyGoals)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TapCard(
              selected: goal == xp,
              onTap: () => onChanged(xp),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: t.titleMedium),
                        Text(hint, style: t.bodySmall?.copyWith(color: Brand.muted)),
                      ],
                    ),
                  ),
                  Text('$xp XP / gün', style: t.titleSmall?.copyWith(color: Brand.muted)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Optional placement step: why the user learns, then test or skip.
class _LevelStep extends StatelessWidget {
  const _LevelStep({required this.reason, required this.onChanged});
  final LearnReason reason;
  final ValueChanged<LearnReason> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.only(top: 24),
      children: [
        Text('Neden İngilizce öğreniyorsun?', style: t.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Biraz biliyorsan kısa bir seviye testiyle bildiğin yerleri atlayabilirsin. '
          "İstersen sıfırdan başla; testi sonra Profil'den de çözebilirsin.",
          style: t.bodyMedium?.copyWith(color: Brand.muted),
        ),
        const SizedBox(height: 16),
        ReasonPicker(selected: reason, onChanged: onChanged),
      ],
    );
  }
}

/// "Kimin için?": picks the look. Applies at once so the rest of onboarding
/// already previews it; changeable later in Profil > Görünüm.
class _AudiencePick extends ConsumerWidget {
  const _AudiencePick();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final mode = ref.watch(appSettingsProvider.select((s) => s.mode));
    Widget option(AppMode m, IconData icon, String emoji, String title, String hint) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TapCard(
        selected: mode == m,
        onTap: () => ref.read(appSettingsProvider.notifier).setMode(m),
        child: Row(
          children: [
            IconBadge(icon: icon, emoji: emoji, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleMedium),
                  const SizedBox(height: 2),
                  Text(hint, style: t.bodySmall),
                ],
              ),
            ),
            if (mode == m) Icon(Icons.check_circle, color: Brand.primary),
          ],
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.only(top: 32),
      children: [
        Text('Kimin için?', style: t.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Görünümü buna göre ayarlarız. İstediğin zaman profilden değiştirebilirsin.',
          style: t.bodyMedium?.copyWith(color: Brand.muted),
        ),
        const SizedBox(height: 20),
        option(
          AppMode.adult,
          Icons.school_outlined,
          '🎓',
          'Kendim için',
          'Lise, üniversite, iş ve sınavlar. Sade ve odaklı görünüm.',
        ),
        option(
          AppMode.kid,
          Icons.child_care_rounded,
          '🧒',
          'Çocuğum için (Çocuk modu)',
          'İlkokul, ortaokul ve LGS. Maskot, renkler ve kutlamalarla eğlenceli görünüm.',
        ),
      ],
    );
  }
}
