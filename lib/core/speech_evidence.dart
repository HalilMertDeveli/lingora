/// Pronunciation evidence for the voice coach's karne, taken only from what
/// the phone's speech recognizer actually did. Nothing here is a score: a word
/// lands in the list when
/// 1. the learner fixed it by hand after speaking into a similar-sounding
///    word (the recognizer wrote "tree", the learner sent "three"), or
/// 2. the recognizer hesitated: one of its other guesses had a different word
///    in that place ("coffee" / "copy").
/// The recognizer's own confidence for the utterance travels along, when it
/// reports one. The server keeps only words the learner really sent
/// (functions/src/conversation_report.ts).
library;

import '../services/speech.dart' show SpeechGuess;

class WeakWordEvidence {
  const WeakWordEvidence({required this.word, this.heard = '', this.confidence});

  /// The word the learner meant (as sent).
  final String word;

  /// What the recognizer wrote instead, or '' when it only hesitated.
  final String heard;

  /// The recognizer's confidence for the utterance, 0..1, if it gave one.
  final double? confidence;

  Map<String, Object?> toJson() => {'word': word, 'heard': heard, 'confidence': confidence};

  factory WeakWordEvidence.fromJson(Map<String, Object?> j) => WeakWordEvidence(
    word: j['word'] as String? ?? '',
    heard: j['heard'] as String? ?? '',
    confidence: (j['confidence'] as num?)?.toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is WeakWordEvidence &&
      other.word == word &&
      other.heard == heard &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(word, heard, confidence);

  @override
  String toString() => 'WeakWordEvidence($word, heard: $heard, $confidence)';
}

/// Lower-case words with letters (and apostrophes) only.
List<String> evidenceWords(String text) =>
    RegExp(r"[a-z][a-z']*").allMatches(text.toLowerCase()).map((m) => m[0]!).toList();

/// Short words ("a", "is", "to") are grammar, not pronunciation.
bool _worthIt(String w) => w.replaceAll("'", '').length >= 3;

/// Levenshtein distance between two words.
int _distance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final row = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      row[j] = [prev[j] + 1, row[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
    }
    prev = row;
  }
  return prev[b.length];
}

/// [heard] could be a mishearing of [meant] ("tree" for "three"), not a
/// different word the learner chose on second thought ("a" for "the").
bool _soundsAlike(String heard, String meant) =>
    heard.isNotEmpty && _distance(heard, meant) <= (meant.length / 2).floor().clamp(1, 3);

/// Pairs of (word in [a], word in [b]) where the two differ, after lining up
/// their longest common subsequence; a gap with words on one side only gives
/// '' on the other. Null when fewer than half of [b]'s words line up (the
/// learner rewrote the sentence rather than fixing a word).
List<(String, String)>? _differences(List<String> a, List<String> b) {
  final n = a.length, m = b.length;
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  if (m == 0 || lcs[0][0] * 2 < m) return null;
  final out = <(String, String)>[];
  final gapA = <String>[], gapB = <String>[];
  void flush() {
    for (var k = 0; k < (gapA.length > gapB.length ? gapA.length : gapB.length); k++) {
      out.add((k < gapA.length ? gapA[k] : '', k < gapB.length ? gapB[k] : ''));
    }
    gapA.clear();
    gapB.clear();
  }

  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      flush();
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      gapA.add(a[i++]);
    } else {
      gapB.add(b[j++]);
    }
  }
  gapA.addAll(a.sublist(i));
  gapB.addAll(b.sublist(j));
  flush();
  return out;
}

/// Evidence for one spoken-then-sent message: [guesses] are the recognizer's
/// guesses (favourite first, [lastRecognition]) and [sent] the text the
/// learner finally sent.
List<WeakWordEvidence> speechEvidence(List<SpeechGuess> guesses, String sent) {
  if (guesses.isEmpty || guesses.first.words.trim().isEmpty) return const [];
  final heard = evidenceWords(guesses.first.words);
  final said = evidenceWords(sent);
  final conf = guesses.first.confidence;
  final out = <String, WeakWordEvidence>{};

  // 1. Words the learner corrected by hand into a similar-sounding word.
  for (final (h, s) in _differences(heard, said) ?? const <(String, String)>[]) {
    if (_worthIt(s) && _soundsAlike(h, s)) out[s] = WeakWordEvidence(word: s, heard: h, confidence: conf);
  }
  // 2. Words the recognizer hesitated on (and the learner kept).
  final kept = said.toSet();
  for (final alt in guesses.skip(1).take(4)) {
    for (final (h, _) in _differences(heard, evidenceWords(alt.words)) ?? const <(String, String)>[]) {
      if (h.isEmpty || !_worthIt(h) || !kept.contains(h) || out.containsKey(h)) continue;
      out[h] = WeakWordEvidence(word: h, confidence: conf);
    }
  }
  return out.values.toList();
}
