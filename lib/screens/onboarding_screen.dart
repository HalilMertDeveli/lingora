import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../theme.dart';

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

  void _next() {
    if (_page < 2) {
      _pages.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else {
      ref.read(progressProvider.notifier).finishOnboarding(_goal);
    }
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
                        value: (_page + 1) / 3,
                        minHeight: 10,
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
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    const _Welcome(),
                    const _CoursePick(),
                    _GoalPick(
                      goal: _goal,
                      onChanged: (g) => setState(() => _goal = g),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: _next,
                child: Text(_page == 2 ? 'Öğrenmeye başla' : 'Devam'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LingoraLogo extends StatelessWidget {
  const LingoraLogo({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Brand.primary, Color(0xFF9B7BFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Text(
        'L',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.55,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const LingoraLogo(size: 112),
        const SizedBox(height: 28),
        Text('Lingora', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Text(
          'Her gün birkaç dakika,\nadım adım yeni bir dil.',
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
        const TapCard(
          selected: true,
          child: ListTile(
            leading: Text('🇬🇧', style: TextStyle(fontSize: 32)),
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
                  leading: Text(flag, style: const TextStyle(fontSize: 32)),
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
        Text('Günlük hedefin ne olsun?', style: t.headlineSmall),
        const SizedBox(height: 6),
        Text('İstediğin zaman profilden değiştirebilirsin.',
            style: t.bodyMedium?.copyWith(color: Brand.muted)),
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
