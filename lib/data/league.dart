import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'progress.dart';
import 'showcase_data.dart';
import 'quests.dart' show stableHash;

class LeagueTier {
  const LeagueTier(this.name, this.emoji, this.color);
  final String name;
  final String emoji;
  final Color color;
}

/// The ten Dünya Ligi tiers, lowest first (functions/src/league.ts uses the
/// same order).
const leagueTiers = [
  LeagueTier('Bronz', '🥉', Color(0xFFB0703C)),
  LeagueTier('Gümüş', '🥈', Color(0xFF8A94A6)),
  LeagueTier('Altın', '🥇', Color(0xFFE0A100)),
  LeagueTier('Safir', '🔷', Color(0xFF2F6FDB)),
  LeagueTier('Yakut', '♦️', Color(0xFFD12E4A)),
  LeagueTier('Zümrüt', '💚', Color(0xFF1FA971)),
  LeagueTier('Ametist', '🔮', Color(0xFF8E5BD8)),
  LeagueTier('İnci', '🦪', Color(0xFFB79C8A)),
  LeagueTier('Obsidyen', '🖤', Color(0xFF3B3F4A)),
  LeagueTier('Elmas', '💎', Color(0xFF2D9CDB)),
];

/// Learners per group.
const leagueSize = 100;

/// How many move up and down at the end of the week in a group of [size]
/// (the same rule as `zones` in functions/src/league.ts). A full group:
/// 15 up in Bronz–Altın, 10 above; nobody leaves Bronz downwards, 5 move
/// down from Gümüş–Yakut, 10 from Zümrüt up; Elmas is the top. Smaller
/// groups scale down.
({int promote, int demote}) leagueZones(int tier, [int size = leagueSize]) {
  final top = leagueTiers.length - 1;
  final promoteFull = tier >= top ? 0 : (tier <= 2 ? 15 : 10);
  final demoteFull = tier == 0 ? 0 : (tier <= 4 ? 5 : 10);
  final n = size.clamp(0, leagueSize);
  final promote = (n * promoteFull / leagueSize).ceil();
  final demote = min((n * demoteFull / leagueSize).floor(), n - promote);
  return (promote: promote, demote: max(0, demote));
}

