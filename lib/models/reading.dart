// Graded reading stories with Turkish glosses (assets/reading/stories.json).

const readingLevels = ['A1', 'A2', 'B1', 'B1+', 'B2', 'C1'];

/// Turkish name of each reading level.
const readingLevelNames = {
  'A1': 'Başlangıç',
  'A2': 'Temel',
  'B1': 'Orta',
  'B1+': 'Orta üstü',
  'B2': 'İleri orta',
  'C1': 'İleri',
};

/// Node id used with `completeNode` when a story is finished.
String readNodeId(String storyId) => 'read_$storyId';

class ReadingQuestion {
  const ReadingQuestion({
    required this.q,
    required this.options,
    required this.answer,
    required this.explain,
  });

  final String q;
  final List<String> options;

  /// Index of the right option.
  final int answer;

  /// Why the answer is right, in Turkish.
  final String explain;

  factory ReadingQuestion.fromJson(Map<String, dynamic> j) => ReadingQuestion(
    q: j['q'] as String,
    options: (j['options'] as List).cast<String>(),
    answer: j['answer'] as int,
    explain: j['explain'] as String,
  );
}

class ReadingStory {
  const ReadingStory({
    required this.id,
    required this.level,
    required this.emoji,
    required this.title,
    required this.titleTr,
    required this.text,
    required this.glosses,
    required this.questions,
  });

  final String id;

  /// CEFR level: A1, A2 or B1.
  final String level;
  final String emoji;
  final String title;
  final String titleTr;

  /// Story text, paragraphs separated by a blank line.
  final String text;

  /// Lower-case word or phrase → Turkish meaning in this story.
  final Map<String, String> glosses;
  final List<ReadingQuestion> questions;

  List<String> get paragraphs => text.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty).toList();

  int get wordCount => text.split(RegExp(r'\s+')).where((w) => normalizeWord(w).isNotEmpty).length;

  factory ReadingStory.fromJson(Map<String, dynamic> j) => ReadingStory(
    id: j['id'] as String,
    level: j['level'] as String,
    emoji: j['emoji'] as String? ?? '📖',
    title: j['title'] as String,
    titleTr: j['titleTr'] as String,
    text: j['text'] as String,
    glosses: {
      for (final e in (j['glosses'] as Map<String, dynamic>).entries) e.key.toLowerCase(): e.value as String,
    },
    questions: (j['questions'] as List)
        .map((q) => ReadingQuestion.fromJson(q as Map<String, dynamic>))
        .toList(),
  );
}

final _edges = RegExp(r"^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$", unicode: true);

/// [raw] without surrounding punctuation or quotes, keeping its case.
String stripPunctuation(String raw) => raw.replaceAll('’', "'").replaceAll(_edges, '');

/// Lower-case word without surrounding punctuation or quotes.
String normalizeWord(String raw) => stripPunctuation(raw).toLowerCase();

/// One tappable piece of a paragraph: a single word or a glossed phrase.
class ReadingToken {
  const ReadingToken({required this.text, required this.word, required this.sentence, this.gloss});

  /// As written, with punctuation (e.g. "ferry.").
  final String text;

  /// Normalized word or phrase used for lookup and pronunciation.
  final String word;

  /// Index of the sentence (across the whole story) this token starts in.
  final int sentence;

  /// Turkish meaning from the story's glosses, if any.
  final String? gloss;
}

/// Longest glossed phrase, in words.
const _maxPhrase = 6;

final _sentenceEnd = RegExp(r'[.!?]["”’)]*$');

/// Titles whose dot does not end a sentence.
const _abbreviations = {'mr.', 'mrs.', 'ms.', 'dr.'};

bool _endsSentence(String text) =>
    _sentenceEnd.hasMatch(text) && !_abbreviations.contains(text.split(' ').last.toLowerCase());

/// Splits each paragraph into tokens, grouping glossed phrases (longest match
/// first) into one token. Sentence indexes run across paragraphs.
List<List<ReadingToken>> tokenizeStory(ReadingStory story) {
  final result = <List<ReadingToken>>[];
  var sentence = 0;
  for (final paragraph in story.paragraphs) {
    final raw = paragraph.trim().split(RegExp(r'\s+'));
    final norm = raw.map(normalizeWord).toList();
    final tokens = <ReadingToken>[];
    var i = 0;
    while (i < raw.length) {
      var len = 1;
      String? gloss;
      for (var n = _maxPhrase; n >= 1; n--) {
        if (i + n > raw.length) continue;
        final key = norm.sublist(i, i + n).join(' ');
        if (story.glosses.containsKey(key)) {
          len = n;
          gloss = story.glosses[key];
          break;
        }
      }
      final text = raw.sublist(i, i + len).join(' ');
      tokens.add(
        ReadingToken(
          text: text,
          word: norm.sublist(i, i + len).where((w) => w.isNotEmpty).join(' '),
          sentence: sentence,
          gloss: gloss,
        ),
      );
      if (_endsSentence(text)) sentence++;
      i += len;
    }
    // A paragraph always closes its sentence.
    if (tokens.isNotEmpty && !_endsSentence(tokens.last.text)) sentence++;
    result.add(tokens);
  }
  return result;
}

/// Sentences of the story in reading order, for the "dinle" mode.
List<String> storySentences(List<List<ReadingToken>> paragraphs) {
  final sentences = <int, List<String>>{};
  for (final p in paragraphs) {
    for (final t in p) {
      sentences.putIfAbsent(t.sentence, () => []).add(t.text);
    }
  }
  final keys = sentences.keys.toList()..sort();
  return [for (final k in keys) sentences[k]!.join(' ')];
}
