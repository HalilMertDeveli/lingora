/// One shared matcher for every answer the learner types: dinle-yaz,
/// kelime tekrarı, Notlarım pratiği, sınav ve atlama testleri.
///
/// Three layers, from silent to strict:
/// 1. Normalisation that is never a mistake and shows nothing: case, spaces,
///    end punctuation, smart quotes and apostrophes, contractions
///    (I'm = I am, don't = do not).
/// 2. Small spelling slips that still count as correct but show a friendly
///    note with the exact spelling: a word-level Damerau-Levenshtein distance
///    (a swap of two letters is one edit), 1 for 4–7 letter words, 2 for 8+,
///    none for 1–3 letter words, and a budget for the whole sentence. In
///    Turkish answers, letters typed without Turkish characters
///    (ı/i, ş/s, ğ/g, ç/c, ö/o, ü/u).
/// 3. Everything else is wrong. A slip that makes another real English word
///    (their/there, then/than, form/from) is a grammar or meaning mistake,
///    not a typo, and so is a change in a grammar ending (-s, -es, -ed,
///    -ing): "go" for "goes" is wrong.
library;

import 'text.dart';

/// How a typed answer compares to the accepted ones.
enum AnswerMatchKind { exact, typo, wrong }

/// A word the learner misspelled and how it is written.
class SpellingFix {
  const SpellingFix(this.typed, this.correct);
  final String typed;
  final String correct;

  /// [correct] cut into plain and highlighted parts: the letters that differ
  /// from what was typed are highlighted ("teach" + "er" for "teachet").
  List<({String text, bool mark})> get parts {
    var start = 0;
    while (start < typed.length && start < correct.length && typed[start] == correct[start]) {
      start++;
    }
    var end = 0;
    while (end < typed.length - start &&
        end < correct.length - start &&
        typed[typed.length - 1 - end] == correct[correct.length - 1 - end]) {
      end++;
    }
    final mid = correct.substring(start, correct.length - end);
    // Extra letters only ("beautifull"): nothing is missing, mark the whole word.
    if (mid.isEmpty) return [(text: correct, mark: true)];
    return [
      if (start > 0) (text: correct.substring(0, start), mark: false),
      (text: mid, mark: true),
      if (end > 0) (text: correct.substring(correct.length - end), mark: false),
    ];
  }

  @override
  bool operator ==(Object other) => other is SpellingFix && other.typed == typed && other.correct == correct;

  @override
  int get hashCode => Object.hash(typed, correct);

  @override
  String toString() => '$typed→$correct';
}

class AnswerMatch {
  const AnswerMatch._(this.kind, {this.expected, this.fixes = const [], this.turkishLetters = false});

  static const wrong = AnswerMatch._(AnswerMatchKind.wrong);

  final AnswerMatchKind kind;

  /// The accepted answer the input matched (null when wrong).
  final String? expected;

  /// Misspelled words, in sentence order (empty unless [kind] is typo).
  final List<SpellingFix> fixes;

  /// The slip was only missing Turkish letters (ı, ş, ğ, ç, ö, ü).
  final bool turkishLetters;

  bool get correct => kind != AnswerMatchKind.wrong;
  bool get hasTypo => kind == AnswerMatchKind.typo;

  @override
  String toString() => 'AnswerMatch($kind, $fixes)';
}

/// Most edits accepted in one answer, however long.
const maxSentenceTypos = 3;

/// Edits accepted in a word of [length] letters.
int typoAllowance(int length) => length <= 3
    ? 0
    : length <= 7
    ? 1
    : 2;

/// Edits accepted in a whole answer of [words] words: 2, or 3 from 8 words on.
int sentenceTypoBudget(int words) => words >= 8 ? maxSentenceTypos : 2;

/// Compares [input] with each of [accepted].
///
/// [turkish] is for answers written in Turkish (English → Turkish
/// translation): only missing Turkish letters are forgiven there, since one
/// letter is often a whole suffix in Turkish. [typos] false keeps the
/// normalisation but forgives no spelling (word banks, where nothing is typed).
/// [lexicon] holds lower-case English words the app knows; a slip that makes
/// one of them is a different word, not a typo.
AnswerMatch matchAnswer(
  String input,
  List<String> accepted, {
  bool turkish = false,
  bool typos = true,
  Set<String> lexicon = const {},
}) {
  final typed = answerWords(input);
  if (typed.isEmpty) return AnswerMatch.wrong;
  AnswerMatch? best;
  var bestCost = 1 << 30;
  for (final a in accepted) {
    final want = answerWords(a);
    if (want.isEmpty || want.length != typed.length) continue;
    if (_sameWords(typed, want)) return AnswerMatch._(AnswerMatchKind.exact, expected: a);
    if (!typos) continue;
    final fixes = <SpellingFix>[];
    var cost = 0;
    var ok = true;
    var onlyTurkish = true;
    for (var i = 0; i < want.length && ok; i++) {
      final t = typed[i], w = want[i];
      if (t == w) continue;
      if (foldTurkish(t) == foldTurkish(w)) {
        fixes.add(SpellingFix(t, w));
        cost++;
        continue;
      }
      onlyTurkish = false;
      final d = turkish ? null : spellingSlip(t, w, lexicon: lexicon);
      if (d == null) {
        ok = false;
      } else {
        fixes.add(SpellingFix(t, w));
        cost += d;
      }
    }
    if (!ok) continue;
    // Missing Turkish letters are a keyboard matter: never out of budget.
    if (!onlyTurkish && cost > sentenceTypoBudget(want.length)) continue;
    if (cost < bestCost) {
      bestCost = cost;
      best = AnswerMatch._(AnswerMatchKind.typo, expected: a, fixes: fixes, turkishLetters: onlyTurkish);
    }
  }
  return best ?? AnswerMatch.wrong;
}

