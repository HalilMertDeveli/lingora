import 'spelling.dart';

/// Lowercases, removes punctuation and collapses whitespace so that
/// "Good morning, thanks!" and "good morning thanks" compare equal.
/// Turkish dotted capital İ becomes plain i ("İzmir" == "izmir"); Dart's toLowerCase would
/// otherwise leave a combining dot behind.
String normalizeAnswer(String s) => s
    .replaceAll('İ', 'i')
    .toLowerCase()
    .replaceAll('’', "'")
    .replaceAll(RegExp('[.,!?;:¿¡"]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Exact match after the silent normalisation of [matchAnswer] (case,
/// punctuation, apostrophes, contractions); no spelling slips. For typed
/// answers use [matchAnswer], which also forgives small typos.
bool matchesAny(String input, List<String> accepted) => matchAnswer(input, accepted, typos: false).correct;

/// Share of the target's words that appear in what was heard (0..1).
double spokenSimilarity(String target, String heard) {
  final want = normalizeAnswer(target).split(' ').where((w) => w.isNotEmpty);
  final got = normalizeAnswer(heard).split(' ').toSet();
  if (want.isEmpty) return 0;
  return want.where(got.contains).length / want.length;
}

/// Uppercase that keeps Turkish dotted/dotless i correct ("bilgi" → "BİLGİ").
String trUpper(String s) => s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
