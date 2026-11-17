import 'dart:math';

import '../models/course.dart';
import 'practice.dart';
import 'progress.dart';
import 'sections.dart';

/// "Atlama sınavı": a learner who already knows a unit or a whole section
/// proves it in one exam and moves on.
///
/// The exam has [skipHearts] hearts: every wrong answer takes one, and the
/// question comes back near the end, so the exam is passed only when every
/// question was answered right. It ends when the hearts run out. Hearts
/// exist only here; normal lessons never have them. Passing counts every
/// step of the unit (or section) as done; running out of hearts changes
/// nothing on the path.
const skipHearts = 3;

/// Questions in a unit skip exam (more than a lesson has); more when the
/// unit's learning goals need them (see [coveringItems]).
const unitSkipTarget = 24;

/// Fewest questions per unit in a section skip exam.
const sectionSkipPerUnit = 5;

/// XP for passing a unit / section skip exam.
const unitSkipXp = 15;
const sectionSkipXp = 30;

/// Fewest questions a skip exam may have; smaller units are not offered one.
const skipMinQuestions = 6;

const _unitPrefix = 'unit_skip_';

/// Progress key (and answer-log node) of the "Bu üniteyi atla" exam of [unit].
String unitSkipId(Unit unit) => '$_unitPrefix${unit.id}';

/// Questions of the unit skip exam: every learning goal of [unit] (see
/// [skipObjectives]) at least once, filled up with mixed question types to
/// [unitSkipTarget], more than a lesson has.
List<LessonItem> unitSkipItems(Unit unit, [Random? random]) =>
    coveringItems(skipLessons(unit), target: unitSkipTarget, random: random);

/// Questions of the section skip exam: [unitSkipItems]-style coverage of
/// every unit, at least [sectionSkipPerUnit] questions from each.
List<LessonItem> sectionSkipQuestions(Section section, [Random? random]) {
  final r = random ?? Random();
  return [
    for (final unit in section.units)
      ...coveringItems(skipLessons(unit), target: sectionSkipPerUnit, random: r),
  ]..shuffle(r);
}

/// Steps of [unit] whose questions a skip exam draws on: its lessons and a
/// unit test with its own questions (exam paths).
List<PathNode> skipLessons(Unit unit) => [
  for (final n in unit.nodes)
    if ((n.type == NodeType.lesson || n.type == NodeType.test) &&
        n.exercises.any((e) => !ungradedTypes.contains(e.type)))
      n,
];

/// A learning goal of a unit: a lesson (its grammar point or pattern) or a
/// key word / phrase from a lesson's description ("hello, good morning").
typedef SkipObjective = ({String id, bool Function(LessonItem) coveredBy});

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r"[’']"), "'").replaceAll(RegExp(r'\s+'), ' ').trim();

/// The text an exercise teaches (its answers and sentence), not its wrong
/// options.
String exerciseText(Exercise e) => _norm(
  [
    e.prompt,
    e.text,
    e.translation,
    e.question,
    e.answer,
    ...e.answers,
    for (final (a, b) in e.pairs) '$a $b',
    if (e.type == ExerciseType.choice) e.displayAnswer,
  ].whereType<String>().join(' | '),
);

/// Key words of [lesson]: the comma-separated parts of its description.
List<String> lessonKeywords(PathNode lesson) => [
  for (final part in lesson.description.split(RegExp(r'[,;/]')))
    if (_norm(part).length >= 2) _norm(part),
];

/// The learning goals of [lessons]: each lesson, and each of its key words
/// that some question of [lessons] asks about (a description written as a
/// sentence, e.g. "present simple ile günlük rutin", has no askable words;
/// its lesson goal covers it).
List<SkipObjective> skipObjectives(List<PathNode> lessons) {
  final items = [for (final l in lessons) ..._graded(l)];
  final texts = {for (final it in items) it.key: exerciseText(it.ex)};
  // Whole words only: "is" is not in "this".
  final patterns = <String, RegExp>{};
  bool mentions(LessonItem it, String word) => patterns
      .putIfAbsent(word, () => RegExp('(^|[^a-zçğıöşü0-9])${RegExp.escape(word)}(\$|[^a-zçğıöşü0-9])'))
      .hasMatch(texts[it.key] ?? exerciseText(it.ex));
  return [
    for (final l in lessons) ...[
      (id: 'lesson:${l.id}', coveredBy: (LessonItem it) => it.key.startsWith('${l.id}#')),
      for (final word in lessonKeywords(l))
        if (items.any((it) => mentions(it, word)))
          (id: 'word:${l.id}:$word', coveredBy: (LessonItem it) => mentions(it, word)),
    ],
  ];
}

List<LessonItem> _graded(PathNode n) => [
  for (final it in lessonItems(n))
    if (!ungradedTypes.contains(it.ex.type)) it,
];

/// Picks questions from [lessons] so that every [skipObjectives] goal is
/// asked at least once (greedy set cover: the question covering most open
/// goals first, a new question type on ties), then fills up to [target]
/// round-robin over the lessons, preferring types used least so far.
List<LessonItem> coveringItems(List<PathNode> lessons, {required int target, Random? random}) {
  final r = random ?? Random();
  final pool = [for (final l in lessons) ..._graded(l)]..shuffle(r);
  final open = skipObjectives(lessons);
  final picked = <LessonItem>[];
  final types = <ExerciseType, int>{};
  void take(LessonItem it) {
    picked.add(it);
    pool.remove(it);
    types[it.ex.type] = (types[it.ex.type] ?? 0) + 1;
  }

  while (open.isNotEmpty && pool.isNotEmpty) {
    LessonItem? best;
    var bestScore = 0;
    for (final it in pool) {
      final covers = open.where((o) => o.coveredBy(it)).length;
      if (covers == 0) continue;
      final score = covers * 10 - (types[it.ex.type] ?? 0);
      if (best == null || score > bestScore) (best, bestScore) = (it, score);
    }
    if (best == null) break;
    final chosen = best;
    take(chosen);
    open.removeWhere((o) => o.coveredBy(chosen));
  }
  // Fill up: one lesson at a time, the least used question type first.
  final byLesson = [for (final l in lessons) pool.where((it) => it.key.startsWith('${l.id}#')).toList()];
  var added = true;
  while (picked.length < target && added) {
    added = false;
    for (final from in byLesson) {
      if (picked.length >= target || from.isEmpty) continue;
      from.sort((a, b) => (types[a.ex.type] ?? 0).compareTo(types[b.ex.type] ?? 0));
      take(from.removeAt(0));
      added = true;
    }
  }
  return picked..shuffle(r);
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
