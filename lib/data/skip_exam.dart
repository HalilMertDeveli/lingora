import 'dart:math';

import '../models/course.dart';
import 'practice.dart';
import 'progress.dart';
import 'sections.dart';

/// "Atlama sınavı": a learner who already knows a unit or a whole section
/// proves it in one exam and moves on.
///
/// The exam has [skipHearts] hearts: every wrong answer takes one, and the
/// exam ends when they run out. Hearts exist only here; normal lessons never
/// have them. Passing counts every step of the unit (or section) as done;
/// running out of hearts changes nothing on the path.
const skipHearts = 5;

/// XP for passing a unit / section skip exam.
const unitSkipXp = 15;
const sectionSkipXp = 30;

/// Fewest questions a skip exam may have; smaller units are not offered one.
const skipMinQuestions = 6;

const _unitPrefix = 'unit_skip_';

/// Progress key (and answer-log node) of the "Bu üniteyi atla" exam of [unit].
String unitSkipId(Unit unit) => '$_unitPrefix${unit.id}';

/// Questions of the unit skip exam: the unit test's own questions when it
/// has them (exam paths), else mixed questions from every lesson of the unit.
List<LessonItem> unitSkipItems(Unit unit, [Random? random]) {
  final test = unit.nodes.where((n) => n.type == NodeType.test && n.exercises.isNotEmpty).lastOrNull;
  return test != null ? lessonItems(test) : unitTestItems(unit, random);
}

/// Whether [unit] gets a "Bu üniteyi atla" exam: it has lessons and some of
/// its steps are not finished yet.
bool unitSkipOffered(Unit unit, Progress p) =>
    unit.nodes.any((n) => n.type == NodeType.lesson) &&
    unit.nodes.any((n) => n.type != NodeType.mock && !p.isDone(n.id));

/// Steps that passing the skip exam [examId] counts as finished in [course];
/// empty when [examId] is not a skip exam of it.
///
/// * Unit: the unit and every unit before it in its section (the learner
///   jumped past them), so the next unit opens.
/// * Section: every step of the section, its exam too, so the next section
///   opens.
///
/// Mock exams are optional practice and stay as they were.
List<String> skipExamNodes(Course course, String examId) {
  Iterable<PathNode> nodes = const [];
  if (examId.startsWith(_unitPrefix)) {
    final unitId = examId.substring(_unitPrefix.length);
    for (final s in course.sections) {
      final i = s.units.indexWhere((u) => u.id == unitId);
      if (i >= 0) nodes = s.units.take(i + 1).expand((u) => u.nodes);
    }
  } else {
    final section = course.sections.where((s) => sectionPassKey(s) == examId).firstOrNull;
    if (section != null) nodes = section.nodes;
  }
  return [
    for (final n in nodes)
      if (n.type != NodeType.mock) n.id,
  ];
}

/// Records a passed skip exam: its steps count as finished (no extra XP or
/// lesson counts, like the placement test). Returns how many were marked.
int applySkipPass(ProgressNotifier progress, Course course, String examId) {
  final ids = skipExamNodes(course, examId);
  if (ids.isNotEmpty) progress.markKnown(ids);
  return ids.length;
}

/// Whether [examId] is a unit skip exam ("Bu üniteyi atla").
bool isUnitSkipId(String examId) => examId.startsWith(_unitPrefix);

/// Whether every step of [section] that a skip exam would mark is done
/// already (nothing left to skip).
bool sectionSkipFinished(Section section, Progress p) =>
    section.nodes.where((n) => n.type != NodeType.mock).every((n) => p.isDone(n.id));
