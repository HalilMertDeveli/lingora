import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_links.dart';
import '../data/app_settings.dart';
import '../data/first_lesson.dart';
import '../data/placement.dart';
import '../data/progress.dart';
import '../goals/learn_goal.dart';
import '../services/firebase/account_service.dart';
import '../services/firebase/firebase_providers.dart';
import '../services/growth/analytics.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import 'auth_screen.dart';
import 'lesson_screen.dart';
import 'placement_screen.dart';

const dailyGoals = [
  (10, 'Rahat', 'Günde ~5 dakika'),
  (20, 'Normal', 'Günde ~10 dakika'),
  (30, 'Ciddi', 'Günde ~15 dakika'),
  (50, 'Yoğun', 'Günde ~25 dakika'),
];

/// Set when onboarding ends without asking the daily goal: the path's daily
/// goal card asks for it later, once the learner has done a few lessons.
const dailyGoalPendingKey = 'daily_goal_pending_v1';

/// The one question of the first run: what the learner is here for. It sets
/// the look (Ebeveyn gözetimli mod, AppMode.kid), the course and the goal card at once; everything
/// else (account, reminders, daily goal, level test) is asked later, at a
/// natural moment.
enum StartGoal {
  general('🌍', 'Genel İngilizce', 'Sıfırdan ya da yeniden, günlük hayat için'),
  speaking('🗣️', 'Konuşmak / seyahat', 'Günlük konuşma ve yolculuk'),
  exam('📝', 'YDS / YÖKDİL', 'Sınava hazırlık, tarihe göre plan'),
  interview('💼', 'İş görüşmesi', 'Mülakata hazır gir'),
  lgs('🏫', "LGS'ye hazırlık", '8. sınıf İngilizcesi, sade ve renkli görünüm'),
  kid('👪', 'Ebeveyn olarak, çocuğumla', 'Ebeveyn hesabıyla, ebeveyn gözetiminde');

  const StartGoal(this.emoji, this.title, this.subtitle);
  final String emoji;
  final String title;
  final String subtitle;

  /// LGS and the parent-led option use Ebeveyn gözetimli mod (AppMode.kid: no AI,
  /// no friends, no exam or job goals). Play target audience is 13+ (decision a).
  AppMode get mode => this == lgs || this == kid ? AppMode.kid : AppMode.adult;

  LearnReason get reason => switch (this) {
    exam => LearnReason.academic,
    interview => LearnReason.work,
    lgs => LearnReason.school,
    general || speaking || kid => LearnReason.general,
  };

  /// The "Hedefin ne?" goal (adults only).
  GoalKind? get goalKind => switch (this) {
    general => GoalKind.general,
    speaking => GoalKind.speaking,
    exam => GoalKind.exam,
    interview => GoalKind.interview,
    lgs || kid => null,
  };
}

/// First run: welcome → one goal → the first lesson at once.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  StartGoal? _goal;

  static const _steps = ['welcome', 'goal'];

  /// Welcome, goal, first lesson.
  static const _totalSteps = 3;

  void _next() => _pages.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);

  void _pick(StartGoal g) {
    setState(() => _goal = g);
    // The look changes at once, so the lesson already has it.
    ref.read(appSettingsProvider.notifier).setMode(g.mode);
  }

  /// Track and goal from the choice.
  void _applyGoal(StartGoal g, PlacementRecommendation plan) {
    final progress = ref.read(progressProvider.notifier);
    applyPlacement(progress, plan);
    if (g.goalKind case final kind?) {
      progress.setLearnGoal(LearnGoal(kind: kind, at: ref.read(clockProvider)().millisecondsSinceEpoch));
    }
    logEvent(ref, AnalyticsEvent.trackChosen(plan.trackId, source: 'onboarding'));
  }

  void _finish({required String method, required String track}) {
    ref.read(prefsProvider).setBool(dailyGoalPendingKey, true);
    final goal = ref.read(progressProvider).dailyGoal;
    ref.read(progressProvider.notifier).finishOnboarding(goal);
    logEvent(ref, AnalyticsEvent.onboardingComplete(method: method, dailyGoal: goal, track: track));
  }

  /// The first lesson right away (a beginner's start, no level yet).
  /// Onboarding ends when the lesson closes, finished or left: its result
  /// screens then return to the path.
  Future<void> _startFirstLesson() async {
    final g = _goal;
    if (g == null) return;
    final plan = recommend(level: null, reason: g.reason, courseUnits: const [], lessons: const []);
    _applyGoal(g, plan);
    logEvent(ref, AnalyticsEvent.onboardingStep('first_lesson', _steps.length));
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => LessonScreen(
          nodeId: firstLessonId,
          title: firstLessonTitle,
          items: firstLessonItems(),
          color: Brand.primary,
        ),
      ),
    );
    if (!mounted) return;
    _finish(method: 'first_lesson', track: plan.trackId);
  }

  /// "İngilizcem var": the level test instead of the first lesson.
  void _startTest() {
    final g = _goal ?? StartGoal.general;
    logEvent(ref, AnalyticsEvent.placementStart());
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlacementTestScreen(
          reason: g.reason,
          onDone: (ctx, plan) {
            Navigator.of(ctx).popUntil((r) => r.isFirst);
            _applyGoal(g, plan);
            _finish(method: 'placement', track: plan.trackId);
          },
        ),
      ),
    );
  }

  void _logStep(int i) => logEvent(ref, AnalyticsEvent.onboardingStep(_steps[i], i));

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
                      tooltip: 'Geri',
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
                        value: (_page + 1) / _totalSteps,
                        // TalkBack read a bare "33" here.
                        semanticsLabel: 'Adım ${_page + 1} / $_totalSteps',
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
                    _GoalStep(goal: _goal, onChanged: _pick),
                  ],
                ),
              ),
              if (_page == 0)
                FilledButton(
                  key: const ValueKey('onboarding-next'),
                  onPressed: _next,
                  child: const Text('Başla'),
                )
              else ...[
                FilledButton(
                  key: const ValueKey('onboarding-start'),
                  onPressed: _goal == null ? null : _startFirstLesson,
                  child: const Text('İlk derse başla'),
                ),
                const SizedBox(height: 4),
                TextButton(
                  key: const ValueKey('onboarding-placement'),
                  onPressed: _startTest,
                  child: const Text('İngilizcem var, seviyemi ölçeyim'),
                ),
              ],
              if (_page == 0) const _SignInLink(),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Zaten hesabın var mı? Giriş yap" on the welcome page. Signing in pulls the
