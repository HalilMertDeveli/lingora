import 'package:flutter/material.dart';

import '../data/mistake_nudge.dart';
import '../data/practice.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import 'lesson_screen.dart';

/// The notebook review of [items] (same as "Vadesi gelenleri çöz"): right
/// answers move a question to its next interval, wrong ones start it again.
Widget mistakeReviewScreen(List<LessonItem> items) => LessonScreen(
  nodeId: 'practice',
  title: 'Hatalarını çalış',
  items: items,
  color: Brand.error,
  mode: LessonMode.practice,
);

/// "Bunlar senin hataların": after a lesson, at most once a day, the
/// notebook questions whose review day has come, with a way to solve them
/// right away. "Sonra" moves on; nothing is lost, they wait in "Hatalarını çalış".
class MistakeNudgeScreen extends StatelessWidget {
  const MistakeNudgeScreen({super.key, required this.items, required this.onSolve, this.onLater});

  /// Due notebook questions, most recent first.
  final List<LessonItem> items;
  final VoidCallback onSolve;
  final VoidCallback? onLater;

  /// A short line naming the question, or null when it has no text.
  static String? lineOf(LessonItem item) {
    final ex = item.ex;
    for (final s in [ex.question, ex.text, ex.prompt, ex.translation]) {
      final t = s?.trim() ?? '';
      if (t.isNotEmpty) return t.length > 60 ? '${t.substring(0, 57)}...' : t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final lines = [for (final it in items) ?lineOf(it)].take(mistakeNudgePreview).toList();
    final n = items.length;
    return Scaffold(
      key: const Key('mistake-nudge'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Spacer(),
              Pofuduk(mood: Mood.calm, size: Brand.isKid ? 150 : 120),
              const SizedBox(height: 12),
              Text(
                'Bunlar senin hataların',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                n == 1
                    ? 'Birkaç kez takıldığın bir soru tekrar zamanına geldi. Şimdi çözelim mi?'
                    : 'Birkaç kez takıldığın $n soru tekrar zamanına geldi. Şimdi çözelim mi?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Brand.muted, fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 16),
              for (final line in lines)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Brand.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.replay_rounded, size: 18, color: Brand.error),
                      const SizedBox(width: 10),
                      Expanded(child: Text(line, maxLines: 2, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              const Spacer(),
              PressableButton(key: const Key('mistake-nudge-solve'), label: 'ÇÖZELİM', onPressed: onSolve),
              const SizedBox(height: 12),
              PressableButton(
                key: const Key('mistake-nudge-later'),
                label: 'SONRA',
                outlined: true,
                onPressed: onLater ?? () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
