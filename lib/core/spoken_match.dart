/// Compares what the speech recognizer heard with the sentence the learner
/// was asked to say.
///
/// Speech is not typing: the recognizer writes "2" for "two", "color" for
/// "colour", "there" for "their", and a Turkish accent turns "think" into
/// "tink" or "very" into "wery". None of that is the learner's mistake, so
/// the comparison is word by word, in order, and forgiving:
/// 1. The silent normalisation of typed answers ([answerWords]): case,
///    punctuation, contractions (I'm = I am).
/// 2. Numbers written as digits become words ("7:30" = "seven thirty").
/// 3. Words that sound the same count (to/too/two, right/write).
/// 4. Words that sound close count too: a rough sound key ("th" as "t",
///    "w" as "v", no vowels) or a small spelling distance.
///
/// The pronunciation coach turns 3 and 4 off ([lenient] false) for minimal
/// pairs, where "ship" for "sheep" is exactly the mistake to catch.
///
/// Every alternative transcription of the recognizer is scored and the best
/// one wins, and a sentence passes when about 80% of its words were heard.
library;

import 'spelling.dart';

/// A word of the target sentence as it is shown, and whether it was heard.
typedef SpokenWord = ({String text, bool heard});

class SpokenMatch {
  const SpokenMatch({required this.words, required this.heard, required this.matched, required this.total});

  /// No speech at all.
  static const none = SpokenMatch(words: [], heard: '', matched: 0, total: 0);

  /// The target sentence word by word (as written), marked heard or missed.
  final List<SpokenWord> words;

  /// The transcription that matched best.
  final String heard;

  /// Words of the (normalised) target that were heard, out of [total].
  final int matched;
  final int total;

  double get score => total == 0 ? 0 : matched / total;
  int get missed => total - matched;

  /// About 80% of the words: everything in one or two words, one slip in
  /// three to seven, one in five after that.
  bool get passed => heard.trim().isNotEmpty && total > 0 && missed <= allowedMisses(total);

  bool get perfect => total > 0 && matched == total;

  @override
  String toString() => 'SpokenMatch($matched/$total "$heard")';
}

/// Missed words a spoken sentence of [words] words may still pass with.
int allowedMisses(int words) => words <= 2 ? 0 : (words < 8 ? 1 : (words * 0.2).round());

/// Scores every transcription in [alternatives] against [target] and returns
/// the best one (the first one on a tie: the recognizer's own favourite).
SpokenMatch matchSpoken(String target, Iterable<String> alternatives, {bool lenient = true}) {
  final want = _targetWords(target);
  SpokenMatch? best;
  for (final alt in alternatives) {
    if (alt.trim().isEmpty) continue;
    final m = _match(want, alt, lenient);
    if (best == null || m.matched > best.matched) best = m;
  }
  return best ??
      SpokenMatch(
        words: [for (final t in want.shown) (text: t, heard: false)],
        heard: '',
        matched: 0,
        total: want.words.length,
      );
}

/// The best of [alternatives] for [target], or the first one without a target.
String bestTranscription(String? target, List<String> alternatives) {
  if (alternatives.isEmpty) return '';
  if (target == null || target.trim().isEmpty) return alternatives.first;
  final m = matchSpoken(target, alternatives);
  return m.heard.isEmpty ? alternatives.first : m.heard;
}

/// Lower-case words for comparing speech: [answerWords] plus numbers as
/// words and hyphens as spaces ("twenty-one" = "21").
List<String> spokenWords(String s) {
  final out = <String>[];
  final spaced = s
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'(?<=\w)-(?=\w)'), ' ')
      .replaceAll('%', ' percent');
  for (final w in answerWords(spaced)) {
    final n = RegExp(r'^(\d+)(st|nd|rd|th)?$').firstMatch(w);
    if (n == null) {
      out.add(w);
      continue;
    }
    final value = int.parse(n.group(1)!);
    final words = numberWords(value);
    if (words == null) {
      out.add(w);
    } else if (n.group(2) != null) {
      out.addAll(_ordinal(words));
    } else {
      out.addAll(words);
    }
  }
  return out;
}

const _ones = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];
const _tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

/// English words for 0..9999 ("1990" is said "nineteen ninety"), or null.
List<String>? numberWords(int n) {
  if (n < 0 || n > 9999) return null;
  if (n < 20) return [_ones[n]];
  if (n < 100) return [_tens[n ~/ 10], if (n % 10 != 0) _ones[n % 10]];
  if (n < 1000) {
    return [_ones[n ~/ 100], 'hundred', if (n % 100 != 0) ...numberWords(n % 100)!];
  }
  // Years: 1990 → nineteen ninety, 2005 → two thousand five.
  if (n >= 1100 && n < 2000 && n % 100 != 0) {
    return [
      ...numberWords(n ~/ 100)!,
      ...(n % 100 < 10 ? ['oh', _ones[n % 100]] : numberWords(n % 100)!),
    ];
  }
  return [...numberWords(n ~/ 1000)!, 'thousand', if (n % 1000 != 0) ...numberWords(n % 1000)!];
}

const _ordinals = {
  'one': 'first',
  'two': 'second',
  'three': 'third',
  'five': 'fifth',
  'eight': 'eighth',
  'nine': 'ninth',
  'twelve': 'twelfth',
};

List<String> _ordinal(List<String> words) {
  final last = words.last;
  final o =
      _ordinals[last] ?? (last.endsWith('y') ? '${last.substring(0, last.length - 1)}ieth' : '${last}th');
  return [...words.take(words.length - 1), o];
}

