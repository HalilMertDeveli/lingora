import 'package:flutter/material.dart';

import '../data/progress.dart';
import '../theme.dart';

class LessonResultScreen extends StatelessWidget {
  const LessonResultScreen({
    super.key,
    required this.reward,
    required this.accuracy,
    required this.duration,
    required this.perfect,
  });

  final LessonReward reward;
  final int accuracy;
  final Duration duration;
  final bool perfect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mm = duration.inMinutes.toString();
    final ss = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final goalDone = reward.todayXp >= reward.dailyGoal;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Spacer(),
              Text(perfect ? '🏆' : '🎉', style: const TextStyle(fontSize: 96)),
              const SizedBox(height: 12),
              Text(perfect ? 'Kusursuz ders!' : 'Ders tamamlandı!', style: t.headlineSmall),
              const SizedBox(height: 28),
              Row(
                children: [
                  _Tile('XP', '+${reward.xp}', Icons.bolt, Brand.xp),
                  const SizedBox(width: 10),
                  _Tile('Doğruluk', '%$accuracy', Icons.track_changes, Brand.success),
                  const SizedBox(width: 10),
                  _Tile('Süre', '$mm:$ss', Icons.timer_outlined, Brand.primary),
                ],
              ),
              const SizedBox(height: 16),
              if (reward.streakExtended)
                TapCard(
                  selected: true,
                  color: Brand.streak,
                  child: Row(
                    children: [
                      const Icon(Icons.local_fire_department, color: Brand.streak, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          reward.streak == 1
                              ? 'Seri başladı! Yarın da gel.'
                              : '${reward.streak} günlük seri!',
                          style: t.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              for (final q in reward.questsCompleted)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TapCard(
                    selected: true,
                    color: Brand.success,
                    child: Row(
                      children: [
                        const Icon(Icons.task_alt, color: Brand.success, size: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Görev tamamlandı: ${q.title}',
                              style: Theme.of(context).textTheme.titleSmall),
                        ),
                        const Text('Ödül hazır',
                            style: TextStyle(color: Brand.success, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                goalDone
                    ? 'Günlük hedef tamam: ${reward.todayXp} / ${reward.dailyGoal} XP'
                    : 'Günlük hedef: ${reward.todayXp} / ${reward.dailyGoal} XP',
                style: TextStyle(color: goalDone ? Brand.success : Brand.muted, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('DEVAM'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 4),
                  Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
        ),
      );
}
