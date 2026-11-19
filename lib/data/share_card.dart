import 'level_report.dart';
import 'placement.dart';
import 'progress.dart';
import 'vocab_practice.dart' show knownBox;

/// Paylaşım kartı: what the shareable image says, from the learner's own
/// progress. The milestone card (everyone) shows the newest level, the
/// streak and the words learned; the monthly card (Premium) adds the
/// month's active days, XP and the level change since the previous karne.

const _monthNames = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', //
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

String monthNameTr(int month) => _monthNames[month - 1];

class ShareCardData {
  const ShareCardData({
    required this.headline,
    required this.streak,
    required this.wordsLearned,
    this.level,
    this.previousLevel,
    this.month,
    this.activeDays = 0,
    this.monthXp = 0,
    this.dailyXp = const [],
  });

  /// Big line: "B1'e çıktım!", "Seviyem: A2", "30 günlük seri!".
  final String headline;
  final int streak;

  /// Words in the learner's review boxes that count as known.
  final int wordsLearned;

  /// Newest karne level (null: no karne yet or pre-A1).
  final Cefr? level;
  final Cefr? previousLevel;

  /// Monthly card only: "Kasım 2026".
  final String? month;
  final int activeDays;
  final int monthXp;

  /// XP per day of the month so far (monthly card's small chart).
  final List<int> dailyXp;

  bool get monthly => month != null;
  bool get leveledUp =>
      level != null && (previousLevel == null ? false : level!.index > previousLevel!.index);
}

/// "B1'e", "A2'ye", "C1'e": Turkish dative after a level code, by how the
/// last character is read aloud (bir, iki → -e / -ye).
String levelDative(Cefr level) => switch (level) {
  Cefr.a1 || Cefr.b1 || Cefr.c1 => "${level.code}'e",
  Cefr.a2 || Cefr.b2 => "${level.code}'ye",
};

/// The card for [p] at [now]; [monthly] adds the month's numbers.
ShareCardData buildShareCard(Progress p, DateTime now, {bool monthly = false}) {
  final reports = sortedReports(p.levelReports);
  final latest = reports.lastOrNull;
  final previous = reports.length > 1 ? reports[reports.length - 2] : null;
  final level = latest?.overall;
  final prevLevel = previous?.overall;
  final streak = p.streakAt(now);
  final words = p.wordBox.values.where((b) => b >= knownBox).length;
  final up = level != null && prevLevel != null && level.index > prevLevel.index;
  final headline = up
      ? '${levelDative(level)} çıktım!'
      : level != null
      ? 'Seviyem: ${level.code}'
      : streak >= 2
      ? '$streak günlük seri!'
      : "İngilizce'ye başladım!";
  if (!monthly) {
    return ShareCardData(
      headline: headline,
      streak: streak,
      wordsLearned: words,
      level: level,
      previousLevel: prevLevel,
    );
  }
  final prefix = '${now.year}-${now.month.toString().padLeft(2, '0')}-';
  final daily = [for (var d = 1; d <= now.day; d++) p.xpByDay['$prefix${d.toString().padLeft(2, '0')}'] ?? 0];
  return ShareCardData(
    headline: headline,
    streak: streak,
    wordsLearned: words,
    level: level,
    previousLevel: prevLevel,
    month: '${monthNameTr(now.month)} ${now.year}',
    activeDays: daily.where((x) => x > 0).length,
    monthXp: daily.fold(0, (a, b) => a + b),
    dailyXp: daily,
  );
}
