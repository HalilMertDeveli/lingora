import 'package:flutter/material.dart';

import '../core/text.dart';
import '../theme.dart';
import '../ui/motion.dart';
import 'common.dart';

/// Tap-to-build answer: an answer line above a bank of word tiles. Tapping a
/// tile in the bank appends it to the answer; tapping one in the answer puts
/// it back. Controlled: the parent keeps [chosen] (indexes into [words]) so
/// the built sentence survives a switch to the keyboard and back.
class WordBank extends StatelessWidget {
  const WordBank({
    super.key,
    required this.words,
    required this.chosen,
    required this.onChanged,
    this.locked = false,
  });

  /// The tiles, already in the order they are shown.
  final List<String> words;
  final List<int> chosen;
  final ValueChanged<List<int>> onChanged;
  final bool locked;

  /// The sentence the learner built so far.
  static String sentence(List<String> words, List<int> chosen) => chosen.map((i) => words[i]).join(' ');

  void _set(List<int> next) {
    if (!locked) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    // Short phones (720x1280 at 320 dpi is 640 dp): with the full gaps the
    // last row of the word bank sat under the Kontrol et bar, out of sight.
    final compact = MediaQuery.sizeOf(context).height < 700;
    final built = sentence(words, chosen);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: built.isEmpty ? 'Cevap satırı, boş' : 'Cevap satırı: $built',
          child: Container(
            key: const Key('word-bank-answer'),
            constraints: BoxConstraints(minHeight: compact ? 84 : 110),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Brand.line, width: 2),
                bottom: BorderSide(color: Brand.line, width: 2),
              ),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final i in chosen)
                  PopIn(
                    key: ValueKey(i),
                    from: 0.7,
                    child: Semantics(
                      hint: 'Cevaptan çıkar',
                      child: WordChip(words[i], onTap: () => _set([...chosen]..remove(i))),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(height: compact ? 14 : 28),
        Wrap(
          key: const Key('word-bank-tiles'),
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 10,
          children: [
            for (var i = 0; i < words.length; i++)
              chosen.contains(i)
                  ? ExcludeSemantics(child: WordChip(words[i], hidden: true))
                  : Semantics(
                      hint: 'Cevaba ekle',
                      child: WordChip(words[i], onTap: () => _set([...chosen, i])),
                    ),
          ],
        ),
      ],
    );
  }
}

/// The words of [sentence] as tiles: split on spaces, outer punctuation
/// dropped ("morning!" → "morning"), inner apostrophes kept ("I'm").
List<String> sentenceTiles(String sentence) => [
  for (final raw in sentence.split(RegExp(r'\s+')))
    if (raw.replaceAll(RegExp(r'''^[.,!?;:"“”¿¡()…-]+|[.,!?;:"“”¿¡()…-]+$'''), '') case final w
        when w.isNotEmpty)
      w,
];

/// Easily confused neighbours of common words, tried first as distractors so
/// the bank tests listening, not just counting words.
const _confusers = <String, List<String>>{
  'is': ['are', 'am'],
  'are': ['is', 'am'],
  'am': ['is', 'are'],
  'was': ['were'],
  'were': ['was'],
  'a': ['an', 'the'],
  'an': ['a', 'the'],
  'the': ['a', 'an'],
  'he': ['she'],
  'she': ['he'],
  'his': ['her'],
  'her': ['his'],
  'do': ['does'],
  'does': ['do'],
  'have': ['has'],
  'has': ['have'],
  'in': ['on', 'at'],
  'on': ['in', 'at'],
  'at': ['in', 'on'],
  'this': ['that', 'these'],
  'that': ['this'],
  'to': ['too'],
  'my': ['me'],
  'your': ["you're"],
  'good': ['well'],
  'morning': ['evening'],
  'night': ['day'],
  'go': ['goes'],
  'goes': ['go'],
  'like': ['likes'],
  'want': ['wants'],
};

/// Short, common words used when no confuser fits.
const _fillers = [
  'is', 'are', 'the', 'a', 'to', 'in', 'on', 'and', 'he', 'she', 'it', 'we', 'they', 'not', 'very', //
  'have', 'has', 'do', 'can', 'will', 'was', 'go', 'my', 'your', 'with', 'from', 'for', 'at', 'here',
];

/// The tiles for building [sentence]: its words plus two (up to three words)
/// or three distractors, shuffled. Depends only on [sentence], so the same
/// exercise always shows the same bank (screenshots, retries, tests).
List<String> sentenceBank(String sentence) {
  final tiles = sentenceTiles(sentence);
  final used = {for (final t in tiles) normalizeAnswer(t)};
  final want = tiles.length <= 3 ? 2 : 3;
  final picked = <String>[];
  void offer(Iterable<String> words) {
    for (final w in words) {
      if (picked.length >= want) return;
      final n = normalizeAnswer(w);
      if (used.contains(n) || picked.contains(w)) continue;
      picked.add(w);
    }
  }

  offer(stableShuffle([for (final t in used) ...?_confusers[t]], 'confusers:$sentence'));
  offer(stableShuffle(_fillers, 'fillers:$sentence'));
  return stableShuffle([...tiles, ...picked], 'bank:$sentence');
}
