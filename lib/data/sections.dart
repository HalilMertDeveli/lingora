import 'dart:math';

import '../models/course.dart';
import 'practice.dart';
import 'progress.dart';

/// Questions in a "Bölüme atla" exam.
const sectionSkipSize = 15;

/// Progress key recording that section [index] was opened early, by the
/// "Bölüme atla" exam or the placement test. It opens every section up to
/// [index], so a key for a section that is not shipped yet still works.
String sectionPassId(int index) => 'section_s$index';

final _passKey = RegExp(r'^section_s(\d+)$');

/// Highest section index the learner may enter.
int sectionReach(Course course, Progress p) {
  var reach = course.sections.isEmpty ? 0 : course.sections.first.index;
  for (final key in p.completed.keys) {
    final m = _passKey.firstMatch(key);
    if (m != null && p.isDone(key)) reach = max(reach, int.parse(m.group(1)!));
  }
  // Passing a section's exam opens the next one.
  for (var i = 0; i + 1 < course.sections.length; i++) {
    final exam = course.sections[i].exam;
    if (exam != null && p.isDone(exam.id)) reach = max(reach, course.sections[i + 1].index);
  }
  return reach;
}

/// Whether [section] is open: the first one always is; a later one opens once
/// the section before it is passed, or by "Bölüme atla" / the placement test.
bool sectionOpen(Course course, Section section, Progress p) =>
    section == course.sections.first || section.index <= sectionReach(course, p);

/// Share of finished nodes in [section], 0–1.
double sectionProgress(Section section, Progress p) {
  final nodes = section.nodes;
  if (nodes.isEmpty) return 0;
  return nodes.where((n) => p.isDone(n.id)).length / nodes.length;
}

/// Next node to play in each open section, by section id.
Map<String, PathNode> activeNodes(Course course, Progress p) => {
  for (final s in course.sections)
    if (sectionOpen(course, s, p)) s.id: ?s.nodes.where((n) => !p.isDone(n.id)).firstOrNull,
};

/// The node the path focuses on ("Bulunduğun yere dön"): the next node of the
/// furthest open section that is not finished yet.
PathNode? currentNode(Course course, Progress p) {
  final active = activeNodes(course, p);
  for (final s in course.sections.reversed) {
    if (active[s.id] case final n?) return n;
  }
  return null;
}

/// "Bölüme atla" questions: [sectionSkipSize] mixed unit-test questions from
/// every unit of [section], spread evenly over its lessons.
List<LessonItem> sectionSkipItems(Section section, [Random? random]) {
  final r = random ?? Random();
  final pools = [
    for (final unit in section.units)
      for (final l in unit.nodes.where((n) => n.type == NodeType.lesson))
        lessonItems(l).where((it) => it.ex.type != ExerciseType.speak).toList()..shuffle(r),
  ]..shuffle(r);
  final picked = <LessonItem>[];
  for (var round = 0; picked.length < sectionSkipSize; round++) {
    var added = false;
    for (final pool in pools) {
      if (round < pool.length && picked.length < sectionSkipSize) {
        picked.add(pool[round]);
        added = true;
      }
    }
    if (!added) break;
  }
  return picked..shuffle(r);
}
