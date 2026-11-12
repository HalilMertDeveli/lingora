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

/// Progress key opening [section] early. General-course sections ("s3") use
/// [sectionPassId]; other paths' sections ("ys2") get their own key, so the
/// general course's "Bölüm 5" never opens an exam path's section 5.
String sectionPassKey(Section section) =>
    section.id == 's${section.index}' ? sectionPassId(section.index) : 'section_${section.id}';

/// Whether the shared "section_sN" keys apply to [course]: only to paths
/// whose sections are named "s1", "s2"... (the general course).
bool _sharedPassKeys(Course course) => course.sections.every((s) => s.implicit || s.id == 's${s.index}');

/// Main-path sections (not [Section.parallel]) in path order.
List<Section> mainSections(Course course) => course.sections.where((s) => !s.parallel).toList();

/// Position in [mainSections] up to which the learner may enter.
int _reachPos(Course course, Progress p) {
  final main = mainSections(course);
  var reach = 0;
  // "section_sN" opens every section numbered up to N, even one that ships
  // later. Exam paths have their own keys; before they had, "Bölüme atla"
  // wrote the shared key there too, so it still counts for a learner who
  // has started the exam path (never for one who has not).
  if (_sharedPassKeys(course) || course.allNodes.any((n) => p.isDone(n.id))) {
    var upTo = -1;
    for (final key in p.completed.keys) {
      final m = _passKey.firstMatch(key);
      if (m != null && p.isDone(key)) upTo = max(upTo, int.parse(m.group(1)!));
    }
    for (var i = 0; i < main.length; i++) {
      if (main[i].index <= upTo) reach = max(reach, i);
    }
  }
  if (!_sharedPassKeys(course)) {
    for (var i = 0; i < main.length; i++) {
      if (p.isDone(sectionPassKey(main[i]))) reach = max(reach, i);
    }
  }
  // A section with any finished step stays open, whatever opened it before
  // (e.g. an exam path opened by an old shared "section_sN" key).
  for (var i = 0; i < main.length; i++) {
    if (main[i].nodes.any((n) => p.isDone(n.id))) reach = max(reach, i);
  }
  // Passing a section's exam opens the next one.
  for (var i = 0; i + 1 < main.length; i++) {
    final exam = main[i].exam;
    if (exam != null && p.isDone(exam.id)) reach = max(reach, i + 1);
  }
  return reach;
}

/// Index of the furthest main section the learner may enter.
int sectionReach(Course course, Progress p) {
  final main = mainSections(course);
  return main.isEmpty ? 0 : main[_reachPos(course, p)].index;
}

/// Whether [section] is open: a side path ([Section.parallel]) always is; a
/// main section once the one before it is passed (the first one from the
/// start), or by "Bölüme atla" / the placement test.
bool sectionOpen(Course course, Section section, Progress p) {
  if (section.parallel) return true;
  final pos = mainSections(course).indexOf(section);
  return pos >= 0 && pos <= _reachPos(course, p);
}

/// Share of finished nodes in [section], 0–1.
double sectionProgress(Section section, Progress p) {
  final nodes = section.nodes;
  if (nodes.isEmpty) return 0;
  return nodes.where((n) => p.isDone(n.id)).length / nodes.length;
}

/// Next node to play in each open section, by section id. Mock exams never
/// hold the path up (see [mockOpen]).
Map<String, PathNode> activeNodes(Course course, Progress p) => {
  for (final s in course.sections)
    if (sectionOpen(course, s, p))
      s.id: ?s.nodes.where((n) => n.type != NodeType.mock && !p.isDone(n.id)).firstOrNull,
};

/// Whether mock exam [mock] can be taken: its section is open and every step
/// before it in the section is finished. Mocks are extra practice, so the
/// steps after them open without them.
bool mockOpen(Course course, PathNode mock, Progress p) {
  for (final s in course.sections) {
    final i = s.nodes.indexOf(mock);
    if (i < 0) continue;
    return sectionOpen(course, s, p) &&
        s.nodes.take(i).every((n) => n.type == NodeType.mock || p.isDone(n.id));
  }
  return false;
}

/// The node the path focuses on ("Bulunduğun yere dön"): the next node of the
/// furthest open main section that is not finished yet; side paths
/// ([Section.parallel]) only once the main path is done.
PathNode? currentNode(Course course, Progress p) {
  final active = activeNodes(course, p);
  for (final parallel in [false, true]) {
    for (final s in course.sections.reversed.where((s) => s.parallel == parallel)) {
      if (active[s.id] case final n?) return n;
    }
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
