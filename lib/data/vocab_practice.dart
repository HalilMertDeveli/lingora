import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/text.dart';
import '../models/vocab.dart';
import 'progress.dart';

/// Yazılımcı İngilizcesi logic: knowledge map, triage, review queue and the
/// review cards. Words use the same spaced-repetition boxes as the personal
/// dictionary ([Progress.wordBox] / [Progress.wordDue]) under `sw_` ids.

const vocabAsset = 'assets/vocab/software.json';
const vocabIdPrefix = 'sw_';

/// Words per rank band on the knowledge map.
const rankBandSize = 100;

/// Most cards in one review session.
const vocabSessionMax = 15;

/// Box from which a word counts as known.
const knownBox = 3;

Future<VocabBundle> loadVocab(AssetBundle bundle) async =>
    VocabBundle.fromJson(jsonDecode(await bundle.loadString(vocabAsset)) as Map<String, dynamic>);

final vocabProvider = FutureProvider<VocabBundle>((ref) => loadVocab(rootBundle));

enum VocabStatus { unknown, learning, known }

VocabStatus vocabStatus(VocabEntry e, Progress p) {
  final box = p.wordBox[e.id];
  if (box == null) return VocabStatus.unknown;
  return box >= knownBox ? VocabStatus.known : VocabStatus.learning;
}

/// One block of the knowledge map: words ranked [from]–[to].
class RankBand {
  const RankBand({
    required this.from,
    required this.to,
    required this.unknown,
    required this.learning,
    required this.known,
  });
  final int from;
  final int to;
  final int unknown;
  final int learning;
  final int known;

  int get size => unknown + learning + known;
  int get seen => learning + known;

  /// Words of this band the user probably knows: once enough words were
  /// sorted, the known share of the sorted ones is applied to the whole band.
  double get estimatedKnown => seen >= 5 ? size * known / seen : known.toDouble();
}

List<RankBand> rankBands(List<VocabEntry> entries, Progress p, {int bandSize = rankBandSize}) {
  final sorted = [...entries]..sort((a, b) => a.rank.compareTo(b.rank));
  final bands = <RankBand>[];
  for (var i = 0; i < sorted.length; i += bandSize) {
    final chunk = sorted.sublist(i, min(i + bandSize, sorted.length));
    final counts = {for (final s in VocabStatus.values) s: 0};
    for (final e in chunk) {
      counts[vocabStatus(e, p)] = counts[vocabStatus(e, p)]! + 1;
    }
    bands.add(
      RankBand(
        from: chunk.first.rank,
        to: chunk.last.rank,
        unknown: counts[VocabStatus.unknown]!,
        learning: counts[VocabStatus.learning]!,
        known: counts[VocabStatus.known]!,
      ),
    );
  }
  return bands;
}

/// Estimated share (0–100) of the track's words the user knows.
int knownPercent(List<RankBand> bands) {
  final total = bands.fold<int>(0, (s, b) => s + b.size);
  if (total == 0) return 0;
  final known = bands.fold<double>(0, (s, b) => s + b.estimatedKnown);
  return (known * 100 / total).round();
}

/// Words not sorted yet ("Kelime keşfet"), most important first.
List<VocabEntry> triageQueue(List<VocabEntry> entries, Progress p, {String? topic}) =>
    entries.where((e) => (topic == null || e.topic == topic) && !p.wordBox.containsKey(e.id)).toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));

bool _isDue(VocabEntry e, Progress p, String today) {
  final due = p.wordDue[e.id];
  return due != null && due.compareTo(today) <= 0;
}

/// Words due for review: lowest box first, then by rank.
List<VocabEntry> reviewQueue(
  List<VocabEntry> entries,
  Progress p,
  DateTime now, {
  String? topic,
  int limit = vocabSessionMax,
}) {
  final today = dayKey(now);
  final due = entries.where((e) => (topic == null || e.topic == topic) && _isDue(e, p, today)).toList()
    ..sort((a, b) {
      final box = (p.wordBox[a.id] ?? 0).compareTo(p.wordBox[b.id] ?? 0);
      return box != 0 ? box : a.rank.compareTo(b.rank);
    });
  return due.take(limit).toList();
}

int dueVocabCount(List<VocabEntry> entries, Progress p, DateTime now) {
  final today = dayKey(now);
  return entries.where((e) => _isDue(e, p, today)).length;
}

// ---------------------------------------------------------------------------
// Review cards

