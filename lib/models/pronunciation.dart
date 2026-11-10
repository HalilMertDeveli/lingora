// "Telaffuz koçu": units for English sounds that Turkish speakers find hard.

import 'dart:convert';

/// Two words that differ only (or mainly) in the unit's sound.
class MinimalPair {
  const MinimalPair({required this.a, required this.aTr, required this.b, required this.bTr});
  final String a;
  final String aTr;
  final String b;
  final String bTr;

  factory MinimalPair.fromJson(Map<String, dynamic> j) => MinimalPair(
    a: j['a'] as String,
    aTr: j['aTr'] as String? ?? '',
    b: j['b'] as String,
    bTr: j['bTr'] as String? ?? '',
  );
}

class PronSentence {
  const PronSentence(this.en, this.tr);
  final String en;
  final String tr;

  factory PronSentence.fromJson(Map<String, dynamic> j) => PronSentence(j['en'] as String, j['tr'] as String);
}

class PronUnit {
  const PronUnit({
    required this.id,
    required this.emoji,
    required this.title,
    required this.sound,
    required this.summary,
    required this.how,
    required this.turkish,
    required this.mistake,
    required this.pairs,
    required this.sentences,
  });

  final String id;
  final String emoji;
  final String title;
  final String sound;
  final String summary;

  /// Step-by-step mouth/tongue instructions, in Turkish.
  final List<String> how;

  /// How the sound compares to Turkish.
  final String turkish;

  /// The typical mistake a Turkish speaker makes.
  final String mistake;
  final List<MinimalPair> pairs;
  final List<PronSentence> sentences;

  String get nodeId => 'pron_$id';

  factory PronUnit.fromJson(Map<String, dynamic> j) => PronUnit(
    id: j['id'] as String,
    emoji: j['emoji'] as String,
    title: j['title'] as String,
    sound: j['sound'] as String,
    summary: j['summary'] as String,
    how: (j['how'] as List).cast<String>(),
    turkish: j['turkish'] as String,
    mistake: j['mistake'] as String,
    pairs: (j['pairs'] as List).map((p) => MinimalPair.fromJson(p as Map<String, dynamic>)).toList(),
    sentences: (j['sentences'] as List).map((s) => PronSentence.fromJson(s as Map<String, dynamic>)).toList(),
  );
}

List<PronUnit> parsePronUnits(String json) =>
    (jsonDecode(json) as List).map((u) => PronUnit.fromJson(u as Map<String, dynamic>)).toList();
