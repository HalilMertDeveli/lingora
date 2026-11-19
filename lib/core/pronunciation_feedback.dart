/// Telaffuz puanı: which words of a spoken sentence came through, word by
/// word, from what the phone's speech recognizer really did. There are no
/// percentages here: a recognizer cannot measure "akıcılık", so every word
/// gets one of three honest verdicts:
///
/// * [WordVerdict.ok] (doğru): the recognizer wrote exactly this word.
/// * [WordVerdict.hardSound] (şu ses zor): it wrote a similar-sounding
///   different word ("tree" for "three", "vest" for "west"), or one of its
///   other guesses did, so the word was close but a sound slipped.
/// * [WordVerdict.unclear] (anlaşılmadı): nothing like the word was heard.
///
/// For each problem word the likely Turkish-speaker issue is named
/// ([SoundIssue]: th, w/v, short/long vowels, final consonants…), from the
/// spelling of the word and of what was heard instead. When nothing was
/// heard the issue is only a guess from the spelling, and says so.
library;

import '../services/speech.dart' show SpeechGuess;
import 'spelling.dart' show damerauLevenshtein;
import 'spoken_match.dart';

enum WordVerdict {
  ok('Doğru'),
  hardSound('Şu ses zor'),
  unclear('Anlaşılmadı');

  const WordVerdict(this.label);

  /// Turkish label shown on the chip.
  final String label;
}

/// A sound Turkish speakers often find hard, with the coach unit that
/// teaches it (`assets/pronunciation/units.json`).
enum SoundIssue {
  thVoiceless(
    'th sesi (think)',
    'Dilinin ucunu dişlerinin arasına koy ve üfle; "t" ya da "s" değil.',
    'th_voiceless',
  ),
  thVoiced(
    'th sesi (this)',
    'Dil ucu dişlerin arasında, ses tellerin titresin; "d" ya da "z" değil.',
    'th_voiced',
  ),
  wV(
    'w ile v',
    'w için dudaklarını yuvarla, dişlerin dudağa değmesin; v için üst dişler alt dudağa değer.',
    'w_v',
  ),
  vowelLength(
    'Kısa / uzun ünlü',
    'ship–sheep, full–fool: uzun ünlüyü biraz daha uzat ve gergin söyle, kısa olanı gevşek bırak.',
    'i_ee',
  ),
  openA('Geniş a (bad)', 'bad, man: ağzını "e"den daha çok aç; "bed" ve "men" gibi kalmasın.', 'ae_e'),
  finalConsonant(
    'Kelime sonu ünsüz',
    'Son ünsüzü yutma ve sertleştirme: dog "dok", need "nit" olmasın; sesi sonuna kadar taşı.',
    'final_consonants',
  ),
  initialCluster(
    'Kelime başı sp / st / sk',
    'school, street: başa "i" ekleme ("iskul" değil); s ile hemen sonraki ünsüze geç.',
    'final_consonants',
  ),
  edEnding(
    '-ed sonu',
    'worked "workt", liked "laykt" gibi biter; -ed\'i ayrı hece yapma ama atlama da.',
    'ed_endings',
  ),
  ng('ng sesi', 'sing: n ile g\'yi ayrı söyleme ve g\'yi atlama; ses genizden çıksın.', 'r_h_ng'),
  silentLetter(
    'Okunmayan harf',
    'walk, could, island: yazılan her harf okunmaz; bu kelimeyi dinleyip taklit et.',
    'silent_letters',
  );

  const SoundIssue(this.title, this.tip, this.unitId);
  final String title;

  /// One sentence in Turkish: how to say it.
  final String tip;

  /// Telaffuz koçu unit for this sound.
  final String unitId;
}

class WordFeedback {
  const WordFeedback({
    required this.word,
    required this.verdict,
    this.heardAs = '',
    this.issue,
    this.issueIsGuess = false,
  });

  /// The word as written in the target sentence.
  final String word;
  final WordVerdict verdict;

  /// What the recognizer wrote instead ('' when nothing similar).
  final String heardAs;

  /// The likely sound behind the problem, if one fits.
  final SoundIssue? issue;

  /// True when [issue] comes from the spelling only (nothing was heard to
  /// compare with): shown as "olası neden".
  final bool issueIsGuess;

  bool get isProblem => verdict != WordVerdict.ok;

  @override
  String toString() => 'WordFeedback($word ${verdict.name} "$heardAs" ${issue?.name})';
}

class PronunciationFeedback {
  const PronunciationFeedback({required this.words, required this.heard, this.lowConfidence = false});

  static const empty = PronunciationFeedback(words: [], heard: '');

  /// The target sentence word by word, in order.
  final List<WordFeedback> words;

  /// The transcription the feedback is about.
  final String heard;

  /// The recognizer said it was unsure about the whole sentence (its own
  /// confidence below one half). Shown as a note, never as a number.
  final bool lowConfidence;

  bool get nothingHeard => heard.trim().isEmpty;
  List<WordFeedback> get problems => [
    for (final w in words)
      if (w.isProblem) w,
  ];
  bool get allClear => !nothingHeard && words.isNotEmpty && problems.isEmpty;

