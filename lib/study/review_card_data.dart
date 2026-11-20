import '../models/notes.dart';
import '../models/vocab.dart';
import 'review_queue.dart';

/// What a "Tekrar kartları" card shows on its two faces.
class ReviewCardData {
  const ReviewCardData({
    required this.id,
    required this.en,
    required this.tr,
    this.tag,
    this.sub,
    this.exampleEn,
    this.exampleTr,
    this.highlight,
    this.note,
    this.noteLabel,
  });

  /// Review box key.
  final String id;
  final String en;
  final String tr;

  /// Small topic or level label on the front (unit title, notebook topic).
  final String? tag;

  /// Under the word: part of speech or pronunciation hint, when known.
  final String? sub;

  final String? exampleEn;
  final String? exampleTr;

  /// The word as it appears in [exampleEn] (may be inflected); defaults to [en].
  final String? highlight;

  /// A related Notlarım pattern, a common-mistake tip or a memory trick.
  final String? note;

  /// "Sık hata", "Notlarım", "Hafıza ipucu".
  final String? noteLabel;

  /// Both faces as one sentence for screen readers.
  String get frontLabel => [en, ?sub, ?tag].join('. ');

  String get backLabel => [
    '$en: $tr',
    if (exampleEn != null) 'Örnek: $exampleEn',
    ?exampleTr,
    if (note != null) '${noteLabel ?? 'Not'}: $note',
  ].join('. ');

  /// A word from the Notlarım dictionary.
  factory ReviewCardData.fromNoteWord(NoteWord w) => ReviewCardData(
    id: w.id,
    en: w.en,
    tr: w.tr,
    tag: w.topic,
    exampleEn: w.example,
    note: w.story,
    noteLabel: w.story == null ? null : 'Hafıza ipucu',
  );
}

String _norm(String s) => s.trim().toLowerCase();

/// Whether [text] contains [word] as a whole word (case-insensitive).
bool containsWord(String text, String word) {
  final w = RegExp.escape(_norm(word));
  return RegExp('(^|[^a-z])$w([^a-z]|\$)').hasMatch(text.toLowerCase());
}

/// Builds the card for a path word, filling the back from the YDS word bank
/// ([entries]: example with its translation, common mistake) and the
/// learner's notebook ([notes]: dictionary example and memory trick, or a
/// grammar pattern whose example uses the word).
/// [why]: the reason of the mistake the card was made from ("Neden
/// yanlıştı"), shown in the card's note slot instead of a tip.
ReviewCardData reviewCardFor(
  WordCard c, {
  Map<String, VocabEntry> entries = const {},
  NotesBundle? notes,
  String? why,
}) {
  final entry = entries[c.id] ?? entries[_norm(c.en)];
  final key = _norm(c.en);
  NoteWord? noteWord;
  for (final w in notes?.words ?? const <NoteWord>[]) {
    if (_norm(w.en) == key) {
      noteWord = w;
      break;
    }
  }
  final example = entry == null || entry.examples.isEmpty ? null : entry.examples.first;

  String? note;
  String? noteLabel;
  NoteExample? patternExample;
  if (why != null && why.trim().isNotEmpty) {
    (note, noteLabel) = (why.trim(), 'Neden yanlıştı');
  } else if (entry?.tip case final tip?) {
    (note, noteLabel) = (tip, 'Sık hata');
  } else if (noteWord?.story case final story?) {
    (note, noteLabel) = (story, 'Hafıza ipucu');
  } else if (key.length >= 4) {
    // A grammar pattern from Notlarım whose example uses the word.
    outer:
    for (final t in notes?.topics ?? const <GrammarTopic>[]) {
      for (final e in t.examples) {
        if (containsWord(e.en, key)) {
          (note, noteLabel, patternExample) = (t.title, 'Notlarım', e);
          break outer;
        }
      }
    }
  }

  final exampleEn = example?.en ?? c.example ?? noteWord?.example ?? patternExample?.en;
  return ReviewCardData(
    id: c.id,
    en: c.en,
    tr: c.tr,
    tag: c.unit,
    sub: entry == null || entry.pos.isEmpty ? null : entry.pos,
    exampleEn: exampleEn,
    exampleTr: example?.tr ?? (exampleEn == patternExample?.en ? patternExample?.tr : null),
    highlight: example?.target,
    note: note,
    noteLabel: noteLabel,
  );
}

/// YDS bank entries by card id and by word, for [reviewCardFor].
Map<String, VocabEntry> entryIndex(List<VocabEntry> entries) => {
  for (final e in entries) ...{_norm(e.word): e, e.id: e, wordCardId(ydsWordPrefix, e.word): e},
};
