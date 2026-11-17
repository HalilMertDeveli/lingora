import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/spelling.dart';
import '../models/course.dart';
import '../models/vocab.dart';
import 'course_repository.dart';
import 'vocab_practice.dart';

/// English words the app itself teaches: the course's English sentences and
/// word banks, and the dictionary's headwords and examples. A spelling slip
/// that lands on one of them is another word, so [matchAnswer] does not
/// forgive it.
///
/// Only what is already loaded is used (opening a lesson never waits for the
/// dictionary); [commonWords] covers the classic confusions either way.
final spellingLexiconProvider = Provider<Set<String>>((ref) {
  final course = ref.read(courseProvider.exists) ? ref.watch(courseProvider).value : null;
  final vocab = ref.read(vocabProvider.exists) ? ref.watch(vocabProvider).value : null;
  return buildSpellingLexicon(course: course, vocab: vocab);
});

Set<String> buildSpellingLexicon({Course? course, VocabBundle? vocab}) {
  final out = <String>{};
  void add(String? s) {
    if (s != null) out.addAll(answerWords(s));
  }

  for (final node in course?.allNodes ?? const <PathNode>[]) {
    for (final ex in node.exercises) {
      if (ex.lang == 'en') add(ex.text);
      if (englishAnswer(ex)) {
        ex.answers.forEach(add);
        ex.tokens.forEach(add);
      }
    }
  }
  for (final e in vocab?.entries ?? const <VocabEntry>[]) {
    add(e.word);
    for (final x in e.examples) {
      add(x.en);
    }
  }
  return out;
}

/// Whether [ex] is answered in English (dinle-yaz, Türkçeden çeviri).
bool englishAnswer(Exercise ex) =>
    ex.type == ExerciseType.listen || (ex.type == ExerciseType.translate && ex.lang == 'tr');