bool _sameWords(List<String> a, List<String> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Lower-case words of an answer after the silent normalisation.
List<String> answerWords(String s) {
  final text = normalizeAnswer(s.replaceAll(RegExp('[‘’ʼ`´]'), "'").replaceAll(RegExp('[“”„«»…]'), ' '));
  final out = <String>[];
  for (var w in text.split(' ')) {
    w = w.replaceAll(RegExp(r"^'+|'+$"), '');
    if (w.isEmpty) continue;
    final long = _contractions[w] ?? _expandSuffix(w);
    out.addAll(long == null ? [w] : long.split(' '));
  }
  return out;
}

/// The same word without Turkish letters ("güçlü" → "guclu").
String foldTurkish(String s) {
  const from = 'ıişğçöüâîû';
  const to = 'iisgcouaiu';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i < 0 ? ch : to[i]);
  }
  return b.toString();
}

const _contractions = {
  "i'm": 'i am',
  "can't": 'can not',
  'cannot': 'can not',
  "won't": 'will not',
  "shan't": 'shall not',
  "let's": 'let us',
  "it's": 'it is',
  "he's": 'he is',
  "she's": 'she is',
  "that's": 'that is',
  "there's": 'there is',
  "here's": 'here is',
  "what's": 'what is',
  "where's": 'where is',
  "who's": 'who is',
  "how's": 'how is',
};

/// you're → you are, don't → do not, we've → we have…
String? _expandSuffix(String w) {
  const tails = {"n't": ' not', "'re": ' are', "'ve": ' have', "'ll": ' will', "'d": ' would'};
  for (final MapEntry(:key, :value) in tails.entries) {
    if (w.length > key.length && w.endsWith(key)) return w.substring(0, w.length - key.length) + value;
  }
  return null;
}

/// Edits between [typed] and [word] when the difference is a forgivable
/// spelling slip, or null when it is a different word or too far off.
int? spellingSlip(String typed, String word, {Set<String> lexicon = const {}}) {
  final allowed = typoAllowance(word.length);
  if (allowed == 0 || (typed.length - word.length).abs() > allowed) return null;
  final d = damerauLevenshtein(typed, word);
  if (d == 0 || d > allowed) return null;
  // Another real word: a meaning or grammar mistake.
  if (commonWords.contains(typed) || lexicon.contains(typed)) return null;
  if (_touchesGrammarEnding(typed, word)) return null;
  return d;
}

/// Endings a slip may not add or drop ("love" / "loved").
const _addedEndings = ['ing', 'ies', 'es', 'ed', 's', 'd'];

/// Endings a slip may not change: a slip inside them is a grammar slip
/// ("walkd" for "walked"). A bare final d is not one ("cart" for "card").
const _endings = ['ing', 'ies', 'es', 'ed', 's'];

/// The slip adds, drops or changes a grammar ending: "go" for "goes",
/// "walkd" for "walked", "book" for "books".
bool _touchesGrammarEnding(String typed, String word) {
  final (short, long) = typed.length < word.length ? (typed, word) : (word, typed);
  if (long.startsWith(short) && _addedEndings.contains(long.substring(short.length))) return true;
  var p = 0;
  while (p < typed.length && p < word.length && typed[p] == word[p]) {
    p++;
  }
  for (final e in _endings) {
    // "-s" only as an ending: not the "ss" of "class" or the "us" of "bus".
    if (e == 's' && (word.endsWith('ss') || word.endsWith('us'))) continue;
    if (word.endsWith(e) && word.length - e.length >= 3 && p >= word.length - e.length) return true;
  }
  return false;
}

/// Optimal string alignment distance: insert, delete, substitute, and swap
/// of two neighbouring letters, each one edit ("recieve" → "receive" is 1).
int damerauLevenshtein(String a, String b) {
  final n = a.length, m = b.length;
  if (n == 0) return m;
  if (m == 0) return n;
  final d = List.generate(n + 1, (i) => List<int>.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = d[i - 1][j] + 1;
      if (d[i][j - 1] + 1 < v) v = d[i][j - 1] + 1;
      if (d[i - 1][j - 1] + cost < v) v = d[i - 1][j - 1] + cost;
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] && d[i - 2][j - 2] + 1 < v) {
        v = d[i - 2][j - 2] + 1;
      }
      d[i][j] = v;
    }
  }
  return d[n][m];
}

