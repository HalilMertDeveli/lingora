// Colours a formula's example sentence with the formula's own part roles, so
// "Subject · am/is/are · V-ing" and "We are watching TV now." use the same
// colours. The formula parts are in sentence order; each word of the example
// is matched to one part by a small dynamic programme that prefers literal
// matches ("am / is / are" ↔ "are") and word classes (pronoun ↔ subject).

import 'dart:math';

import '../models/grammar_lesson.dart';

/// A piece of the example: [text] as written, painted with [role]
/// (null for the text between words).
class ExampleSegment {
  const ExampleSegment(this.text, this.role);
  final String text;
  final PartRole? role;

  @override
  String toString() => role == null ? text : '[$text:${role!.name}]';
}

const _subjects = {'i', 'you', 'he', 'she', 'it', 'we', 'they', 'there', 'this', 'that', 'these', 'those'};
const _objectPronouns = {'me', 'him', 'her', 'us', 'them', 'it', 'you'};
const _auxWords = {
  'am', 'is', 'are', 'was', 'were', 'be', 'been', 'being', //
  'do', 'does', 'did', 'have', 'has', 'had', 'will', 'would', 'can', 'could', 'shall', 'should',
  'may', 'might', 'must', "'ll", "'m", "'re", "'s", "'ve", "'d",
};
const _clitics = {"'ll", "'m", "'re", "'s", "'ve", "'d"};
const _negWords = {'not', 'never', 'no', 'neither', 'cannot'};
const _whWords = {'what', 'where', 'when', 'why', 'who', 'whom', 'whose', 'which', 'how'};

/// Words that sit outside the formula ("Please close the window").
const _fillers = {'please'};
const _determiners = {
  'the', 'a', 'an', 'my', 'your', 'his', 'her', 'its', 'our', 'their', 'some', 'any', 'every', //
  'this', 'that', 'these', 'those', 'many', 'much', 'more', 'most',
};
const _prepositions = {
  'in', 'on', 'at', 'to', 'for', 'of', 'with', 'from', 'by', 'about', 'after', 'under', 'than', //
  'into', 'during', 'since',
};

/// Words in a part label that describe the slot instead of being English
/// words that appear in the sentence.
const _labelWords = {
  'subject',
  'verb',
  'object',
  'complement',
  'main',
  'clause',
  'subordinate',
  'modal',
  'noun',
  'adj',
  'adjective',
  'adverb',
  'action',
  'present',
  'simple',
  'continuous',
  'v',
  'v1',
  'v2',
  'v3',
  'o',
  'c',
  's',
  'wh',
  'job',
  'direct',
  'indirect',
  'isim',
  'fiil',
  'kelime',
  'cümle',
  'yer',
  'zaman',
  'sayı',
  'kişi',
  'şey',
  'zamir',
  'nesne',
  'özne',
  'sıfat',
  'durum',
  'grup',
  'ölçü',
  'yardımcı',
  'edat',
  'ana',
};

const _beForms = {'am', 'is', 'are', 'was', 'were', 'be', 'been', 'being', "'m", "'re", "'s"};
const _haveForms = {'have', 'has', 'had', "'ve", "'d"};
const _doForms = {'do', 'does', 'did'};

String _core(String token) =>
    token.toLowerCase().replaceAll('’', "'").replaceAll(RegExp(r"[^a-zçğıöşü0-9']"), '');

List<String> _labelTokens(String label) => label
    .replaceAll('İ', 'i')
    .toLowerCase()
    .replaceAll('’', "'")
    .split(RegExp(r"[^a-zçğıöşü0-9']+"))
    .where((w) => w.isNotEmpty)
    .toList();

Set<String> _literals(String label) {
  final words = _labelTokens(label).where((w) => !_labelWords.contains(w) && !label.contains('-$w')).toSet();
  // "be" in a label stands for every form of be; same for have and do.
  if (words.contains('be')) words.addAll(_beForms);
  if (words.contains('have')) words.addAll(_haveForms);
  if (words.contains('do')) words.addAll(_doForms);
  if (words.contains("'ll")) words.add('will');
  if (words.contains('will')) words.add("'ll");
  if (words.contains('am')) words.add("'m");
  if (words.contains('are')) words.add("'re");
  return words;
}