enum VocabCardType {
  meaning('Anlamı seç'),
  definition('Tanımdan kelimeyi seç'),
  listenSpell('Dinle ve yaz'),
  exampleBlank('Örnekte boşluğu doldur'),
  collocation('Eşdizimi tamamla'),
  synonym('Eş anlamlıyı seç'),
  devSentence('Commit/PR cümlesinde doğru kelime');

  const VocabCardType(this.label);
  final String label;
}

class VocabCard {
  const VocabCard({
    required this.type,
    required this.entry,
    required this.prompt,
    required this.answer,
    this.sub,
    this.options = const [],
    this.speak,
    this.hint,
    this.where,
  });

  final VocabCardType type;
  final VocabEntry entry;

  /// Main text: a word, a definition or a sentence with a blank.
  final String prompt;

  /// Helper line, usually Turkish.
  final String? sub;

  /// Choices; empty for typing cards.
  final List<String> options;
  final String answer;

  /// Text read aloud (dinle-yaz).
  final String? speak;

  /// Typing hint such as "d _ _ _ _ _ (6 harf)".
  final String? hint;

  /// Where the example sentence comes from (commit, PR, stand-up...).
  final VocabContext? where;

  bool get isTyping => options.isEmpty;

  bool check(String input) => isTyping ? normalizeAnswer(input) == normalizeAnswer(answer) : input == answer;
}

/// Card types an entry has content for.
List<VocabCardType> availableCardTypes(VocabEntry e) => [
  VocabCardType.meaning,
  VocabCardType.definition,
  if (e.word.length <= 24) VocabCardType.listenSpell,
  if (e.examples.isNotEmpty) VocabCardType.exampleBlank,
  if (e.collocations.isNotEmpty) VocabCardType.collocation,
  if (e.synonym != null) VocabCardType.synonym,
  if (e.examples.any((x) => x.context.isWritten)) VocabCardType.devSentence,
];

/// Card types that suit a word's box: recognition first, then recall.
List<VocabCardType> _preferredFor(int box) => switch (box) {
  0 => const [VocabCardType.meaning, VocabCardType.definition],
  1 => const [
    VocabCardType.definition,
    VocabCardType.devSentence,
    VocabCardType.collocation,
    VocabCardType.synonym,
  ],
  2 => const [
    VocabCardType.exampleBlank,
    VocabCardType.collocation,
    VocabCardType.listenSpell,
    VocabCardType.synonym,
  ],
  _ => VocabCardType.values,
};

String _hintFor(String answer) {
  final letters = answer.replaceAll(' ', '').length;
  return '${answer[0]}${' _' * (answer.length - 1)}  ($letters harf)';
}

String _matchCase(String like, String word) {
  if (like.isEmpty || word.isEmpty) return word;
  final upper = like[0] == like[0].toUpperCase() && like[0] != like[0].toLowerCase();
  return upper ? word[0].toUpperCase() + word.substring(1) : word;
}

/// Picks [n] distinct strings from [pools] in order, skipping [exclude]
/// (case-insensitive).
List<String> _pick(List<List<String>> pools, Set<String> exclude, int n, Random r) {
  final seen = {for (final x in exclude) x.toLowerCase()};
  final out = <String>[];
  for (final pool in pools) {
    final shuffled = [...pool]..shuffle(r);
    for (final s in shuffled) {
      if (out.length == n) return out;
      if (s.trim().isEmpty || !seen.add(s.toLowerCase())) continue;
      out.add(s);
    }
  }
  return out;
}

List<String> _withAnswer(String answer, List<String> distractors, Random r) =>
    [answer, ...distractors]..shuffle(r);

