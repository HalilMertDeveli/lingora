import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/course_repository.dart';
import '../../data/progress.dart';
import '../../models/course.dart';
import '../../theme.dart';
import '../lesson_screen.dart';
import '../story_screen.dart';

/// YÖKDİL fields of reading texts.
const readingFields = {'fen': 'Fen', 'saglik': 'Sağlık', 'sosyal': 'Sosyal'};

/// Reading texts of the YDS path (Okuma evi): lessons and stories with a
/// `reading` field, with their unit.
List<(Unit, PathNode)> readingHouseTexts(Course course) => [
  for (final u in course.units)
    for (final n in u.nodes)
      if (n.reading != null && (n.type == NodeType.lesson || n.type == NodeType.story)) (u, n),
];

/// "Okuma evi" in the reading library: the YDS path's reading texts by
/// field, each opening its lesson. Hidden until the path has such texts.
class ReadingHouseSection extends ConsumerWidget {
  const ReadingHouseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(examPathProvider('yds')).value;
    if (course == null) return const SizedBox.shrink();
    final texts = readingHouseTexts(course);
    if (texts.isEmpty) return const SizedBox.shrink();
    final p = ref.watch(progressProvider);
    final t = Theme.of(context).textTheme;
    final done = texts.where((e) => p.isDone(e.$2.id)).length;
    return Column(
      key: const Key('reading-house'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Row(
            children: [
              Text('Okuma evi · YDS', style: t.titleLarge),
              const Spacer(),
              Text(
                '$done/${texts.length}',
                style: TextStyle(fontWeight: FontWeight.w900, color: Brand.primary),
              ),
            ],
          ),
        ),
        for (final (unit, node) in texts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TapCard(
              key: Key('house-${node.id}'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => node.type == NodeType.story
                      ? StoryScreen(node: node, color: Brand.tone(unit.color))
                      : LessonScreen.forNode(node, Brand.tone(unit.color)),
                ),
              ),
              child: Row(
                children: [
                  const Text('📰', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(node.title, style: t.titleMedium),
                        Text(
                          [
                            readingFields[node.reading!.field] ?? 'Genel',
                            if (node.reading!.cefr != null) node.reading!.cefr!,
                            if (node.reading!.words > 0) '${node.reading!.words} kelime',
                          ].join(' · '),
                          style: TextStyle(color: Brand.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (p.isDone(node.id))
                    Icon(Icons.check_circle_rounded, color: Brand.success)
                  else
                    Icon(Icons.chevron_right_rounded, color: Brand.muted),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