/// A label that names a slot ("Subject", "V-ing", "isim", "A", "...")
/// rather than listing the exact words ("am / is / are", "not", "There").
bool _isOpen(String label) =>
    label.contains('...') ||
    label.contains('…') ||
    label.contains('-') ||
    RegExp(r'^\s*[A-Z]\s*$').hasMatch(label) ||
    RegExp('[çğıöşüÇĞİÖŞÜ]').hasMatch(label) ||
    _labelTokens(label).any(_labelWords.contains);

/// "decided" for "decide", "looks" for "look".
bool _inflected(String c, String literal) =>
    literal.length >= 3 &&
    c.startsWith(literal) &&
    const {'s', 'es', 'd', 'ed', 'ing'}.contains(c.substring(literal.length));

/// A whole clause in one part ("S + V", "Main clause", "Cümle 1"): any
/// number of words fit.
bool _isClause(String label) =>
    RegExp(r'(\bS|Subject)\s*\+|(?<!to )\+\s*V|clause|[Cc]ümle|\.\.\.|…').hasMatch(label);

bool _isNeg(String c) => _negWords.contains(c) || c.endsWith("n't");

/// What a word adds to its part: none (function word), a head (content word)
/// or a closing head (a pronoun subject, after which the subject is complete).
enum _Kind { function, head, closing }

/// A word's fit for a part: its score and kind.
(double, _Kind) _fit(String c, FormulaPart part, Set<String> lits, bool open) {
  const f = _Kind.function, h = _Kind.head;
  if (c.isEmpty) return (0, f);
  if (lits.contains(c) || lits.any((l) => _inflected(c, l))) {
    return (6, part.role == PartRole.subject && _subjects.contains(c) ? _Kind.closing : f);
  }
  if (_fillers.contains(c)) return (-2, h);
  if (part.role == PartRole.negative && _isNeg(c)) return (4, f);
  if (!open) return (-3, h);
  final aux = _auxWords.contains(c) || c.endsWith("n't");
  final det = _determiners.contains(c);
  final prep = _prepositions.contains(c);
  return switch (part.role) {
    PartRole.subject when _subjects.contains(c) => (3, _Kind.closing),
    PartRole.subject when det => (1, f),
    PartRole.subject when aux || prep || _whWords.contains(c) || _isNeg(c) => (-2, h),
    PartRole.subject => (1, h),
    PartRole.aux => aux ? (3, f) : (-3, h),
    PartRole.verb when aux => part.text.toLowerCase().contains('be') ? (3, f) : (1, h),
    PartRole.verb when det || prep || (_subjects.contains(c) && c != 'it') => (-2, h),
    PartRole.verb => (1.5, h),
    PartRole.object when _objectPronouns.contains(c) => (2, h),
    PartRole.object when det || prep => (1, f),
    PartRole.object => (_whWords.contains(c) ? -1 : 1, h),
    PartRole.negative => (_clitics.contains(c) ? 1 : -3, h),
    PartRole.question => _whWords.contains(c) ? (4, f) : (-3, h),
    PartRole.other => (0, f),
  };
}

/// Splits on spaces and peels off clitics after pronouns ("I'll" → "I" +
/// "'ll") so they can take the aux colour; keeps the spaces as pieces.
List<String> _tokens(String sentence) {
  final out = <String>[];
  for (final m in RegExp(r'\S+|\s+').allMatches(sentence)) {
    final t = m[0]!;
    final clitic = RegExp(r"^([A-Za-z]+)(['’](?:ll|m|re|ve|d|s))([^A-Za-z]*)$").firstMatch(t);
    // Only after pronouns: "Tom's car" keeps its possessive 's.
    if (clitic != null && _subjects.contains(clitic[1]!.toLowerCase())) {
      out
        ..add(clitic[1]!)
        ..add('${clitic[2]}${clitic[3]}');
    } else {
      out.add(t);
    }
  }
  return out;
}

const _none = -1e9;

