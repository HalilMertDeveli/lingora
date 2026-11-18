import 'package:flutter/material.dart';

import '../models/course.dart';
import '../theme.dart';
import '../ui/guide_view.dart';
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
    final guide = unit.guide ?? '';
    return Scaffold(
      appBar: AppBar(title: Text('Ünite $index · Konu anlatımı')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                key: const Key('topic-guide'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  GuideHeader(unit: unit, index: index),
                  const SizedBox(height: 14),
                  GuideView(guide, color: color),
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

/// Coloured banner above a guide: unit number, title, description and
/// "n bölüm · ~m dk".
class GuideHeader extends StatelessWidget {
  const GuideHeader({super.key, required this.unit, required this.index, this.label = 'KONU ANLATIMI'});
  final Unit unit;
  final int index;
  final String label;

  @override
  Widget build(BuildContext context) {
    final l = context.lingora;
    final guide = unit.guide ?? '';
    final sections = guideSections(guide).where((s) => s.title.isNotEmpty).length;
    const white = Colors.white;
    Widget pill(IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: white),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(color: white, fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
        ],
      ),
    );
    return Container(
      key: const Key('guide-header'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: l.hero(unit.color, from: Color.lerp(unit.color, Colors.white, 0.25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ÜNİTE $index · $label',
            style: TextStyle(
              color: white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            unit.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: white, height: 1.2),
          ),
          if (unit.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(unit.description, style: TextStyle(color: white.withValues(alpha: 0.92), height: 1.4)),
          ],
          if (guide.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (sections > 0) pill(Icons.view_agenda_rounded, '$sections bölüm'),
                pill(Icons.schedule_rounded, '~${guideMinutes(guide)} dk okuma'),
              ],
            ),
          ],
        ],
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
