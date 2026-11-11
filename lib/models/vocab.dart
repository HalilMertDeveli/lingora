/// Yazılımcı İngilizcesi: English vocabulary for Turkish software developers
/// (assets/vocab/software.json, written for Dilbaz).
library;

/// Where an example sentence would appear in a developer's working day.
enum VocabContext {
  kodYorumu('kod_yorumu', 'Kod yorumu', '💬'),
  commit('commit', 'Commit mesajı', '📌'),
  pr('pr', 'PR incelemesi', '🔍'),
  ticket('ticket', 'İş kaydı', '🎫'),
  standup('standup', 'Stand-up', '🧍'),
  mulakat('mulakat', 'Teknik mülakat', '🎤'),
  dokuman('dokuman', 'Dokümantasyon', '📄'),
  mesaj('mesaj', 'E-posta / Slack', '✉️');

  const VocabContext(this.key, this.label, this.emoji);
  final String key;
  final String label;
  final String emoji;

  /// Sentences written in the team's tools: commits, reviews and tickets.
  bool get isWritten => this == commit || this == pr || this == ticket;

  static VocabContext byKey(String key) => values.firstWhere((c) => c.key == key);
}

class VocabSense {
  const VocabSense({required this.tr, required this.def});
  final String tr;

  /// Short English definition (never contains the headword).
  final String def;

  factory VocabSense.fromJson(Map<String, dynamic> j) =>
      VocabSense(tr: j['tr'] as String, def: j['def'] as String);
}

class VocabExample {
  const VocabExample({required this.en, required this.tr, required this.context, required this.target});
  final String en;
  final String tr;
  final VocabContext context;

  /// The headword exactly as it appears in [en] (may be inflected).
  final String target;

  /// [en] with [target] replaced by a blank.
  String get blanked => en.replaceFirst(target, '_____');

  factory VocabExample.fromJson(Map<String, dynamic> j) => VocabExample(
    en: j['en'] as String,
    tr: j['tr'] as String,
    context: VocabContext.byKey(j['context'] as String),
    target: j['target'] as String,
  );
}

/// A common word partnership such as "fix a bug"; [answer] is the word that
/// is left out in the "eşdizim tamamla" card.
class Collocation {
  const Collocation({required this.phrase, required this.answer, required this.tr});
  final String phrase;
  final String answer;
  final String tr;

  String get blanked => phrase.split(' ').map((w) => w == answer ? '_____' : w).join(' ');

  factory Collocation.fromJson(Map<String, dynamic> j) =>
      Collocation(phrase: j['phrase'] as String, answer: j['answer'] as String, tr: j['tr'] as String);
}

class VocabEntry {
  const VocabEntry({
    required this.id,
    required this.word,
    required this.pos,
    required this.rank,
    required this.topic,
    required this.senses,
    required this.examples,
    required this.collocations,
    this.synonym,
    this.tip,
    this.fromNotes = false,
    this.notesWord,
  });

  /// Namespaced id (`sw_...`), also the key in the review boxes.
  final String id;
  final String word;
  final String pos;

  /// Importance in everyday software work, 1 = most important.
  final int rank;
  final String topic;
  final List<VocabSense> senses;
  final List<VocabExample> examples;
  final List<Collocation> collocations;
  final String? synonym;

  /// Turkish tip about a typical Turkish-developer mistake.
  final String? tip;

  /// Also in the owner's Notion dictionary (assets/notes/words.json) as [notesWord].
  final bool fromNotes;
  final String? notesWord;

  String get tr => senses.first.tr;
  String get def => senses.first.def;

  String get posTr => switch (pos) {
    'noun' => 'isim',
    'verb' => 'fiil',
    'adjective' => 'sıfat',
    'adverb' => 'zarf',
    'phrasal verb' => 'deyimsel fiil',
    'idiom' => 'deyim',
    'abbreviation' => 'kısaltma',
    _ => 'ifade',
  };

  factory VocabEntry.fromJson(Map<String, dynamic> j) => VocabEntry(
    id: j['id'] as String,
    word: j['word'] as String,
    pos: j['pos'] as String,
    rank: j['rank'] as int,
    topic: j['topic'] as String,
    senses: [for (final s in j['senses'] as List) VocabSense.fromJson(s as Map<String, dynamic>)],
    examples: [for (final e in j['examples'] as List) VocabExample.fromJson(e as Map<String, dynamic>)],
    collocations: [
      for (final c in j['collocations'] as List) Collocation.fromJson(c as Map<String, dynamic>),
    ],
    synonym: j['synonym'] as String?,
    tip: j['tip'] as String?,
    fromNotes: j['fromNotes'] as bool? ?? false,
    notesWord: j['notesWord'] as String?,
  );
}

class VocabTopic {
  const VocabTopic({required this.name, required this.emoji, required this.description});
  final String name;
  final String emoji;
  final String description;

  factory VocabTopic.fromJson(Map<String, dynamic> j) => VocabTopic(
    name: j['name'] as String,
    emoji: j['emoji'] as String,
    description: j['description'] as String,
  );
}

class VocabBundle {
  const VocabBundle({required this.topics, required this.entries});
  final List<VocabTopic> topics;

  /// Sorted by rank.
  final List<VocabEntry> entries;

  List<VocabEntry> inTopic(String topic) => entries.where((e) => e.topic == topic).toList();

  factory VocabBundle.fromJson(Map<String, dynamic> j) => VocabBundle(
    topics: [for (final t in j['topics'] as List) VocabTopic.fromJson(t as Map<String, dynamic>)],
    entries: [for (final e in j['entries'] as List) VocabEntry.fromJson(e as Map<String, dynamic>)]
      ..sort((a, b) => a.rank.compareTo(b.rank)),
  );
}
