import 'dart:math';

import '../models/course.dart';
import 'progress.dart';

/// An exercise plus a stable key ("nodeId#index") used to remember mistakes.
typedef LessonItem = ({String key, Exercise ex});

enum LessonMode {
  /// Normal lesson: wrong answers come back at the end. No hearts, no penalty.
  lesson,

  /// Unit test: no second chances, pass with [testPassPercent].
  test,

  /// Mistakes review: a correct answer clears the mistake.
  practice,
}

const testPassPercent = 80;
const testSize = 12;
const practiceSize = 10;
const practiceXp = 10;

String itemKey(String nodeId, int index) => '$nodeId#$index';

List<LessonItem> lessonItems(PathNode node) => [
  for (var i = 0; i < node.exercises.length; i++) (key: itemKey(node.id, i), ex: node.exercises[i]),
];

/// Mixed questions from every lesson of [unit]. Speaking is left out because
/// it can be skipped, which would make the score meaningless.
List<LessonItem> unitTestItems(Unit unit, [Random? random]) {
  final r = random ?? Random();
  final lessons = unit.nodes.where((n) => n.type == NodeType.lesson).toList();
  if (lessons.isEmpty) return const [];
  final pools = [
    for (final l in lessons)
      lessonItems(l).where((it) => !ungradedTypes.contains(it.ex.type)).toList()..shuffle(r),
  ];
  final picked = <LessonItem>[];
  // Round-robin so every lesson is represented.
  for (var round = 0; picked.length < testSize; round++) {
    var added = false;
    for (final pool in pools) {
      if (round < pool.length && picked.length < testSize) {
        picked.add(pool[round]);
        added = true;
      }
    }
    if (!added) break;
  }
  return picked..shuffle(r);
}

/// Questions of a unit test node: its own questions when it has them (exam
/// paths: a fixed mini exam in the real format), else [unitTestItems].
List<LessonItem> testItems(Unit unit, PathNode test, [Random? random]) =>
    test.exercises.isNotEmpty ? lessonItems(test) : unitTestItems(unit, random);

/// Resolves saved mistake keys, most recent first, at most [limit].
List<LessonItem> mistakeItems(Course course, List<String> keys, {int limit = practiceSize}) {
  final byId = {for (final n in course.allNodes) n.id: n};
  final items = <LessonItem>[];
  for (final key in keys.reversed) {
    final hash = key.lastIndexOf('#');
    if (hash < 0) continue;
    final node = byId[key.substring(0, hash)];
    final i = int.tryParse(key.substring(hash + 1));
    if (node == null || i == null || i >= node.exercises.length) continue;
    items.add((key: key, ex: node.exercises[i]));
    if (items.length == limit) break;
  }
  return items;
}

/// Word pairs (Turkish, English) the user has met: from match exercises in
/// finished lessons, or the first unit when nothing is finished yet.
List<(String, String)> vocabularyPool(Course course, Progress p) {
  List<(String, String)> collect(Iterable<PathNode> nodes) {
    final seen = <String>{};
    return [
      for (final n in nodes)
        for (final ex in n.exercises)
          if (ex.type == ExerciseType.match)
            for (final pair in ex.pairs)
              if (seen.add(pair.$2.toLowerCase())) pair,
    ];
  }

  final done = course.allNodes.where((n) => n.type == NodeType.lesson && p.isDone(n.id));
  final pool = collect(done);
  return pool.length >= 5 ? pool : collect(course.units.first.nodes);
}
