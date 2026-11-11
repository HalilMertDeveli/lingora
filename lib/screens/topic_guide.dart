import 'package:flutter/material.dart';

import '../models/course.dart';
import '../theme.dart';
import '../ui/markdown_text.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';

/// A unit's topic explanation as a page (exam paths). With [startLabel] a
/// button at the bottom closes it with `true` ("Derse başla").
class TopicGuideScreen extends StatelessWidget {
  const TopicGuideScreen({super.key, required this.unit, required this.index, this.startLabel});
  final Unit unit;

  /// Unit number in its section.
  final int index;
  final String? startLabel;

  @override
  Widget build(BuildContext context) {
    final color = Brand.tone(unit.color);
    return Scaffold(
      appBar: AppBar(title: Text('Ünite $index · Konu anlatımı')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                key: const Key('topic-guide'),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Text(unit.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color)),
                  if (unit.description.isNotEmpty)
                    Text(unit.description, style: TextStyle(color: Brand.muted, height: 1.4)),
                  MarkdownText(unit.guide ?? ''),
                ],
              ),
            ),
            if (startLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: PressableButton(
                  key: const Key('topic-guide-start'),
                  label: startLabel!,
                  color: color,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Answer to "Önce konuyu oku" before a unit's first lesson.
enum GuideChoice { read, skip }

/// Suggests reading the unit's topic guide before its first lesson. Returns
/// null when the dialog is dismissed without a choice.
Future<GuideChoice?> showGuideSuggestion(BuildContext context, Unit unit) => showDialog<GuideChoice>(
  context: context,
  builder: (c) => AlertDialog(
    key: const Key('guide-suggestion'),
    icon: const Mascot(mood: Mood.think, size: 72, decorative: true),
    title: const Text('Önce konuyu oku'),
    content: Text(
      '"${unit.title}" ünitesinin kısa konu anlatımı hazır. Kalıpları ve sınav ipuçlarını okuyup '
      'başlarsan sorular çok daha kolay gelir!',
    ),
    actions: [
      TextButton(
        key: const Key('guide-suggestion-skip'),
        onPressed: () => Navigator.pop(c, GuideChoice.skip),
        child: const Text('Atla, derse başla'),
      ),
      FilledButton(
        key: const Key('guide-suggestion-read'),
        onPressed: () => Navigator.pop(c, GuideChoice.read),
        child: const Text('Konuyu oku'),
      ),
    ],
  ),
);
