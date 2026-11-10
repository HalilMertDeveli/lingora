// "Gramer Yolu": guided lessons built on top of the user's grammar notes.

/// Colour role of a formula chip.
enum PartRole {
  subject, // özne
  aux, // yardımcı fiil
  verb, // ana fiil
  object, // nesne / tümleç
  negative, // not
  question, // soru kelimesi
  other,
}

class FormulaPart {
  const FormulaPart(this.text, this.role);
  final String text;
  final PartRole role;

  static PartRole _role(String r) => switch (r) {
    's' => PartRole.subject,
    'aux' => PartRole.aux,
    'v' => PartRole.verb,
    'o' => PartRole.object,
    'neg' => PartRole.negative,
    'q' => PartRole.question,
    _ => PartRole.other,
  };

  factory FormulaPart.fromJson(List<dynamic> j) => FormulaPart(j[0] as String, _role(j[1] as String));
}

class Formula {
  const Formula({required this.label, required this.parts, this.example});
  final String label;
  final List<FormulaPart> parts;
  final String? example;

  factory Formula.fromJson(Map<String, dynamic> j) => Formula(
    label: j['label'] as String,
    parts: (j['parts'] as List).map((p) => FormulaPart.fromJson(p as List)).toList(),
    example: j['example'] as String?,
  );
}

/// Where the action sits on the past–now–future line.
enum TimelineKind {
  pastPoint,
  pastSpan,
  now,
  habit,
  pastToNow,
  beforePast,
  futurePoint,
  futureSpan,
  beforeFuture,
}

class Mistake {
  const Mistake({required this.wrong, required this.right, required this.why});
  final String wrong;
  final String right;
  final String why;

  factory Mistake.fromJson(Map<String, dynamic> j) =>
      Mistake(wrong: j['wrong'] as String, right: j['right'] as String, why: j['why'] as String);
}

class QuizQuestion {
  const QuizQuestion({required this.q, required this.options, required this.answer, required this.why});
  final String q;
  final List<String> options;
  final int answer;
  final String why;

  factory QuizQuestion.fromJson(Map<String, dynamic> j) => QuizQuestion(
    q: j['q'] as String,
    options: (j['options'] as List).cast<String>(),
    answer: j['answer'] as int,
    why: j['why'] as String,
  );
}

class GrammarLesson {
  const GrammarLesson({
    required this.id,
    required this.unit,
    required this.level,
    required this.title,
    required this.emoji,
    required this.summary,
    required this.formulas,
    required this.compare,
    required this.mistakes,
    required this.quiz,
    required this.noteIds,
    this.timeline,
    this.timelineNote,
    this.tip,
  });

  final String id;

  /// Path section, e.g. "A1 · Temeller".
  final String unit;
  final String level;
  final String title;
  final String emoji;

  /// What the topic is for, in one or two Turkish sentences.
  final String summary;
  final List<Formula> formulas;
  final TimelineKind? timeline;
  final String? timelineNote;

  /// How Turkish says it versus English.
  final String compare;
  final List<Mistake> mistakes;

  /// Memory trick.
  final String? tip;
  final List<QuizQuestion> quiz;

  /// The user's own note topics this lesson builds on.
  final List<String> noteIds;

  factory GrammarLesson.fromJson(Map<String, dynamic> j) => GrammarLesson(
    id: j['id'] as String,
    unit: j['unit'] as String,
    level: j['level'] as String,
    title: j['title'] as String,
    emoji: (j['emoji'] as String?) ?? '📘',
    summary: j['summary'] as String,
    formulas: ((j['formulas'] as List?) ?? const [])
        .map((f) => Formula.fromJson(f as Map<String, dynamic>))
        .toList(),
    timeline: j['timeline'] == null ? null : TimelineKind.values.byName(j['timeline'] as String),
    timelineNote: j['timelineNote'] as String?,
    compare: j['compare'] as String,
    mistakes: ((j['mistakes'] as List?) ?? const [])
        .map((m) => Mistake.fromJson(m as Map<String, dynamic>))
        .toList(),
    tip: j['tip'] as String?,
    quiz: ((j['quiz'] as List?) ?? const [])
        .map((q) => QuizQuestion.fromJson(q as Map<String, dynamic>))
        .toList(),
    noteIds: ((j['noteIds'] as List?) ?? const []).cast<String>(),
  );
}
