import 'package:flutter/material.dart';

enum ExerciseType { select, translate, fillBlank, listen, match, speak, choice }

class Choice {
  const Choice(this.text, this.emoji);
  final String text;
  final String emoji;

  factory Choice.fromJson(Map<String, dynamic> j) =>
      Choice(j['text'] as String, (j['emoji'] as String?) ?? '');
}

class Exercise {
  const Exercise({
    required this.type,
    this.prompt,
    this.text,
    this.lang = 'en',
    this.translation,
    this.answer,
    this.answers = const [],
    this.tokens = const [],
    this.choices = const [],
    this.wordChoices = const [],
    this.pairs = const [],
    this.question,
    this.passage,
    this.options = const [],
    this.answerIndex,
    this.explanation,
  });

  final ExerciseType type;

  /// Word the user looks for (select).
  final String? prompt;

  /// Sentence shown, heard or spoken.
  final String? text;

  /// Language of [text]: 'tr' or 'en'.
  final String lang;
  final String? translation;

  /// Single correct choice (select, fillBlank).
  final String? answer;

  /// Accepted answers (translate, listen).
  final List<String> answers;

  /// Word bank (translate).
  final List<String> tokens;

  /// Picture cards (select).
  final List<Choice> choices;

  /// Plain word options (fillBlank).
  final List<String> wordChoices;

  /// [native, learning] pairs (match).
  final List<(String, String)> pairs;

  /// Exam-style multiple choice (choice): an optional reading text, the
  /// question, 4 (LGS) or 5 (YDS) options, the right option's index and a
  /// Turkish explanation shown after answering.
  final String? question;
  final String? passage;
  final List<String> options;
  final int? answerIndex;
  final String? explanation;

  /// The right option of a choice exercise.
  String get correctOption {
    final i = answerIndex;
    return i != null && i >= 0 && i < options.length ? options[i] : '';
  }

  /// Text shown to the user as the correct answer after a mistake.
  String get displayAnswer => switch (type) {
    ExerciseType.select || ExerciseType.fillBlank => answer ?? '',
    ExerciseType.translate || ExerciseType.listen => answers.first,
    ExerciseType.speak => text ?? '',
    ExerciseType.match => '',
    ExerciseType.choice => correctOption,
  };

  factory Exercise.fromJson(Map<String, dynamic> j) {
    final type = ExerciseType.values.byName(j['type'] as String);
    List<String> strings(String key) => ((j[key] as List?) ?? const []).cast<String>();
    final choice = type == ExerciseType.choice;
    return Exercise(
      type: type,
      prompt: j['prompt'] as String?,
      text: j['text'] as String?,
      lang: (j['lang'] as String?) ?? 'en',
      translation: j['translation'] as String?,
      answer: choice ? null : j['answer'] as String?,
      answers: strings('answers'),
      tokens: strings('tokens'),
      choices: type == ExerciseType.select
          ? ((j['choices'] as List?) ?? const [])
                .map((c) => Choice.fromJson(c as Map<String, dynamic>))
                .toList()
          : const [],
      wordChoices: type == ExerciseType.fillBlank ? strings('choices') : const [],
      pairs: ((j['pairs'] as List?) ?? const [])
          .map((p) => ((p as List)[0] as String, p[1] as String))
          .toList(),
      question: j['question'] as String?,
      passage: j['passage'] as String?,
      options: choice ? strings('options') : const [],
      answerIndex: choice ? j['answer'] as int? : null,
      explanation: j['explanation'] as String?,
    );
  }
}

/// Steps of a path. [mock] is a section's timed practice exam (exam paths):
/// it opens the exam engine with the section's questions.
enum NodeType { lesson, chest, story, test, mock }

/// One step of a story node: a line of dialogue or a comprehension question.
class StoryStep {
  const StoryStep.line({required this.speaker, required this.avatar, required this.text, this.translation})
    : prompt = null,
      choices = const [],
      answer = null;
  const StoryStep.question({required this.prompt, required this.choices, required this.answer})
    : speaker = null,
      avatar = null,
      text = null,
      translation = null;

  final String? speaker;
  final String? avatar;
  final String? text;
  final String? translation;
  final String? prompt;
  final List<String> choices;
  final String? answer;

  bool get isQuestion => prompt != null;

  factory StoryStep.fromJson(Map<String, dynamic> j) => j['kind'] == 'question'
      ? StoryStep.question(
          prompt: j['prompt'] as String,
          choices: (j['choices'] as List).cast<String>(),
          answer: j['answer'] as String,
        )
      : StoryStep.line(
          speaker: j['speaker'] as String,
          avatar: (j['avatar'] as String?) ?? '🙂',
          text: j['text'] as String,
          translation: j['translation'] as String?,
        );
}

class PathNode {
  const PathNode({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.exercises = const [],
    this.rewardXp = 0,
    this.steps = const [],
    this.examId,
    this.size = 0,
    this.minutes = 0,
  });

  final String id;
  final NodeType type;
  final String title;
  final String description;
  final List<Exercise> exercises;
  final int rewardXp;

  /// Dialogue and questions (story nodes).
  final List<StoryStep> steps;

  /// Mock nodes: the question bank that tops up the section's questions
  /// (`assets/exams/<examId>.json`), question count and time limit.
  final String? examId;
  final int size;
  final int minutes;