  /// The distinct sounds behind the problem words, most frequent first.
  List<SoundIssue> get issues {
    final count = <SoundIssue, int>{};
    for (final w in problems) {
      if (w.issue case final i?) count[i] = (count[i] ?? 0) + 1;
    }
    return (count.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => e.key).toList();
  }
}

/// "th" words with the voiced sound (this, they…); other th words are
/// voiceless (think, three…).
const voicedThWords = {
  'the', 'this', 'that', 'these', 'those', 'they', 'them', 'their', 'there', 'then', 'than', 'with', //
  'other', 'mother', 'father', 'brother', 'weather', 'together', 'though', 'without', 'either', 'neither',
};

const _vowels = 'aeiouy';
String _skeleton(String w) => w.replaceAll(RegExp('[$_vowels]'), '');
String _letters(String w) => w.toLowerCase().replaceAll(RegExp('[^a-z]'), '');

const _devoiced = {'d': 't', 'g': 'k', 'b': 'p', 'v': 'f', 'z': 's'};

/// The likely Turkish-speaker issue when [target] came out as [heard]
/// (both single words); with [heard] empty, a guess from the spelling of
/// [target] alone. Null when nothing fits.
SoundIssue? soundIssueFor(String target, String heard) {
  final t = _letters(target), h = _letters(heard);
  if (t.isEmpty) return null;
  if (h.isEmpty) return _likelyIssue(t);
  if (t.contains('th') && !h.contains('th')) {
    return voicedThWords.contains(t) ? SoundIssue.thVoiced : SoundIssue.thVoiceless;
  }
  if ((t.contains('w') && !h.contains('w') && h.contains('v')) ||
      (t.contains('v') && !h.contains('v') && h.contains('w'))) {
    return SoundIssue.wV;
  }
  if (t.endsWith('ed') &&
      t.length > 3 &&
      !h.endsWith('ed') &&
      (h.endsWith('id') || !h.endsWith('d') && !h.endsWith('t'))) {
    return SoundIssue.edEnding;
  }
  if (t.endsWith('ng') && !h.endsWith('ng')) return SoundIssue.ng;
  if (RegExp('^s[ptkcmnlw]').hasMatch(t) && RegExp('^[ie]s').hasMatch(h)) return SoundIssue.initialCluster;
  // Same consonants, other vowels: ship / sheep, bad / bed, full / fool.
  if (_skeleton(t) == _skeleton(h) && t != h) {
    if (t.contains('a') && !h.contains('a') && h.contains('e')) return SoundIssue.openA;
    return SoundIssue.vowelLength;
  }
  // The last consonant dropped or hardened: dog → dock, need → neat, card → car.
  final last = t[t.length - 1];
  if (!_vowels.contains(last)) {
    final stem = t.substring(0, t.length - 1);
    if (h == stem ||
        h.startsWith(stem) && _devoiced[last] != null && h.contains(_devoiced[last]!, stem.length)) {
      return SoundIssue.finalConsonant;
    }
    if (_devoiced[last] case final hard?
        when h.endsWith(hard) || h.endsWith('${hard}k') || h.endsWith('ck')) {
      if (damerauLevenshtein(stem, h.substring(0, h.length - 1)) <= 1) return SoundIssue.finalConsonant;
    }
  }
  return _likelyIssue(t);
}

/// A guess from spelling only, hardest-looking sound first.
SoundIssue? _likelyIssue(String t) {
  if (t.contains('th')) return voicedThWords.contains(t) ? SoundIssue.thVoiced : SoundIssue.thVoiceless;
  if (t.contains('w') && !t.startsWith('wr') || t.contains('v')) return SoundIssue.wV;
  if (t.length > 3 && t.endsWith('ed')) return SoundIssue.edEnding;
  if (t.endsWith('ng')) return SoundIssue.ng;
  if (RegExp('^s[ptk]').hasMatch(t)) return SoundIssue.initialCluster;
  if (RegExp('(^kn|^wr|alk|ould|mb\$|isl)').hasMatch(t)) return SoundIssue.silentLetter;
  if (RegExp('(ee|ea|oo)').hasMatch(t)) return SoundIssue.vowelLength;
  if (_devoiced.containsKey(t[t.length - 1])) return SoundIssue.finalConsonant;
  return null;
}

/// [heard] is a plausible slip for [target]: close in sound or spelling.
bool _closeTo(String target, String heard) {
  if (heard.isEmpty || target.isEmpty) return false;
  if (sameSpokenWord(target, heard)) return true;
  if (target.length < 3) return false;
  // Short words must at least start alike (dog / dock, not dog / log).
  if (target.length <= 4 && target[0] != heard[0]) return false;
  return damerauLevenshtein(target, heard) <= (target.length / 2).ceil().clamp(1, 3);
}

/// Exactly the target word, or one that sounds the same (to / two).
bool _exact(String target, String heard) => target == heard || sameSound(target, heard);

