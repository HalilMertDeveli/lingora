import 'package:flutter/material.dart';

import '../data/practice.dart';
import '../data/progress.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';

class LessonResultScreen extends StatelessWidget {
  const LessonResultScreen({
    super.key,
    required this.reward,
    required this.accuracy,
    required this.duration,
    required this.perfect,
    this.bestCombo = 0,
    this.headline,
    this.onContinue,
    this.showStreak = true,
  });

  final LessonReward reward;
  final int accuracy;
  final Duration duration;
  final bool perfect;
  final int bestCombo;

  /// Overrides the default "Ders tamamlandı!" title.
  final String? headline;

  /// "Devam": the next end-of-lesson screen; closes the screen when null.
  final VoidCallback? onContinue;

  /// False when a separate streak screen follows.
  final bool showStreak;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mm = duration.inMinutes.toString();
    final ss = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final goalDone = reward.todayXp >= reward.dailyGoal;
    const step = Duration(milliseconds: 140);
    var delay = const Duration(milliseconds: 350);
    Duration next() => delay += step;

    return Scaffold(
      body: Confetti(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Spacer(),
                Mascot(mood: perfect ? Mood.cheer : Mood.happy, size: 150),
                const SizedBox(height: 8),
                PopIn(
                  delay: const Duration(milliseconds: 150),
                  child: Text(
                    headline ?? (perfect ? 'Kusursuz ders!' : 'Ders tamamlandı!'),
                    style: t.headlineSmall?.copyWith(
                      color: !Brand.isKid ? Brand.ink : (perfect ? Brand.accent : Brand.primary),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _Tile(
                      'TOPLAM XP',
                      Icons.bolt,
                      Brand.xp,
                      next(),
                      CountUp(value: reward.xp, prefix: '+', style: _Tile.valueStyle),
                    ),
                    const SizedBox(width: 10),
                    _Tile(
                      'DOĞRULUK',
                      Icons.track_changes,
                      Brand.success,
                      next(),
                      CountUp(value: accuracy, prefix: '%', style: _Tile.valueStyle),
                    ),
                    const SizedBox(width: 10),
                    _Tile(
                      'SÜRE',
                      Icons.timer_outlined,
                      Brand.primary,
                      next(),
                      Text('$mm:$ss', style: _Tile.valueStyle),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (bestCombo >= 3)
                  _Banner(
                    delay: next(),
                    color: Brand.streak,
                    icon: Icons.whatshot_rounded,
                    text: 'En uzun seri: $bestCombo doğru üst üste',
                  ),
                if (showStreak && reward.streakExtended)
                  _Banner(
                    delay: next(),
                    color: Brand.streak,
                    icon: Icons.local_fire_department,
                    text: reward.streak == 1
                        ? 'Seri başladı! Yarın da gel.'
                        : '${reward.streak} günlük seri!',
                  ),
                for (final q in reward.questsCompleted)
                  _Banner(
                    delay: next(),
                    color: Brand.success,
                    icon: Icons.task_alt,
                    text: 'Görev tamamlandı: ${q.title}',
                    trailing: 'Ödül hazır',
                  ),
                const SizedBox(height: 10),
                Text(
                  goalDone
                      ? 'Günlük hedef tamam: ${reward.todayXp} / ${reward.dailyGoal} XP'
                      : 'Günlük hedef: ${reward.todayXp} / ${reward.dailyGoal} XP',
                  style: TextStyle(
                    color: goalDone ? Brand.success : Brand.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                PressableButton(label: 'DEVAM', onPressed: onContinue ?? () => Navigator.of(context).pop()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Second end-of-lesson screen when the lesson started or extended a streak.
class StreakCelebrationScreen extends StatelessWidget {
  const StreakCelebrationScreen({super.key, required this.streak, this.onContinue});
  final int streak;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('streak-celebration'),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Spacer(),
            PopIn(child: Icon(Icons.local_fire_department, color: Brand.streak, size: 120)),
            const SizedBox(height: 12),
            Text(
              streak == 1 ? 'Seri başladı!' : '$streak günlük seri!',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              streak == 1
                  ? 'Yarın da kısa bir ders yaparsan serin büyür.'
                  : 'Her gün biraz: en etkili öğrenme yolu bu.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.muted, fontSize: 16, height: 1.4),
            ),
            const Spacer(),
            PressableButton(label: 'DEVAM', onPressed: onContinue ?? () => Navigator.of(context).pop()),
          ],
        ),
      ),
    ),
  );
}

/// Shown when a unit test ends below the pass mark.
class TestFailedScreen extends StatelessWidget {
  const TestFailedScreen({super.key, required this.accuracy, this.onRetry});
  final int accuracy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Spacer(),
            const Mascot(mood: Mood.sad, size: 150),
            const SizedBox(height: 12),
            Text('Az kaldı!', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              '%$accuracy doğru yaptın. Geçmek için %$testPassPercent gerekiyor.\n'
              'Yanlışların "Hatalarını çalış" listesine eklendi.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.muted, fontSize: 16, height: 1.4),
            ),
            const Spacer(),
            if (onRetry != null) ...[
              PressableButton(label: 'TEKRAR DENE', onPressed: onRetry),
              const SizedBox(height: 12),
            ],
            PressableButton(
              label: 'ŞİMDİLİK ÇIK',
              outlined: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.delay,
    required this.color,
    required this.icon,
    required this.text,
    this.trailing,
  });
  final Duration delay;
  final Color color;
  final IconData icon;
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: PopIn(
      delay: delay,
      from: 0.85,
      child: TapCard(
        selected: true,
        color: color,
        child: Row(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.titleSmall)),
            if (trailing != null)
              Text(
                trailing!,
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
          ],
        ),
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.icon, this.color, this.delay, this.value);
  final String label;
  final IconData icon;
  final Color color;
  final Duration delay;
  final Widget value;

  static TextStyle get valueStyle => TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Brand.ink);

  @override
  Widget build(BuildContext context) => Expanded(
    child: PopIn(delay: delay, child: context.isKid ? _kid() : _adult(context)),
  );

  Widget _adult(BuildContext context) => TapCard(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                sentenceCase(label),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Brand.muted, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        value,
      ],
    ),
  );

  Widget _kid() => Container(
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
    padding: const EdgeInsets.fromLTRB(2, 6, 2, 2),
    child: Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(13)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 4),
              value,
            ],
          ),
        ),
      ],
    ),
  );
}