/// Builds a card of [type] for [e], with distractors from [all]. Returns null
/// when the entry has no content for that type.
VocabCard? buildCard(VocabEntry e, List<VocabEntry> all, VocabCardType type, Random r) {
  if (!availableCardTypes(e).contains(type)) return null;
  final others = all.where((o) => o.id != e.id && o.word.toLowerCase() != e.word.toLowerCase()).toList();
  final sameTopicPos = others.where((o) => o.topic == e.topic && o.pos == e.pos).toList();
  final samePos = others.where((o) => o.pos == e.pos).toList();
  final otherTopic = others.where((o) => o.topic != e.topic).toList();

  switch (type) {
    case VocabCardType.meaning:
      final d = _pick(
        [
          [for (final o in sameTopicPos) o.tr],
          [for (final o in samePos) o.tr],
          [for (final o in others) o.tr],
        ],
        {e.tr},
        3,
        r,
      );
      return VocabCard(
        type: type,
        entry: e,
        prompt: e.word,
        sub: e.posTr,
        speak: e.word,
        answer: e.tr,
        options: _withAnswer(e.tr, d, r),
      );
    case VocabCardType.definition:
      final d = _pick(
        [
          [for (final o in sameTopicPos) o.word],
          [for (final o in samePos) o.word],
          [for (final o in others) o.word],
        ],
        {e.word, ?e.synonym},
        3,
        r,
      );
      return VocabCard(
        type: type,
        entry: e,
        prompt: e.def,
        answer: e.word,
        options: _withAnswer(e.word, d, r),
      );
    case VocabCardType.listenSpell:
      return VocabCard(
        type: type,
        entry: e,
        prompt: 'Duyduğun kelimeyi yaz',
        sub: 'İpucu: ${e.tr}',
        speak: e.word,
        answer: e.word,
        hint: _hintFor(e.word),
      );
    case VocabCardType.exampleBlank:
      final x = e.examples[r.nextInt(e.examples.length)];
      return VocabCard(
        type: type,
        entry: e,
        prompt: x.blanked,
        sub: x.tr,
        answer: x.target,
        hint: _hintFor(x.target),
        where: x.context,
      );
    case VocabCardType.collocation:
      final c = e.collocations[r.nextInt(e.collocations.length)];
      final d = _pick(
        [
          [
            for (final o in otherTopic)
              for (final oc in o.collocations) _matchCase(c.answer, oc.answer),
          ],
          [
            for (final o in others)
              for (final oc in o.collocations) _matchCase(c.answer, oc.answer),
          ],
        ],
        {c.answer, for (final w in c.phrase.split(' ')) w},
        3,
        r,
      );
      return VocabCard(
        type: type,
        entry: e,
        prompt: c.blanked,
        sub: c.tr,
        answer: c.answer,
        options: _withAnswer(c.answer, d, r),
      );
    case VocabCardType.synonym:
      final d = _pick(
        [
          [for (final o in otherTopic.where((o) => o.pos == e.pos)) o.word],
          [for (final o in otherTopic) o.word],
          [for (final o in others) o.word],
        ],
        {e.word, e.synonym!, for (final o in others) ?o.synonym},
        3,
        r,
      );
      return VocabCard(
        type: type,
        entry: e,
        prompt: e.word,
        sub: e.tr,
        speak: e.word,
        answer: e.synonym!,
        options: _withAnswer(e.synonym!, d, r),
      );
    case VocabCardType.devSentence:
      final written = e.examples.where((x) => x.context.isWritten).toList();
      final x = written[r.nextInt(written.length)];
      final inflected = x.target.toLowerCase() != e.word.toLowerCase();
      final d = _pick(
        [
          if (inflected)
            [
              for (final o in sameTopicPos)
                for (final ox in o.examples)
                  if (ox.target.toLowerCase() != o.word.toLowerCase()) _matchCase(x.target, ox.target),
            ],
          [for (final o in sameTopicPos) _matchCase(x.target, o.word)],
          [for (final o in samePos) _matchCase(x.target, o.word)],
          [for (final o in others) _matchCase(x.target, o.word)],
        ],
        {x.target, e.word},
        3,
        r,
      );
      return VocabCard(
        type: type,
        entry: e,
        prompt: x.blanked,
        sub: x.tr,
        answer: x.target,
        options: _withAnswer(x.target, d, r),
        where: x.context,
      );
  }
}

/// One card per word, picking types that fit each word's box and avoiding
/// the same type twice in a row.
List<VocabCard> buildSession(List<VocabEntry> queue, List<VocabEntry> all, Progress p, [Random? random]) {
  final r = random ?? Random();
  final cards = <VocabCard>[];
  VocabCardType? last;
  for (final e in queue) {
    final available = availableCardTypes(e);
    var options = _preferredFor(p.wordBox[e.id] ?? 0).where(available.contains).toList();
    if (options.isEmpty) options = available;
    if (options.length > 1) options.remove(last);
    final type = options[r.nextInt(options.length)];
    final card = buildCard(e, all, type, r) ?? buildCard(e, all, VocabCardType.meaning, r)!;
    cards.add(card);
    last = card.type;
  }
  return cards;
}
