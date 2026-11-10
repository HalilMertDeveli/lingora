import 'package:flutter/material.dart';

enum ExerciseType { select, translate, fillBlank, listen, match, speak }

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

  /// Text shown to the user as the correct answer after a mistake.
  String get displayAnswer => switch (type) {
    ExerciseType.select || ExerciseType.fillBlank => answer ?? '',
    ExerciseType.translate || ExerciseType.listen => answers.first,
    ExerciseType.speak => text ?? '',
    ExerciseType.match => '',
  };

  factory Exercise.fromJson(Map<String, dynamic> j) {
    final type = ExerciseType.values.byName(j['type'] as String);
    List<String> strings(String key) => ((j[key] as List?) ?? const []).cast<String>();
    return Exercise(
      type: type,
      prompt: j['prompt'] as String?,
      text: j['text'] as String?,
      lang: (j['lang'] as String?) ?? 'en',
      translation: j['translation'] as String?,
      answer: j['answer'] as String?,
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
    );
  }
}

enum NodeType { lesson, chest, story, test }

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
  });

  final String id;
  final NodeType type;
  final String title;
  final String description;
  final List<Exercise> exercises;
  final int rewardXp;

  /// Dialogue and questions (story nodes).
  final List<StoryStep> steps;

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
  );
}

class Unit {
  const Unit({
    required this.id,
    required this.title,
    required this.description,
    required this.color,
    required this.nodes,
  });

  final String id;
  final String title;
  final String description;
  final Color color;
  final List<PathNode> nodes;

  factory Unit.fromJson(Map<String, dynamic> j) => Unit(
    id: j['id'] as String,
    title: j['title'] as String,
    description: (j['description'] as String?) ?? '',
    color: Color(int.parse(j['color'] as String)),
    nodes: (j['nodes'] as List).map((n) => PathNode.fromJson(n as Map<String, dynamic>)).toList(),
  );
}

class Course {
  const Course({
    required this.id,
    required this.title,
    required this.fromLang,
    required this.learningLang,
    required this.units,
  });

  final String id;
  final String title;
  final String fromLang;
  final String learningLang;
  final List<Unit> units;

  /// All nodes in path order.
  List<PathNode> get allNodes => [for (final u in units) ...u.nodes];

  factory Course.fromJson(Map<String, dynamic> j) => Course(
    id: j['id'] as String,
    title: j['title'] as String,
    fromLang: j['fromLang'] as String,
    learningLang: j['learningLang'] as String,
    units: (j['units'] as List).map((u) => Unit.fromJson(u as Map<String, dynamic>)).toList(),
  );
}
