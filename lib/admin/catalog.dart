import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/catalog.dart';
import '../data/course_repository.dart';
import '../models/course.dart';
import '../org/org.dart';

/// Something a teacher can assign, read from the same assets as the app.
class AssignTarget {
  const AssignTarget({
    required this.kind,
    required this.targetId,
    required this.title,
    required this.group,
    this.courseId = '',
  });

  final AssignmentKind kind;
  final String targetId;
  final String courseId;
  final String title;

  /// Heading in the picker, e.g. "Turizm İngilizcesi · Resepsiyon".
  final String group;
}

/// Lessons and stories of every course, grammar-path lessons and mock exams.
Future<List<AssignTarget>> loadAssignTargets(AssetBundle bundle) async {
  final out = <AssignTarget>[];
  for (final track in courseCatalog) {
    final course = await loadCourse(bundle, track.id);
    for (final unit in course.units) {
      for (final node in unit.nodes) {
        if (node.type != NodeType.lesson && node.type != NodeType.story) continue;
        out.add(
          AssignTarget(
            kind: AssignmentKind.lesson,
            targetId: node.id,
            courseId: track.id,
            title: node.title,
            group: '${track.title} · ${unit.title}',
          ),
        );
      }
    }
  }
  final lessons = jsonDecode(await bundle.loadString('assets/notes/lessons.json')) as List;
  for (final l in lessons.cast<Map<String, dynamic>>()) {
    out.add(
      AssignTarget(
        kind: AssignmentKind.grammar,
        targetId: l['id'] as String,
        title: '${l['title']}',
        group: 'Gramer yolu · ${l['level']}',
      ),
    );
  }
  for (final e in examCatalog) {
    out.add(
      AssignTarget(
        kind: AssignmentKind.exam,
        targetId: e.id,
        title: '${e.title} mini deneme',
        group: 'Sınav denemeleri',
      ),
    );
  }
  return out;
}
