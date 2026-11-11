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

/// Questions of a section mock: the section's `choice` exercises, taken in
/// turns from every unit so each topic is asked, then topped up from the
/// question bank [bank] when the section has too few.
List<ExamQuestion> mockQuestions(Section section, PathNode mock, {Exam? bank, Random? random}) {
  final r = random ?? Random();
  final size = mock.size > 0 ? mock.size : defaultMockSize;
  final pools = [
    for (final unit in section.units)
      [
        for (final lesson in unit.nodes.where((n) => n.type == NodeType.lesson))
          for (final item in lessonItems(lesson))
            if (item.ex.type == ExerciseType.choice && item.ex.options.length >= 2) examQuestionOf(item),
      ]..shuffle(r),
  ];
  final picked = <ExamQuestion>[];
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