  factory PathNode.fromJson(Map<String, dynamic> j) => PathNode(
    id: j['id'] as String,
    type: NodeType.values.byName(j['type'] as String),
    title: j['title'] as String,
    description: (j['description'] as String?) ?? '',
    exercises: ((j['exercises'] as List?) ?? const [])
        .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
        .toList(),
    rewardXp: (j['rewardXp'] as int?) ?? 0,
    steps: ((j['steps'] as List?) ?? const [])
        .map((s) => StoryStep.fromJson(s as Map<String, dynamic>))
        .toList(),
    examId: j['examId'] as String?,
    size: (j['size'] as int?) ?? 0,
    minutes: (j['minutes'] as int?) ?? 0,
  );
}

class Unit {
  const Unit({
    required this.id,
    required this.title,
    required this.description,
    required this.color,
    required this.nodes,
    this.theme,
    this.guide,
  });

  final String id;
  final String title;
  final String description;
  final Color color;
  final List<PathNode> nodes;

  /// Turkish topic explanation in simple markdown (exam paths), shown by the
  /// unit's "Rehber" button and suggested once before its first lesson.
  final String? guide;

  bool get hasGuide => guide?.trim().isNotEmpty ?? false;

  /// Topic theme id (lib/data/topic_themes.dart); null uses the default.
  final String? theme;

  factory Unit.fromJson(Map<String, dynamic> j) => Unit(
    id: j['id'] as String,
    title: j['title'] as String,
    description: (j['description'] as String?) ?? '',
    color: Color(int.parse(j['color'] as String)),
    nodes: (j['nodes'] as List).map((n) => PathNode.fromJson(n as Map<String, dynamic>)).toList(),
    theme: j['theme'] as String?,
    guide: j['guide'] as String?,
  );
}

/// A part of the main course at one CEFR level (e.g. "Bölüm 2 · A1 · Günlük
/// hayat"). Sections open one after another; see `sectionOpen`.
class Section {
  const Section({
    required this.id,
    required this.index,
    required this.title,
    this.cefr = '',
    this.description = '',
    this.grammar = const [],
    this.units = const [],
    this.implicit = false,
  });

  /// "s1", "s2", ...
  final String id;

  /// 1-based position, shown as "Bölüm N".
  final int index;
  final String title;
  final String cefr;
  final String description;

  /// Grammar topics, shown in the section summary.
  final List<String> grammar;
  final List<Unit> units;

  /// True for a course without section metadata (the professional courses):
  /// the path shows no section header for it.
  final bool implicit;

  List<PathNode> get nodes => [for (final u in units) ...u.nodes];

  /// The section exam: the last unit test. Passing it opens the next section.
  PathNode? get exam {
    final all = nodes;
    for (var i = all.length - 1; i >= 0; i--) {
      if (all[i].type == NodeType.test) return all[i];
    }
    return null;
  }

  /// Reads a `section` object (of a section file or of tr_en.json).
  factory Section.fromJson(Map<String, dynamic> j, {List<Unit> units = const []}) => Section(
    id: j['id'] as String,
    index: j['index'] as int,
    title: j['title'] as String,
    cefr: (j['cefr'] as String?) ?? '',
    description: (j['description'] as String?) ?? '',
    grammar: ((j['grammar'] as List?) ?? const []).cast<String>(),
    units: units,
  );

  /// Reads a whole section file: `{"section": {...}, "units": [...]}`.
  factory Section.fromFile(Map<String, dynamic> j) => Section.fromJson(
    j['section'] as Map<String, dynamic>,
    units: (j['units'] as List).map((u) => Unit.fromJson(u as Map<String, dynamic>)).toList(),
  );
}

class Course {
  Course({
    required this.id,
    required this.title,
    required this.fromLang,
    required this.learningLang,
    List<Unit>? units,
    List<Section>? sections,
  }) : assert(units != null || sections != null),
       sections = sections ?? [Section(id: 'main', index: 1, title: title, units: units!, implicit: true)],
       units = units ?? [for (final s in sections!) ...s.units];

  final String id;
  final String title;
  final String fromLang;
  final String learningLang;

  /// Sections in path order; at least one.
  final List<Section> sections;

  /// Units of every section, in path order.
  final List<Unit> units;

  /// All nodes in path order.
  List<PathNode> get allNodes => [for (final u in units) ...u.nodes];

  /// Same course with [extra] sections appended after the existing ones.
  Course withSections(List<Section> extra) => extra.isEmpty
      ? this
      : Course(
          id: id,
          title: title,
          fromLang: fromLang,
          learningLang: learningLang,
          sections: [...sections, ...extra],
        );

  /// Reads a course file. An optional `section` object makes the file's units
  /// the course's first section (tr_en.json is "Bölüm 1 · A1 · Temeller").
  factory Course.fromJson(Map<String, dynamic> j) {
    final units = (j['units'] as List).map((u) => Unit.fromJson(u as Map<String, dynamic>)).toList();
    final meta = j['section'] as Map<String, dynamic>?;
    return Course(
      id: j['id'] as String,
      title: j['title'] as String,
      fromLang: j['fromLang'] as String,
      learningLang: j['learningLang'] as String,
      units: meta == null ? units : null,
      sections: meta == null ? null : [Section.fromJson(meta, units: units)],
    );
  }
}
