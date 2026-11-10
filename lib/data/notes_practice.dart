import 'dart:math';

import '../models/course.dart';
import '../models/notes.dart';
import 'practice.dart';
import 'progress.dart';

/// Longest example sentence (in words) that becomes a word-bank exercise.
const maxBankWords = 12;
const wordSessionNew = 10;
const wordSessionMax = 20;

final _punct = RegExp('[.,!?;:¿¡"]');

/// Splits a sentence into word-bank chips, dropping the punctuation that
/// answer matching ignores.
List<String> bankWords(String sentence) => sentence
    .replaceAll('’', "'")
    .replaceAll(_punct, ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

/// Exercises built from a grammar topic's own examples: translate both ways
/// with a word bank, plus listening and speaking.
List<LessonItem> topicItems(GrammarTopic topic, List<GrammarTopic> all, [Random? random]) {
  final r = random ?? Random();
  final usable = [
    for (var i = 0; i < topic.examples.length; i++)
      if (bankWords(topic.examples[i].en).length <= maxBankWords && topic.examples[i].tr.trim().isNotEmpty) i,
  ];
  if (usable.isEmpty) return const [];
  // Distractor words come from other examples in the same category.
  final pool = <String>{
    for (final t in all.where((t) => t.category == topic.category))
      for (final e in t.examples) ...bankWords(e.en),
  }.toList();

  List<String> distractors(List<String> exclude, int n) {
    final lower = exclude.map((w) => w.toLowerCase()).toSet();
    final options = pool.where((w) => !lower.contains(w.toLowerCase())).toList()..shuffle(r);
    return options.take(n).toList();
  }

  final items = <LessonItem>[];
  for (var k = 0; k < usable.length && items.length < 10; k++) {
    final i = usable[k];
    final ex = topic.examples[i];
    final key = 'note:${topic.id}#$i';
    final words = bankWords(ex.en);
    final Exercise exercise = switch (k % 4) {
      0 || 2 => Exercise(
        type: ExerciseType.translate,
        text: ex.tr,
        lang: 'tr',
        answers: [ex.en],
        tokens: [...words, ...distractors(words, 3)]..shuffle(r),
      ),
      1 => Exercise(type: ExerciseType.listen, text: ex.en, answers: [ex.en]),
      _ => Exercise(type: ExerciseType.speak, text: ex.en, translation: ex.tr),
    };
    items.add((key: key, ex: exercise));
  }
  return items;
}

/// Topic of the words the user adds to the dictionary themselves.
const customTopic = 'Eklediklerim';

/// Stable id for a user-added word.
String customWordId(String en) => 'u_${en.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9ğüşöçı]+'), '_')}';

/// A user-added dictionary word.
NoteWord customWord(String en, String tr, {String? example}) => NoteWord(
  id: customWordId(en),
  en: en.trim(),
  tr: tr.trim(),
  topic: customTopic,
  example: (example == null || example.trim().isEmpty) ? null : example.trim(),
);

/// The whole personal dictionary: imported notes plus the user's own words.
List<NoteWord> dictionaryWords(NotesBundle notes, Progress p) => [...notes.words, ...p.customWords];

/// Looks up [word] (case-insensitive) in [words].
NoteWord? findWord(List<NoteWord> words, String word) {
  final key = word.trim().toLowerCase();
  for (final w in words) {
    if (w.en.toLowerCase() == key) return w;
  }
  return null;
}

/// Words to review now: due ones first (oldest box first), then new ones.
List<NoteWord> wordsToReview(List<NoteWord> words, Progress p, DateTime now, {String? topic}) {
  final today = dayKey(now);
  final scoped = topic == null ? words : words.where((w) => w.topic == topic).toList();
  final due = scoped.where((w) => p.wordDue[w.id] != null && p.wordDue[w.id]!.compareTo(today) <= 0).toList()
    ..sort((a, b) => (p.wordBox[a.id] ?? 0).compareTo(p.wordBox[b.id] ?? 0));
  final fresh = scoped.where((w) => !p.wordBox.containsKey(w.id)).take(wordSessionNew);
  return [...due, ...fresh].take(wordSessionMax).toList();
}

int dueWordCount(List<NoteWord> words, Progress p, DateTime now) {
  final today = dayKey(now);
  return words.where((w) => p.wordDue[w.id] != null && p.wordDue[w.id]!.compareTo(today) <= 0).length;
}

/// Words in box 3 or higher count as learned.
int learnedWordCount(Progress p) => p.wordBox.values.where((b) => b >= 3).length;

/// Quiz from the dictionary: match rounds and multiple choice.
List<LessonItem> wordQuizItems(List<NoteWord> words, [Random? random]) {
  final r = random ?? Random();
  // Short meanings work best on cards.
  final usable = words.where((w) => w.tr.length <= 40 && w.en.length <= 30).toList()..shuffle(r);
  if (usable.length < 8) return const [];
  final items = <LessonItem>[];
  for (var round = 0; round < 2; round++) {
    final batch = usable.skip(round * 5).take(5).toList();
    items.add((
      key: 'words:match$round',
      ex: Exercise(type: ExerciseType.match, pairs: [for (final w in batch) (w.tr, w.en)]),
    ));
  }
  for (final w in usable.skip(10).take(6)) {
    final others = usable.where((o) => o.en != w.en).toList()..shuffle(r);
    final choices = [w, ...others.take(3)]..shuffle(r);
    items.add((
      key: 'words:${w.id}',
      ex: Exercise(
        type: ExerciseType.select,
        prompt: w.tr,
        answer: w.en,
        choices: [for (final c in choices) Choice(c.en, '📘')],
      ),
    ));
  }
  return items;
}
