import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../study/learning_evidence.dart';
import '../study/real_progress.dart';
import '../study/study_state.dart';
import '../theme.dart';

/// "Gerçek ilerleme" in Profil: learning, shown apart from XP. Built only
/// from honest signals (lib/study/real_progress.dart); no percentages.
class RealProgressSection extends ConsumerWidget {
  const RealProgressSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final r = realProgress(
      ref.watch(learningEvidenceProvider),
      ref.watch(studyLogProvider),
      ref.watch(clockProvider)(),
    );
    final turnaround = turnaroundSentence(r.turnaround);
    return Column(
      key: const Key('real-progress'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Gerçek ilerleme', style: t.titleLarge),
        const SizedBox(height: 4),
        Text(
          'XP ne kadar çalıştığını gösterir; burası ne kadar öğrendiğini. '
          'Sadece gerçek cevaplarından sayılır, tahmin yok.',
          style: TextStyle(color: Brand.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TapCard(
          child: r.isEmpty
              ? Text(
                  'Henüz gösterecek bir şey yok. Bir kelimeyi ertesi gün tekrarda bildiğinde '
                  've karıştırdığın bir soruyu sonraki bir gün doğru yaptığında burada görünür.',
                  key: const Key('real-progress-empty'),
                  style: TextStyle(color: Brand.muted),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Row(
                      key: const Key('real-words'),
                      icon: Icons.style_rounded,
                      color: Brand.success,
                      title:
                          '${r.wordsPassed} kelime aralıklı tekrarı geçti'
                          '${r.wordsPassedThisWeek > 0 ? ' (bu hafta +${r.wordsPassedThisWeek})' : ''}',
                      detail: 'Görmek sayılmaz: en az bir gün sonra sorulduğunda bildiğin kelimeler.',
                    ),
                    if (turnaround != null)
                      _Row(
                        key: const Key('real-turnaround'),
                        icon: Icons.replay_rounded,
                        color: Brand.primary,
                        title: turnaround,
                      ),
                    _Row(
                      key: const Key('real-cleared'),
                      icon: Icons.task_alt_rounded,
                      color: Brand.accent,
                      title: '${r.mistakesCleared} soru hata defterinden çıktı',
                      detail: 'Farklı günlerde art arda doğru yaptığın sorular.',
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.icon, required this.color, required this.title, this.detail});
  final IconData icon;
  final Color color;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
              if (detail case final d?) Text(d, style: TextStyle(color: Brand.muted, fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );
}
