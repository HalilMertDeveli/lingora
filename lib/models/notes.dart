// The user's own study notes, imported from Notion (assets/notes/).

/// One word from the personal dictionary.
class NoteWord {
  const NoteWord({
    required this.id,
    required this.en,
    required this.tr,
    required this.topic,
    this.example,
    this.story,
  });

  final String id;
  final String en;
  final String tr;

  /// Section in the original dictionary (e.g. "Flutter", "React").
  final String topic;
  final String? example;

  /// Memory-trick story the user wrote for this word.
  final String? story;

  factory NoteWord.fromJson(Map<String, dynamic> j) => NoteWord(
    id: j['id'] as String,
    en: j['en'] as String,
    tr: j['tr'] as String,
    topic: (j['topic'] as String?) ?? 'Genel',
    example: j['example'] as String?,
    story: j['story'] as String?,
  );
}

class NoteExample {
  const NoteExample(this.en, this.tr);
  final String en;
  final String tr;

  factory NoteExample.fromJson(Map<String, dynamic> j) => NoteExample(j['en'] as String, j['tr'] as String);
}

const addedSource = 'Lingora ekledi';

/// One grammar topic from the user's notebooks.
class GrammarTopic {
  const GrammarTopic({
    required this.id,
    required this.title,
    required this.category,
    required this.source,
    required this.body,
    this.rules = const [],
    this.examples = const [],
  });

  final String id;
  final String title;

  /// Grouping in the app, e.g. "Zamanlar", "Bağlaçlar".
  final String category;

  /// Notion page it came from.
  final String source;

  /// Explanation in the user's words (Turkish), paragraphs separated by \n\n.
  final String body;
  final List<String> rules;
  final List<NoteExample> examples;

  /// Topics written by the app to fill gaps in the user's notes.
  bool get addedByApp => source == addedSource;

  factory GrammarTopic.fromJson(Map<String, dynamic> j) => GrammarTopic(
    id: j['id'] as String,
    title: j['title'] as String,
    category: j['category'] as String,
    source: j['source'] as String,
    body: (j['body'] as String?) ?? '',
    rules: ((j['rules'] as List?) ?? const []).cast<String>(),
    examples: ((j['examples'] as List?) ?? const [])
        .map((e) => NoteExample.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class NotesBundle {
  const NotesBundle({required this.words, required this.topics, required this.diaryPrompts});
  final List<NoteWord> words;
  final List<GrammarTopic> topics;

  /// Writing prompts for the diary.
  final List<String> diaryPrompts;

  List<String> get categories => {for (final t in topics) t.category}.toList();
}