/// account's progress; if that account already finished onboarding the app
/// goes straight to the path (main.dart watches `onboarded`).
class _SignInLink extends ConsumerWidget {
  const _SignInLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(accountServiceProvider);
    final user = ref.watch(authStateProvider).value;
    // Hidden without Firebase, and while the guest account is still being
    // created (an anonymous sign-in in flight would replace this one).
    if (service == null || user == null || !user.isAnonymous) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextButton(
        key: const ValueKey('onboarding-sign-in'),
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final ok = await Navigator.of(context)
              .push(MaterialPageRoute<bool>(builder: (_) => AuthScreen(service: service)));
          if (ok == true) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Giriş yapıldı. İlerlemen bu hesaba bağlı.')),
            );
          }
        },
        child: const Text('Zaten hesabın var mı? Giriş yap'),
      ),
    );
  }
}

/// Çenebaz brand mark: Çaycı Dayı on his orange tile, the same art as the
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
    semanticLabel: 'Çenebaz',
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
        // Welcome: Pofuduk waves in both modes. Kid mode: he is the host, big
        // and lively. Adult: beside Çaycı Dayı's still brand mark.
        if (context.isKid)
          const Pofuduk(mood: Mood.wave, size: 180)
        else
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              LingoraLogo(size: 96),
              SizedBox(width: 12),
              Pofuduk(mood: Mood.wave, size: 112),
            ],
          ),
        const SizedBox(height: 28),
        Text(appDisplayName, style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(
          appTagline,
          textAlign: TextAlign.center,
          style: t.titleSmall?.copyWith(color: Brand.primary, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          context.isKid
              ? 'Hoş geldin, ben Pofuduk!\nHer gün birkaç dakika birlikte öğrenelim.'
              : 'Her gün birkaç dakika,\nadım adım yeni bir dil.',
          textAlign: TextAlign.center,
          style: t.titleMedium?.copyWith(color: Brand.muted, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

/// The one goal question. A choice applies its look at once.
class _GoalStep extends StatelessWidget {
  const _GoalStep({required this.goal, required this.onChanged});
  final StartGoal? goal;
  final ValueChanged<StartGoal> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      key: const ValueKey('onboarding-goal'),
      padding: const EdgeInsets.only(top: 24),
      children: [
        Text('Ne için İngilizce?', style: t.headlineSmall),
        const SizedBox(height: 6),
        Text(
          "Birini seç, hemen 2–3 dakikalık ilk dersine başla. Gerisini sonra Profil'den "
          'değiştirebilirsin.',
          style: t.bodyMedium?.copyWith(color: Brand.muted),
        ),
        const SizedBox(height: 16),
        for (final g in StartGoal.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TapCard(
              key: ValueKey('start-goal-${g.name}'),
              selected: goal == g,
              onTap: () => onChanged(g),
              child: Row(
                children: [
                  Text(g.emoji, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.title, style: t.titleMedium),
                        Text(g.subtitle, style: t.bodySmall?.copyWith(color: Brand.muted)),
                      ],
                    ),
                  ),
                  if (goal == g) Icon(Icons.check_circle, color: Brand.primary),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