/// Word-by-word feedback for [target] said aloud. [guesses] are the
/// recognizer's guesses for the utterance, its favourite first
/// ([lastRecognition]); [heard] is the transcription the exercise used (by
/// default the first guess).
PronunciationFeedback pronunciationFeedback(String target, List<SpeechGuess> guesses, {String? heard}) {
  final said = heard ?? (guesses.isEmpty ? '' : guesses.first.words);
  final shown = target.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  // Normalised target words and the shown token each one belongs to.
  final want = <String>[];
  final owner = <int>[];
  for (final (i, token) in shown.indexed) {
    for (final w in spokenWords(token)) {
      want.add(w);
      owner.add(i);
    }
  }
  final got = spokenWords(said);
  final conf = guesses.isEmpty ? null : guesses.first.confidence;
  final low = conf != null && conf > 0 && conf < 0.5;
  if (got.isEmpty) {
    return PronunciationFeedback(
      heard: '',
      words: [
        for (final s in shown)
          WordFeedback(
            word: s,
            verdict: WordVerdict.unclear,
            issue: soundIssueFor(s, ''),
            issueIsGuess: true,
          ),
      ],
    );
  }

  // Line up target and heard words (longest common subsequence, forgiving
  // equality), then look at what was heard in each gap.
  final pairOf = _align(want, got);
  final verdicts = List<WordVerdict>.filled(want.length, WordVerdict.unclear);
  final heardAs = List<String>.filled(want.length, '');
  for (var k = 0; k < want.length; k++) {
    final j = pairOf[k];
    if (j != null) {
      if (_exact(want[k], got[j])) {
        verdicts[k] = WordVerdict.ok;
      } else {
        verdicts[k] = WordVerdict.hardSound;
        heardAs[k] = got[j];
      }
    }
  }
  // Unmatched target words: a close word in the same gap means a slip.
  final used = {...pairOf.whereType<int>()};
  for (var k = 0; k < want.length; k++) {
    if (pairOf[k] != null) continue;
    final lo = _prevMatched(pairOf, k) + 1;
    final hi = _nextMatched(pairOf, k, got.length);
    for (var j = lo; j < hi; j++) {
      if (!used.contains(j) && _closeTo(want[k], got[j])) {
        verdicts[k] = WordVerdict.hardSound;
        heardAs[k] = got[j];
        used.add(j);
        break;
      }
    }
  }
  // The recognizer's other guesses: a sound-alike in place of a word it
  // wrote correctly means it hesitated there (ship / sheep).
  for (final alt in guesses.skip(1).take(4)) {
    final altWords = spokenWords(alt.words);
    final altPair = _align(want, altWords);
    for (var k = 0; k < want.length; k++) {
      if (verdicts[k] != WordVerdict.ok || want[k].length < 3) continue;
      final j = altPair[k];
      String? other;
      if (j != null && !_exact(want[k], altWords[j])) other = altWords[j];
      if (other != null && _closeTo(want[k], other)) {
        verdicts[k] = WordVerdict.hardSound;
        heardAs[k] = other;
      }
    }
  }

  // Back to the written tokens: a token's verdict is its worst word's.
  final out = <WordFeedback>[];
  for (final (i, token) in shown.indexed) {
    var verdict = WordVerdict.ok;
    var as = '';
    var hasWords = false;
    for (var k = 0; k < want.length; k++) {
      if (owner[k] != i) continue;
      hasWords = true;
      if (verdicts[k].index > verdict.index) {
        verdict = verdicts[k];
        as = heardAs[k];
      }
    }
    if (!hasWords) {
      out.add(WordFeedback(word: token, verdict: WordVerdict.ok));
      continue;
    }
    final issue = verdict == WordVerdict.ok ? null : soundIssueFor(token, as);
    out.add(
      WordFeedback(
        word: token,
        verdict: verdict,
        heardAs: as,
        issue: issue,
        issueIsGuess: verdict != WordVerdict.ok && as.isEmpty,
      ),
    );
  }
  return PronunciationFeedback(words: out, heard: said.trim(), lowConfidence: low);
}

/// For each word of [a], the index of the word of [b] it lines up with.
List<int?> _align(List<String> a, List<String> b) {
  final n = a.length, m = b.length;
  final d = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      d[i][j] = sameSpokenWord(a[i], b[j])
          ? d[i + 1][j + 1] + 1
          : (d[i + 1][j] > d[i][j + 1] ? d[i + 1][j] : d[i][j + 1]);
    }
  }
  final out = List<int?>.filled(n, null);
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (sameSpokenWord(a[i], b[j]) && d[i][j] == d[i + 1][j + 1] + 1) {
      out[i++] = j++;
    } else if (d[i + 1][j] >= d[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return out;
}

int _prevMatched(List<int?> pairOf, int k) {
  for (var i = k - 1; i >= 0; i--) {
    if (pairOf[i] case final j?) return j;
  }
  return -1;
}

int _nextMatched(List<int?> pairOf, int k, int end) {
  for (var i = k + 1; i < pairOf.length; i++) {
    if (pairOf[i] case final j?) return j;
  }
  return end;
}
