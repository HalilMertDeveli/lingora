// Notes: the shared course notes (assets/notes/: grammar topics and a
// dictionary, the same for every learner) and each learner's own notes.

/// One word from the personal dictionary.
class NoteWord {
  const NoteWord({
    required this.id,
    required this.en,
    required this.tr,
    required this.topic,
    this.example,
    this.story,
    this.at,
  });

  final String id;
  final String en;
  final String tr;

  /// Section in the original dictionary (e.g. "Flutter", "React").
  final String topic;
  final String? example;

  /// Memory trick: a short story that links the sound to the meaning.
  final String? story;

  /// For a learner's own word: when it was added or last edited (ms since
  /// epoch). Lets two devices agree on the newer copy.
  final int? at;

  NoteWord copyWith({String? en, String? tr, String? example, bool clearExample = false, int? at}) =>
      NoteWord(
        id: id,
        en: en ?? this.en,
        tr: tr ?? this.tr,
        topic: topic,
        example: clearExample ? null : (example ?? this.example),
        story: story,
        at: at ?? this.at,
      );

  factory NoteWord.fromJson(Map<String, dynamic> j) => NoteWord(
    id: j['id'] as String,
    en: j['en'] as String,
    tr: j['tr'] as String,
    topic: (j['topic'] as String?) ?? 'Genel',
    example: j['example'] as String?,
    story: j['story'] as String?,
    at: (j['at'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'en': en,
    'tr': tr,
    'topic': topic,
    if (example != null) 'example': example,
    if (story != null) 'story': story,
    if (at != null) 'at': at,
  };
}

class NoteExample {
  const NoteExample(this.en, this.tr);
  final String en;
  final String tr;

  factory NoteExample.fromJson(Map<String, dynamic> j) => NoteExample(j['en'] as String, j['tr'] as String);
}

const addedSource = 'Çenebaz ekledi';

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

/// A note the learner writes in "Notlarım". Deleting keeps a tombstone
/// ([deleted], empty text) so the deletion also reaches the learner's other
/// devices.
class UserNote {
  const UserNote({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  final String id;
  final String title;
  final String body;

  /// Milliseconds since epoch.
  final int createdAt;
  final int updatedAt;
  final bool deleted;

  UserNote copyWith({String? title, String? body, int? updatedAt, bool? deleted}) => UserNote(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
  );

  factory UserNote.fromJson(Map<String, dynamic> j) => UserNote(
    id: j['id'] as String,
    title: (j['title'] as String?) ?? '',
    body: (j['body'] as String?) ?? '',
    createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
    updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
    deleted: (j['deleted'] as bool?) ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    if (deleted) 'deleted': true,
  };
}
