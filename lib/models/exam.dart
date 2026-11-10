/// Exam-style multiple choice question bank (YDS/YÖKDİL, LGS).
class ExamQuestion {
  const ExamQuestion({
    required this.id,
    required this.text,
    required this.options,
    required this.answer,
    required this.explanation,
    this.passage,
  });

  final String id;

  /// Optional reading text shown above the question.
  final String? passage;
  final String text;
  final List<String> options;

  /// Index of the correct option.
  final int answer;

  /// Turkish explanation shown after answering.
  final String explanation;

  factory ExamQuestion.fromJson(Map<String, dynamic> j) => ExamQuestion(
    id: j['id'] as String,
    passage: j['passage'] as String?,
    text: j['text'] as String,
    options: (j['options'] as List).cast<String>(),
    answer: j['answer'] as int,
    explanation: j['explanation'] as String,
  );
}

class ExamSection {
  const ExamSection({
    required this.id,
    required this.title,
    required this.description,
    required this.questions,
  });
  final String id;
  final String title;
  final String description;
  final List<ExamQuestion> questions;

  factory ExamSection.fromJson(Map<String, dynamic> j) => ExamSection(
    id: j['id'] as String,
    title: j['title'] as String,
    description: (j['description'] as String?) ?? '',
    questions: (j['questions'] as List).map((q) => ExamQuestion.fromJson(q as Map<String, dynamic>)).toList(),
  );
}

class Exam {
  const Exam({
    required this.id,
    required this.title,
    required this.description,
    required this.optionCount,
    required this.mockSize,
    required this.mockMinutes,
    required this.sections,
  });

  final String id;
  final String title;
  final String description;

  /// 5 for YDS/YÖKDİL (A–E), 4 for LGS (A–D).
  final int optionCount;

  /// Questions and time limit of a mini mock exam.
  final int mockSize;
  final int mockMinutes;
  final List<ExamSection> sections;

  List<ExamQuestion> get allQuestions => [for (final s in sections) ...s.questions];

  factory Exam.fromJson(Map<String, dynamic> j) => Exam(
    id: j['id'] as String,
    title: j['title'] as String,
    description: (j['description'] as String?) ?? '',
    optionCount: j['optionCount'] as int,
    mockSize: j['mockSize'] as int,
    mockMinutes: j['mockMinutes'] as int,
    sections: (j['sections'] as List).map((s) => ExamSection.fromJson(s as Map<String, dynamic>)).toList(),
  );
}