/// The formula's example cut into pieces coloured with the formula's roles.
/// Words before the first part or after the last one ("Please", "now") stay
/// uncoloured. Empty when the formula has no example.
List<ExampleSegment> colorExample(Formula f) {
  final example = f.example;
  if (example == null) return const [];
  final pieces = _tokens(example);
  final words = [
    for (var i = 0; i < pieces.length; i++)
      if (pieces[i].trim().isNotEmpty) i,
  ];
  if (words.isEmpty || f.parts.isEmpty) return [ExampleSegment(example, null)];

  // Slots: 0 = words before the formula, 1..m = the parts, m+1 = words after.
  final m = f.parts.length;
  final slots = m + 2;
  final lits = [for (final p in f.parts) _literals(p.text)];
  final open = [for (final p in f.parts) _isOpen(p.text)];
  final clause = [for (final p in f.parts) _isClause(p.text)];
  bool real(int j) => j > 0 && j <= m;
  // Skipping a formula part costs a little.
  double skip(int from, int to) => 0.5 * max(0, min(to, m + 1) - max(from, 0) - 1);
  double extra(int j, PartRole r, int heads) => switch (r) {
    _ when heads == 0 || (real(j) && clause[j - 1]) => 0,
    PartRole.subject => heads == 1 ? 0.2 : 3,
    PartRole.object || PartRole.other => 0,
    _ => 4,
  };

  // best[i][j][h]: best score with word i in slot j, which holds h heads
  // (2 = complete).
  final n = words.length;
  final best = List.generate(n, (_) => List.generate(slots, (_) => List.filled(3, _none)));
  final from = List.generate(n, (_) => List.generate(slots, (_) => List.filled(3, (-1, 0))));

  for (var i = 0; i < n; i++) {
    final c = _core(pieces[words[i]]);
    final afterComma = i > 0 && RegExp(r'[,;]$').hasMatch(pieces[words[i - 1]]);
    for (var j = 0; j < slots; j++) {
      var (s, kind) = real(j) ? _fit(c, f.parts[j - 1], lits[j - 1], open[j - 1]) : (-0.3, _Kind.function);
      // Any word can belong to a clause part.
      if (real(j) && clause[j - 1] && s < 0.5) s = 0.5;
      void offer(double score, int pj, int ph, int nh) {
        if (score > best[i][j][nh]) {
          best[i][j][nh] = score;
          from[i][j][nh] = (pj, ph);
        }
      }

      final fresh = switch (kind) {
        _Kind.function => 0,
        _Kind.head => 1,
        _Kind.closing => 2,
      };
      if (i == 0) {
        offer(s - skip(0, j), -1, 0, fresh);
        continue;
      }
      for (var pj = 0; pj <= j; pj++) {
        for (var ph = 0; ph < 3; ph++) {
          final prev = best[i - 1][pj][ph];
          if (prev == _none) continue;
          if (pj == j) {
            final role = real(j) ? f.parts[j - 1].role : PartRole.other;
            final penalty =
                (kind == _Kind.function ? 0.0 : extra(j, role, ph)) +
                (afterComma && real(j)
                    ? (clause[j - 1] && ((j < m && clause[j]) || (j > 1 && clause[j - 2])) ? 3 : 0.8)
                    : 0);
            offer(prev + s - penalty, pj, ph, kind == _Kind.function ? ph : max(ph + 1, fresh).clamp(0, 2));
          } else {
            // Two clauses in a row are split at a comma when there is one.
            final midClause = real(pj) && real(j) && clause[pj - 1] && clause[j - 1] && !afterComma;
            offer(prev + s - skip(pj, j) - (midClause ? 1 : 0), pj, ph, fresh);
          }
        }
      }
    }
  }

  var (bj, bh) = (0, 0);
  var top = _none;
  for (var j = 0; j < slots; j++) {
    for (var h = 0; h < 3; h++) {
      final s = best[n - 1][j][h] - skip(j, m + 1);
      if (s > top) (top, bj, bh) = (s, j, h);
    }
  }
  final roleOf = <int, PartRole?>{};
  for (var i = n - 1; i >= 0; i--) {
    roleOf[words[i]] = real(bj) ? f.parts[bj - 1].role : null;
    (bj, bh) = from[i][bj][bh];
  }

  final out = <ExampleSegment>[];
  for (var i = 0; i < pieces.length; i++) {
    final role = roleOf[i];
    final last = out.lastOrNull;
    if (last != null && last.role == role) {
      out[out.length - 1] = ExampleSegment(last.text + pieces[i], role);
    } else if (role == null &&
        !roleOf.containsKey(i) &&
        last != null &&
        i + 1 < pieces.length &&
        roleOf[i + 1] == last.role) {
      // A space between two words of the same part stays with them.
      out[out.length - 1] = ExampleSegment(last.text + pieces[i], last.role);
    } else {
      out.add(ExampleSegment(pieces[i], role));
    }
  }
  return out;
}
