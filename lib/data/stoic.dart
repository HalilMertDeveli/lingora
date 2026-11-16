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
/// (fewer when the pool is small), kid-friendly ones only in Çocuk modu.
/// Remembers the pick in [prefs].
StoicQuote? pickStoicQuote(SharedPreferences prefs, List<StoicQuote> all, {required bool kid, int? seed}) {
  final pool = [
    for (final q in all)
      if (!kid || q.kid) q,
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

/// What the learner has done, shown with the quote on the result screen.
/// Built from progress after the lesson was saved, so it counts this lesson.
class StoicStats {
  const StoicStats({required this.lessonsToday, required this.streak, required this.correctTotal});

  final int lessonsToday;
  final int streak;
  final int correctTotal;

  factory StoicStats.of(Progress p, DateTime now) => StoicStats(
    lessonsToday: p.counter(now, QuestMetric.lessons),
    streak: p.streakAt(now),
    correctTotal: p.correct,
  );
}
