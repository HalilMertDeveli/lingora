import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'progress.dart';
import 'quests.dart';

/// Short Stoic sayings shown between exercises and on the lesson result
/// screen. English from public domain translations, Turkish written for
/// Dilbaz (sources: docs/stoaci-sozler.md).
class StoicQuote {
  const StoicQuote({
    required this.id,
    required this.author,
    required this.work,
    required this.ref,
    required this.en,
    required this.tr,
    this.kid = false,
    this.mistake = false,
  });

  final String id;

  /// "marcus", "seneca" or "epictetus".
  final String author;

  /// "meditations", "letters", "enchiridion" or "discourses".
  final String work;

  /// Book.section, letter.section or chapter, e.g. "5.1".
  final String ref;
  final String en;
  final String tr;

  /// Plain enough for Çocuk modu.
  final bool kid;

  /// Fits the card after a mistake (judgement, patience, learning).
  final bool mistake;

  static const authorNames = {'marcus': 'Marcus Aurelius', 'seneca': 'Seneca', 'epictetus': 'Epiktetos'};
  static const workNames = {
    'meditations': 'Kendime Düşünceler',
    'letters': "Lucilius'a Mektuplar",
    'enchiridion': 'Enchiridion',
    'discourses': 'Söylevler',
  };

  /// "Marcus Aurelius, Kendime Düşünceler 5.1".
  String get source => '${authorNames[author] ?? author}, ${workNames[work] ?? work} $ref';

  factory StoicQuote.fromJson(Map<String, dynamic> j) => StoicQuote(
    id: j['id'] as String,
    author: j['author'] as String,
    work: j['work'] as String,
    ref: j['ref'] as String,
    en: j['en'] as String,
    tr: j['tr'] as String,
    kid: j['kid'] as bool? ?? false,
    mistake: j['mistake'] as bool? ?? false,
  );
}

List<StoicQuote> parseStoicQuotes(String raw) {
  final j = jsonDecode(raw) as Map<String, dynamic>;
  return [for (final q in j['quotes'] as List<dynamic>) StoicQuote.fromJson(q as Map<String, dynamic>)];
}

const stoicAsset = 'assets/quotes/stoic.json';

final stoicQuotesProvider = FutureProvider<List<StoicQuote>>(
  (ref) async => parseStoicQuotes(await rootBundle.loadString(stoicAsset)),
);

/// Recently shown quote ids, newest last.
const stoicRecentKey = 'stoic_recent_v1';

/// Quotes kept out of rotation after being shown.
const stoicRecentWindow = 20;

/// Picks the next quote: never one of the last [stoicRecentWindow] shown
/// (fewer when the pool is small), kid-friendly ones only in Çocuk modu,
/// only [StoicQuote.mistake] ones after a mistake. Remembers the pick in
/// [prefs].
StoicQuote? pickStoicQuote(
  SharedPreferences prefs,
  List<StoicQuote> all, {
  required bool kid,
  bool mistake = false,
  int? seed,
}) {
  final pool = [
    for (final q in all)
      if ((!kid || q.kid) && (!mistake || q.mistake)) q,
  ];
  if (pool.isEmpty) return null;
  final recent = prefs.getStringList(stoicRecentKey) ?? const [];
  final window = (pool.length - 1).clamp(0, stoicRecentWindow);
  final blocked = recent.skip(recent.length > window ? recent.length - window : 0).toSet();
  final fresh = [
    for (final q in pool)
      if (!blocked.contains(q.id)) q,
  ];
  final from = fresh.isEmpty ? pool : fresh;
  final pick = from[(seed ?? DateTime.now().microsecondsSinceEpoch) % from.length];
  final next = [...recent.where((id) => id != pick.id), pick.id];
  prefs.setStringList(stoicRecentKey, next.skip(next.length > 40 ? next.length - 40 : 0).toList());
  return pick;
}

/// Answer count after which a session of [total] questions shows its one
/// mid-session card: about halfway, between the 4th and 8th answer. Null for
/// sessions too short to need a break.
int? stoicInterludeAt(int total) => total < 6 ? null : (total ~/ 2).clamp(4, 8);

/// Whether the card is due now, between two questions.
bool stoicInterludeDue({
  required bool enabled,
  required bool alreadyShown,
  required int answered,
  required int total,
  required bool hasNext,
}) {
  if (!enabled || alreadyShown || !hasNext) return false;
  final at = stoicInterludeAt(total);
  return at != null && answered >= at;
}

/// What the learner did, shown above the quote.
class StoicStats {
  const StoicStats({
    required this.lessonsToday,
    required this.streak,
    required this.correctTotal,
    required this.sessionCorrect,
    required this.sessionAnswered,
  });

  final int lessonsToday;
  final int streak;
  final int correctTotal;
  final int sessionCorrect;
  final int sessionAnswered;

  factory StoicStats.of(
    Progress p,
    DateTime now, {
    required int sessionCorrect,
    required int sessionAnswered,
  }) => StoicStats(
    lessonsToday: p.counter(now, QuestMetric.lessons),
    streak: p.streakAt(now),
    correctTotal: p.correct + sessionCorrect,
    sessionCorrect: sessionCorrect,
    sessionAnswered: sessionAnswered,
  );
}

/// When the last card after a mistake was shown (ms since epoch).
const stoicMistakeAtKey = 'stoic_mistake_at_v1';

/// Wrong answers in a session before the card after a mistake can come:
/// a single slip needs no comfort.
const stoicMistakeAfter = 2;

/// Answers between this card and the mid-session card.
const stoicCardGap = 3;

/// At most one card after a mistake in this long, across sessions.
const stoicMistakeCooldown = Duration(minutes: 30);

/// Whether the card after a mistake is due, between two questions, right
/// after a wrong answer: once per session, from the [stoicMistakeAfter]th
/// mistake, [stoicCardGap] answers away from the mid-session card and not
/// again within [stoicMistakeCooldown].
bool stoicMistakeDue({
  required bool enabled,
  required bool lastWrong,
  required bool alreadyShown,
  required int mistakes,
  required int answered,
  required int? lastCardAnswered,
  required bool hasNext,
  required DateTime now,
  required int lastShownMs,
}) {
  if (!enabled || !lastWrong || alreadyShown || !hasNext || mistakes < stoicMistakeAfter) return false;
  if (lastCardAnswered != null && answered - lastCardAnswered < stoicCardGap) return false;
  return now.millisecondsSinceEpoch - lastShownMs >= stoicMistakeCooldown.inMilliseconds;
}
