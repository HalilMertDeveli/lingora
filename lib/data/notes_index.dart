// Ordering, grouping and search for the "Notlarım" notebook: one place that
// decides how the user's notes are laid out, so every notes screen shows the
// same order (grammar in the order of the notebook, words A-Z by topic).

import '../models/notes.dart';
import 'notes_practice.dart';

/// A titled group of notes (a grammar category or a dictionary topic).
class NoteSection<T> {
  const NoteSection(this.title, this.items);
  final String title;
  final List<T> items;
}

/// Lowercase for searching: Turkish and English "i" variants match each other,
/// so "if" finds "If clauses" and "isim" finds "İsimler".
String foldForSearch(String s) =>
    s.replaceAll('İ', 'i').replaceAll('I', 'i').toLowerCase().replaceAll('ı', 'i');

bool _has(String? text, String q) => text != null && foldForSearch(text).contains(q);

const _alphabet = 'abcçdefgğhıijklmnoöprsştuüvwxyz';

int _rank(String ch) {
  final i = _alphabet.indexOf(ch);
  return i < 0 ? ch.codeUnitAt(0) + 100 : i;
}

/// Alphabetical order that puts Ç, Ğ, İ, Ö, Ş, Ü where a Turkish reader expects.
int trCompare(String a, String b) {
  final x = a.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  final y = b.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  final n = x.length < y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    final d = _rank(x[i]) - _rank(y[i]);
    if (d != 0) return d;
  }
  return x.length - y.length;
}

bool topicMatches(GrammarTopic t, String query) {
  final q = foldForSearch(query.trim());
  if (q.isEmpty) return true;
  return _has(t.title, q) ||
      _has(t.category, q) ||
      _has(t.body, q) ||
      t.rules.any((r) => _has(r, q)) ||
      t.examples.any((e) => _has(e.en, q) || _has(e.tr, q));
}

bool wordMatches(NoteWord w, String query) {
  final q = foldForSearch(query.trim());
  if (q.isEmpty) return true;
  return _has(w.en, q) || _has(w.tr, q) || _has(w.example, q) || _has(w.story, q);
}

/// Grammar categories in the order they first appear in the notebook (the
/// curriculum order: Temeller, To be, Zamanlar…), each with its topics.
List<NoteSection<GrammarTopic>> grammarSections(List<GrammarTopic> topics, {String query = ''}) {
  final byCategory = <String, List<GrammarTopic>>{};
  for (final t in topics) {
    if (topicMatches(t, query)) byCategory.putIfAbsent(t.category, () => []).add(t);
  }
  return [for (final e in byCategory.entries) NoteSection(e.key, e.value)];
}

/// Dictionary topics: the user's own additions first, the rest A-Z.
List<String> wordTopics(List<NoteWord> words) {
  final topics = {for (final w in words) w.topic}.toList()
    ..sort((a, b) {
      if (a == customTopic) return -1;
      if (b == customTopic) return 1;
      return trCompare(a, b);
    });
  return topics;
}

/// Words grouped by topic (see [wordTopics]), A-Z inside each topic.
List<NoteSection<NoteWord>> wordSections(List<NoteWord> words, {String? topic, String query = ''}) {
  final shown = words.where((w) => (topic == null || w.topic == topic) && wordMatches(w, query));
  return [
    for (final t in wordTopics(words))
      if (shown.where((w) => w.topic == t).toList() case final items when items.isNotEmpty)
        NoteSection(t, items..sort((a, b) => trCompare(a.en, b.en))),
  ];
}

/// Diary days whose entry contains [query], newest first.
List<String> diaryDays(Map<String, String> diary, {String query = ''}) {
  final q = foldForSearch(query.trim());
  return diary.keys.where((d) => q.isEmpty || _has(diary[d], q)).toList()..sort((a, b) => b.compareTo(a));
}
