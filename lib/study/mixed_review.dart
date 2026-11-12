import 'dart:math';

import '../data/practice.dart';
import '../data/progress.dart';
import '../models/course.dart';

/// Questions in a mixed review set.
const mixedSetSize = 12;

/// Exercise types a mixed set leaves out: speaking can be skipped and a
/// match drill is a vocabulary game, not a question.
const _skipTypes = {ExerciseType.speak, ExerciseType.match};

/// Units the learner has finished: their test is passed (or, for a unit
/// without one, every lesson is done).
List<Unit> finishedUnits(Course course, Progress p) => [
  for (final u in course.units)
    if (_finished(u, p)) u,
];

bool _finished(Unit u, Progress p) {
  final tests = u.nodes.where((n) => n.type == NodeType.test);
  if (tests.isNotEmpty) return tests.every((t) => p.isDone(t.id));
  final lessons = u.nodes.where((n) => n.type == NodeType.lesson);
  return lessons.isNotEmpty && lessons.every((l) => p.isDone(l.id));
}

/// A mixed (interleaved) set: questions from several finished units, never
/// two in a row from the same unit, so each question first asks "which
/// topic is this?". Units come from the whole finished path, older ones
/// as often as recent ones. Before two units are finished, the units with
/// finished lessons are used.
///
/// [only] keeps the items it accepts (e.g. one question type).
List<LessonItem> mixedSet(
  Course course,
  Progress p, {
  int size = mixedSetSize,
  Random? random,
  bool Function(Unit unit, LessonItem item)? only,
}) {
  final r = random ?? Random();
  var units = finishedUnits(course, p);
  if (units.length < 2) {
    units = [
      for (final u in course.units)
        if (u.nodes.any((n) => n.type == NodeType.lesson && p.isDone(n.id))) u,
    ];
  }
  final pools = <List<LessonItem>>[];
  for (final u in units) {
    final pool = [
      for (final n in u.nodes)
        if ((n.type == NodeType.lesson || n.type == NodeType.test) && p.isDone(n.id))
          for (final it in lessonItems(n))
            if (!_skipTypes.contains(it.ex.type) && (only == null || only(u, it))) it,
    ]..shuffle(r);
    if (pool.isNotEmpty) pools.add(pool);
  }
  pools.shuffle(r);
  final picked = <LessonItem>[];
  for (var round = 0; picked.length < size; round++) {
    var added = false;
    for (final pool in pools) {
      if (round < pool.length && picked.length < size) {
        picked.add(pool[round]);
        added = true;
      }
    }
    if (!added) break;
  }
  return picked;
}
