import 'dart:math';

import '../models/course.dart';
import '../models/exam.dart';
import 'practice.dart';

/// Default question count and time of a section mock without its own.
const defaultMockSize = 20;
const defaultMockMinutes = 30;

/// An exam-style question built from a `choice` exercise; its id is the
/// exercise's item key ("nodeId#index").
ExamQuestion examQuestionOf(LessonItem item) => ExamQuestion(
  id: item.key,
  text: item.ex.question ?? '',
  passage: item.ex.passage,
  options: item.ex.options,
  answer: item.ex.answerIndex ?? 0,
  explanation: item.ex.explanation ?? '',
);

/// The section of [course] that holds [node].
Section? sectionOf(Course course, PathNode node) =>
    course.sections.where((s) => s.nodes.contains(node)).firstOrNull;

/// Units a mock covers: those of its section up to (and with) its own.
List<Unit> mockUnits(Section section, PathNode mock) {
  final i = section.units.indexWhere((u) => u.nodes.contains(mock));
  return i < 0 ? section.units : section.units.take(i + 1).toList();
}

/// Questions of a section mock, in turns from every unit it covers so each
/// topic is asked: first the units' mini exams (test nodes with their own
/// questions, already in the real format), then their lessons' `choice`
/// questions, then the question bank [bank].
List<ExamQuestion> mockQuestions(Section section, PathNode mock, {Exam? bank, Random? random}) {
  // A mock with its own questions (a fixed half mock) asks them in order.
  if (mock.exercises.isNotEmpty) {
    return [
      for (final item in lessonItems(mock))
        if (item.ex.type == ExerciseType.choice && item.ex.options.length >= 2) examQuestionOf(item),
    ];
  }
  final r = random ?? Random();
  final size = mock.size > 0 ? mock.size : defaultMockSize;
  final units = mockUnits(section, mock);
  List<ExamQuestion> choices(Iterable<PathNode> nodes) => [
    for (final n in nodes)
      for (final item in lessonItems(n))
        if (item.ex.type == ExerciseType.choice && item.ex.options.length >= 2) examQuestionOf(item),
  ]..shuffle(r);
  final picked = <ExamQuestion>[];
  void roundRobin(List<List<ExamQuestion>> pools) {
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
  }

  roundRobin([for (final u in units) choices(u.nodes.where((n) => n.type == NodeType.test))]);
  roundRobin([for (final u in units) choices(u.nodes.where((n) => n.type == NodeType.lesson))]);
  if (picked.length < size && bank != null) {
    final extra = [...bank.allQuestions]..shuffle(r);
    picked.addAll(extra.take(size - picked.length));
  }
  return picked..shuffle(r);
}

/// The exam the mock runs as: the bank's settings, or a plain one when the
/// bank cannot be read. [minutes] is the mock's time limit.
Exam mockExam(PathNode mock, Exam? bank, List<ExamQuestion> questions) {
  final options = questions.isEmpty ? 4 : questions.map((q) => q.options.length).reduce(max);
  return Exam(
    id: bank?.id ?? mock.examId ?? mock.id,
    title: mock.title,
    description: mock.description,
    optionCount: bank?.optionCount ?? options,
    mockSize: questions.length,
    mockMinutes: mock.minutes > 0 ? mock.minutes : defaultMockMinutes,
    sections: bank?.sections ?? const [],
  );
}

/// "Son deneme: %80 · 12:30" for a finished mock, or null.
String? mockSummary(String nodeId, Map<String, int> best, Map<String, int> seconds) {
  final b = best[nodeId];
  if (b == null) return null;
  final s = seconds[nodeId];
  final time = s == null ? '' : ' · son süre ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  return 'En iyi sonuç %$b$time';
}