class _Target {
  _Target(this.shown, this.words, this.owner);

  /// Tokens as written in the sentence.
  final List<String> shown;

  /// Normalised words, and the index in [shown] each one comes from.
  final List<String> words;
  final List<int> owner;
}

_Target _targetWords(String target) {
  final shown = target.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  final words = <String>[];
  final owner = <int>[];
  for (final (i, token) in shown.indexed) {
    for (final w in spokenWords(token)) {
      words.add(w);
      owner.add(i);
    }
  }
  return _Target(shown, words, owner);
}

SpokenMatch _match(_Target want, String heard, bool lenient) {
  final a = want.words;
  final b = spokenWords(heard);
  // Longest common subsequence with a forgiving word equality: the order of
  // the sentence counts, extra words ("um", a repeated start) do not.
  final n = a.length, m = b.length;
  final d = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      d[i][j] = sameSpokenWord(a[i], b[j], lenient: lenient)
          ? d[i + 1][j + 1] + 1
          : (d[i + 1][j] > d[i][j + 1] ? d[i + 1][j] : d[i][j + 1]);
    }
  }
  final hit = List<bool>.filled(n, false);
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (sameSpokenWord(a[i], b[j], lenient: lenient) && d[i][j] == d[i + 1][j + 1] + 1) {
      hit[i] = true;
      i++;
      j++;
    } else if (d[i + 1][j] >= d[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  // A written token counts as heard when all of its words were ("I'm" = i + am).
  final shownHeard = List<bool>.filled(want.shown.length, true);
  final hasWords = List<bool>.filled(want.shown.length, false);
  for (var k = 0; k < n; k++) {
    hasWords[want.owner[k]] = true;
    if (!hit[k]) shownHeard[want.owner[k]] = false;
  }
  return SpokenMatch(
    words: [for (final (k, t) in want.shown.indexed) (text: t, heard: hasWords[k] && shownHeard[k])],
    heard: heard.trim(),
    matched: hit.where((h) => h).length,
    total: n,
  );
}

/// Whether the recognizer's [heard] word stands for the [target] word.
bool sameSpokenWord(String target, String heard, {bool lenient = true}) {
  if (target == heard) return true;
  if (!lenient) return false;
  if (_homophone(target) == _homophone(heard)) return true;
  // Very short words carry too little sound to compare loosely ("a"/"I").
  if (target.length < 3 || heard.length < 3) return false;
  final kt = soundKey(target), kh = soundKey(heard);
  if (kt.length >= 2 && kt == kh) return true;
  final allowed = target.length >= 8 ? 2 : (target.length >= 4 ? 1 : 0);
  return allowed > 0 && damerauLevenshtein(target, heard) <= allowed;
}

/// Words that sound the same, grouped under one spelling.
const _homophones = {
  'too': 'to',
  'two': 'to',
  'four': 'for',
  'fore': 'for',
  'their': 'there',
  "they're": 'there',
  'write': 'right',
  'rite': 'right',
  'no': 'know',
  'here': 'hear',
  'sea': 'see',
  'buy': 'by',
  'bye': 'by',
  'eye': 'i',
  "you're": 'your',
  'won': 'one',
  'ate': 'eight',
  'weak': 'week',
  'whole': 'hole',
  'knew': 'new',
  'son': 'sun',
  'meet': 'meat',
  'peace': 'piece',
  'wear': 'where',
  'ware': 'where',
  'which': 'witch',
  'wood': 'would',
  'hour': 'our',
  'flour': 'flower',
  'road': 'rode',
  'mail': 'male',
  'tail': 'tale',
  'pair': 'pear',
  'okay': 'ok',
  'mister': 'mr',
  'missus': 'mrs',
  'doctor': 'dr',
  'grey': 'gray',
  'theatre': 'theater',
  'centre': 'center',
  'metre': 'meter',
  'litre': 'liter',
  'programme': 'program',
};

String _homophone(String w) => _homophones[w] ?? w;

/// A rough sound key: consonants as they sound to a Turkish ear ("th" may
/// come out as "t" or "d"), vowels dropped after the first letter, doubles
/// collapsed. "think" and "tink", "this" and "dis", "very" and "wery",
/// "colour" and "color" share a key.
String soundKey(String word) {
  var w = word.replaceAll(RegExp("[^a-z]"), '');
  if (w.isEmpty) return '';
  w = w
      .replaceFirst(RegExp('^kn'), 'n')
      .replaceFirst(RegExp('^wr'), 'r')
      .replaceFirst(RegExp('^wh'), 'w')
      .replaceAll('tch', 'ch')
      .replaceAll('ph', 'f')
      .replaceAll('th', 't')
      .replaceAll('ck', 'k')
      .replaceAll('dg', 'j')
      .replaceAll('d', 't')
      .replaceAll('gh', '')
      .replaceAll(RegExp('c(?=[eiy])'), 's')
      .replaceAll('c', 'k')
      .replaceAll('q', 'k')
      .replaceAll('x', 'ks')
      .replaceAll('z', 's')
      .replaceAll('w', 'v');
  final first = w[0];
  final rest = w.substring(1).replaceAll(RegExp('[aeiouy]'), '');
  final b = StringBuffer(RegExp('[aeiouy]').hasMatch(first) ? 'a' : first);
  for (final ch in rest.split('')) {
    if (b.toString().endsWith(ch)) continue;
    b.write(ch);
  }
  return b.toString();
}
