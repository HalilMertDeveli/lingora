import 'dart:math';

import 'package:flutter/material.dart';

import 'progress.dart';
import 'quests.dart' show stableHash;

class LeagueTier {
  const LeagueTier(this.name, this.emoji, this.color);
  final String name;
  final String emoji;
  final Color color;
}

const leagueTiers = [
  LeagueTier('Bronz', '🥉', Color(0xFFB0703C)),
  LeagueTier('Gümüş', '🥈', Color(0xFF8A94A6)),
  LeagueTier('Altın', '🥇', Color(0xFFE0A100)),
  LeagueTier('Zümrüt', '💚', Color(0xFF1FA971)),
  LeagueTier('Elmas', '💎', Color(0xFF2D9CDB)),
];

const leagueSize = 15;
const promoteCount = 5;
const demoteCount = 5;

/// Monday 00:00 of the week containing [d] (local time).
DateTime weekStart(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

Duration untilWeekEnd(DateTime now) =>
    weekStart(now).add(const Duration(days: 7)).difference(now);

class LeagueEntry {
  const LeagueEntry(this.name, this.avatar, this.xp, {this.isUser = false});
  final String name;
  final String avatar;
  final int xp;
  final bool isUser;
}

const _names = [
  'Ayşe K.', 'Mehmet Y.', 'Elif D.', 'Can B.', 'Zeynep A.', 'Emre T.', 'Deniz S.',
  'Selin Ö.', 'Burak E.', 'Ece Ç.', 'Kerem G.', 'Duru M.', 'Mert A.', 'İrem B.',
  'Ali R.', 'Sena K.', 'Arda U.', 'Nehir P.', 'Kaan F.', 'Defne İ.',
];
const _avatars = [
  '🦊', '🐼', '🐨', '🐯', '🦁', '🐸', '🐵', '🐧', '🦉', '🐙',
  '🦄', '🐢', '🐳', '🐝', '🦋', '🐞', '🐬', '🦔', '🐿️', '🦜',
];

/// The 14 rivals of a league week. They are simulated on the device (there
/// is no server yet): each gets a weekly XP total that grows over the week.
/// The same week and tier always produce the same rivals.
List<LeagueEntry> rivals({required int tier, required DateTime weekStart, required DateTime now}) {
  final rnd = Random(stableHash('${dayKey(weekStart)}#$tier'));
  final names = [..._names]..shuffle(rnd);
  final avatars = [..._avatars]..shuffle(rnd);
  final elapsed = now.difference(weekStart).inMinutes / const Duration(days: 7).inMinutes;
  final frac = elapsed.clamp(0.0, 1.0);
  final scale = 1 + 0.5 * tier;

  return [
    for (var i = 0; i < leagueSize - 1; i++)
      () {
        // About one in five rivals barely plays.
        final active = rnd.nextDouble() > 0.2;
        final weekTotal = active ? (40 + rnd.nextInt(320)) * scale : rnd.nextInt(30).toDouble();
        final pace = 0.7 + rnd.nextDouble() * 0.7; // early birds vs. last-minute grinders
        return LeagueEntry(names[i], avatars[i], (weekTotal * pow(frac, pace)).round());
      }(),
  ];
}

/// Everyone sorted by XP; on a tie the user ranks above rivals.
List<LeagueEntry> standings({
  required int tier,
  required DateTime weekStart,
  required DateTime now,
  required int userXp,
}) {
  final all = [
    ...rivals(tier: tier, weekStart: weekStart, now: now),
    LeagueEntry('Sen', '⭐', userXp, isUser: true),
  ];
  all.sort((a, b) {
    final byXp = b.xp.compareTo(a.xp);
    if (byXp != 0) return byXp;
    return (b.isUser ? 1 : 0) - (a.isUser ? 1 : 0);
  });
  return all;
}

bool inPromotionZone(int tier, int rank) => tier < leagueTiers.length - 1 && rank <= promoteCount;
bool inDemotionZone(int tier, int rank) => tier > 0 && rank > leagueSize - demoteCount;

class LeagueResult {
  const LeagueResult({required this.oldTier, required this.newTier, required this.rank});
  final int oldTier;
  final int newTier;
  final int rank;

  bool get promoted => newTier > oldTier;
  bool get demoted => newTier < oldTier;

  Map<String, dynamic> toJson() => {'oldTier': oldTier, 'newTier': newTier, 'rank': rank};
  factory LeagueResult.fromJson(Map<String, dynamic> j) =>
      LeagueResult(oldTier: j['oldTier'] as int, newTier: j['newTier'] as int, rank: j['rank'] as int);
}

/// Final ranking of a finished week and the tier for next week.
/// A week with no XP at all never promotes.
LeagueResult finishWeek({required int tier, required DateTime weekStart, required int userXp}) {
  final end = weekStart.add(const Duration(days: 7));
  final table = standings(tier: tier, weekStart: weekStart, now: end, userXp: userXp);
  final rank = table.indexWhere((e) => e.isUser) + 1;
  var next = tier;
  if (userXp > 0 && inPromotionZone(tier, rank)) next = tier + 1;
  if (inDemotionZone(tier, rank)) next = tier - 1;
  return LeagueResult(oldTier: tier, newTier: next, rank: rank);
}