/// Monday 00:00 of the week containing [d] (local time).
DateTime weekStart(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

Duration untilWeekEnd(DateTime now) => weekStart(now).add(const Duration(days: 7)).difference(now);

/// The Dünya Ligi week runs Monday 00:00 to Monday 00:00 Turkish time
/// (UTC+3), the same for every country (functions/src/week.ts).
const _trOffset = Duration(hours: 3);

/// Monday 00:00 Turkish time of the league week containing [now], as a
/// UTC instant.
DateTime trWeekStart(DateTime now) {
  final tr = now.toUtc().add(_trOffset);
  final monday = DateTime.utc(
    tr.year,
    tr.month,
    tr.day,
  ).subtract(Duration(days: tr.weekday - DateTime.monday));
  return monday.subtract(_trOffset);
}

/// "yyyy-mm-dd" of the Turkish Monday that starts the league week.
String trWeekKey(DateTime now) {
  final m = trWeekStart(now).add(_trOffset);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${m.year}-${two(m.month)}-${two(m.day)}';
}

Duration untilTrWeekEnd(DateTime now) =>
    trWeekStart(now).add(const Duration(days: 7)).difference(now.toUtc());

/// Flag emoji for an ISO 3166 alpha-2 code ("TR" -> 🇹🇷); empty when invalid.
String flagEmoji(String? code) {
  if (code == null || !RegExp(r'^[A-Z]{2}$').hasMatch(code)) return '';
  return String.fromCharCodes([for (final c in code.codeUnits) 0x1F1E6 + c - 0x41]);
}

class LeagueEntry {
  const LeagueEntry(
    this.name,
    this.avatar,
    this.xp, {
    this.isUser = false,
    this.uid,
    this.country,
    this.photo,
    this.look,
  });
  final String name;
  final String avatar;
  final int xp;
  final bool isUser;

  /// Server uid of a real league member; null for simulated rivals.
  final String? uid;

  /// ISO 3166 alpha-2 country code, shown as a flag.
  final String? country;

  /// Small JPEG the member chose to show in the league.
  final Uint8List? photo;

  /// Worn Mağaza items (Dünya Ligi members); null for simulated rivals.
  final Showcase? look;
}

const _firstNames = [
  'Ayşe', 'Mehmet', 'Elif', 'Can', 'Zeynep', 'Emre', 'Deniz', 'Selin', 'Burak', 'Ece', //
  'Kerem', 'Duru', 'Mert', 'İrem', 'Ali', 'Sena', 'Arda', 'Nehir', 'Kaan', 'Defne', //
  'Leyla', 'Murat', 'Aylin', 'Orhan', 'Nil', 'Tolga', 'Esra', 'Barış', 'Gizem', 'Onur', //
  'Lena', 'Jonas', 'Sofia', 'Lucas', 'Amira', 'Omar', 'Nora', 'Eldar', 'Aysel', 'Rauf', //
];
const _countries = ['TR', 'TR', 'TR', 'TR', 'DE', 'AZ', 'NL', 'GB', 'US', 'FR', 'AT', 'BE', 'KZ', 'CY', 'BG'];
const _avatars = [
  '🦊', '🐼', '🐨', '🐯', '🦁', '🐸', '🐵', '🐧', '🦉', '🐙', //
  '🦄', '🐢', '🐳', '🐝', '🦋', '🐞', '🐬', '🦔', '🐿️', '🦜', //
];

/// The 99 rivals of an offline league week. They are simulated on the
/// device (preview for guests, fallback without a connection): each gets a
/// weekly XP total that grows over the week. The same week and tier always
/// produce the same rivals.
List<LeagueEntry> rivals({required int tier, required DateTime weekStart, required DateTime now}) {
  final rnd = Random(stableHash('${dayKey(weekStart)}#$tier'));
  final elapsed = now.difference(weekStart).inMinutes / const Duration(days: 7).inMinutes;
  final frac = elapsed.clamp(0.0, 1.0);
  final scale = 1 + 0.35 * tier;

  return [
    for (var i = 0; i < leagueSize - 1; i++)
      () {
        final name =
            '${_firstNames[rnd.nextInt(_firstNames.length)]} ${String.fromCharCode(65 + rnd.nextInt(26))}.';
        final avatar = _avatars[rnd.nextInt(_avatars.length)];
        final country = _countries[rnd.nextInt(_countries.length)];
        // About one in four rivals barely plays.
        final active = rnd.nextDouble() > 0.25;
        final weekTotal = active ? (40 + rnd.nextInt(420)) * scale : rnd.nextInt(30).toDouble();
        final pace = 0.7 + rnd.nextDouble() * 0.7; // early birds vs. last-minute grinders
        return LeagueEntry(name, avatar, (weekTotal * pow(frac, pace)).round(), country: country);
      }(),
  ];
}

/// Everyone sorted by XP; on a tie the user ranks above rivals.
List<LeagueEntry> standings({
  required int tier,
  required DateTime weekStart,
  required DateTime now,
  required int userXp,
  String? userCountry,
}) {
  final all = [
    ...rivals(tier: tier, weekStart: weekStart, now: now),
    LeagueEntry('Sen', '⭐', userXp, isUser: true, country: userCountry),
  ];
  all.sort((a, b) {
    final byXp = b.xp.compareTo(a.xp);
    if (byXp != 0) return byXp;
    return (b.isUser ? 1 : 0) - (a.isUser ? 1 : 0);
  });
  return all;
}

bool inPromotionZone(int tier, int rank, [int size = leagueSize]) => rank <= leagueZones(tier, size).promote;
bool inDemotionZone(int tier, int rank, [int size = leagueSize]) =>
    rank > size - leagueZones(tier, size).demote;

class LeagueResult {
  const LeagueResult({required this.oldTier, required this.newTier, required this.rank, this.size, this.xp});
  final int oldTier;
  final int newTier;
  final int rank;

  /// Group size and weekly XP (Dünya Ligi results only).
  final int? size;
  final int? xp;

  bool get promoted => newTier > oldTier;
  bool get demoted => newTier < oldTier;

  Map<String, dynamic> toJson() => {'oldTier': oldTier, 'newTier': newTier, 'rank': rank};
  factory LeagueResult.fromJson(Map<String, dynamic> j) => LeagueResult(
    oldTier: (j['oldTier'] as int).clamp(0, leagueTiers.length - 1),
    newTier: (j['newTier'] as int).clamp(0, leagueTiers.length - 1),
    rank: j['rank'] as int,
    size: (j['size'] as num?)?.toInt(),
    xp: (j['xp'] as num?)?.toInt(),
  );
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
  return LeagueResult(oldTier: tier, newTier: next, rank: rank, size: table.length, xp: userXp);
}