/// Pairs learners mix up. Each side is a real word, so a slip from one to
/// the other is never forgiven, even before the course words are loaded.
const confusedPairs = [
  ('their', 'there'),
  ("they're", 'there'),
  ('then', 'than'),
  ('live', 'life'),
  ('lose', 'loose'),
  ('quite', 'quiet'),
  ('form', 'from'),
  ('were', 'where'),
  ('wear', 'where'),
  ('of', 'off'),
  ('a', 'an'),
  ('is', 'are'),
  ('is', 'was'),
  ('was', 'were'),
  ('has', 'have'),
  ("it's", 'its'),
  ('your', "you're"),
  ('to', 'too'),
  ('accept', 'except'),
  ('affect', 'effect'),
  ('advice', 'advise'),
  ('desert', 'dessert'),
  ('later', 'latter'),
  ('since', 'sense'),
  ('through', 'though'),
  ('though', 'thought'),
  ('whether', 'weather'),
  ('want', 'went'),
  ('want', 'wont'),
  ('this', 'these'),
  ('that', 'than'),
  ('come', 'came'),
  ('know', 'now'),
  ('know', 'known'),
  ('hear', 'here'),
  ('wait', 'weight'),
  ('week', 'weak'),
  ('meat', 'meet'),
  ('right', 'write'),
  ('buy', 'by'),
  ('steal', 'steel'),
  ('dairy', 'diary'),
  ('angel', 'angle'),
  ('cloth', 'clothes'),
  ('price', 'prize'),
  ('worse', 'worst'),
  ('chose', 'choose'),
  ('lead', 'led'),
  ('lend', 'land'),
  ('rise', 'raise'),
  ('sit', 'set'),
  ('fell', 'feel'),
  ('fill', 'feel'),
  ('leave', 'live'),
  ('sheep', 'ship'),
  ('bad', 'bed'),
  ('man', 'men'),
  ('woman', 'women'),
  ('ever', 'every'),
  ('hole', 'whole'),
  ('peace', 'piece'),
  ('plane', 'plain'),
  ('road', 'rode'),
  ('son', 'sun'),
  ('tail', 'tale'),
  ('waist', 'waste'),
  ('which', 'witch'),
  ('wood', 'would'),
  ('board', 'bored'),
  ('break', 'brake'),
  ('flour', 'flower'),
  ('hour', 'our'),
  ('new', 'knew'),
  ('no', 'know'),
  ('one', 'won'),
  ('see', 'sea'),
  ('some', 'sum'),
  ('tea', 'tee'),
  ('wander', 'wonder'),
  ('bought', 'brought'),
  ('think', 'thing'),
  ('thin', 'thing'),
  ('work', 'walk'),
  ('word', 'world'),
  ('cook', 'cooker'),
  ('fun', 'funny'),
];

/// Short, everyday English words plus both sides of [confusedPairs]: a slip
/// that lands on one of these is a different word. The course and the
/// dictionary add the rest at run time (see `spellingLexiconProvider`).
final Set<String> commonWords = {
  for (final (a, b) in confusedPairs) ...[a, b],
  ...'''
a an the and or but if so as at by for from in into of off on onto out over to up with without about
above after again against all also am are be been before being below between both can could did do does
doing done down during each few further had has have having he her here hers him his how i is it its
just me more most my no nor not now once only other our ours same she should some such than that their
theirs them then there these they this those through too under until very was we were what when where
which while who whom why will would you your yours yes go goes went gone going get gets got make made
take took taken give gave given see saw seen come came know knew known think thought say said tell told
ask work works worked play plays played live lives lived like likes liked love loved want wants wanted
need needs use used look looks looked find found feel felt keep kept let put run ran set sit sat stand
stood read write wrote written speak spoke talk walk call try help start stop open close show turn move
pay buy sell send meet learn teach study eat ate drink sleep wake wear wore win won lose lost leave left
bring brought hold hear heard begin began
good bad big small long short old new young high low hot cold warm cool fast slow hard easy early late
happy sad nice fine great best better worse worst last next first second right wrong true false full empty
day days week weeks year years time times today tomorrow yesterday morning night home house room door
car bus train city town school book books word words name man men woman women child children friend
friends family mother father brother sister boy girl dog cat food water tea coffee money job way place
thing things life lives hand hands head eye eyes face back side part line end case fact point world
form forms from farm firm film fill feel fell full fall
cut cat cot hat hit hot hut bat bet bit but pet pit pot put men man main mine mind kind find fine five
fire hire here hare hear heat hate gate late rate rare race rice nice mice wise wife wide side site
sight light night might right tight fight eight weight wait white write quite quiet quit kite bite
'''
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty),
};
