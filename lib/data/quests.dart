import 'dart:math';

import 'progress.dart';

/// What a daily quest counts.
enum QuestMetric { xp, lessons, perfectLessons, listen, translate, match }

class QuestDef {
  const QuestDef(this.id, this.metric, this.target, this.title, this.rewardXp);
  final String id;
  final QuestMetric metric;
  final int target;
  final String title;
  final int rewardXp;

  int progressOf(Progress p, DateTime day) => min(target, p.counter(day, metric));
  bool isComplete(Progress p, DateTime day) => p.counter(day, metric) >= target;
}

const _xpQuests = [
  QuestDef('xp20', QuestMetric.xp, 20, '20 XP kazan', 5),
  QuestDef('xp40', QuestMetric.xp, 40, '40 XP kazan', 10),
];

const _otherQuests = [
  QuestDef('lessons2', QuestMetric.lessons, 2, '2 ders bitir', 10),
  QuestDef('lessons3', QuestMetric.lessons, 3, '3 ders bitir', 15),
  QuestDef('perfect1', QuestMetric.perfectLessons, 1, 'Bir dersi hatasız bitir', 15),
  QuestDef('listen4', QuestMetric.listen, 4, '4 dinleme alıştırmasını doğru yap', 10),
  QuestDef('translate6', QuestMetric.translate, 6, '6 çeviriyi doğru yap', 10),
  QuestDef('match2', QuestMetric.match, 2, '2 eşleştirme tamamla', 10),
];

/// Stable string hash (FNV-1a) so the same day always gives the same quests.
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// Three quests for [day]: one XP quest plus two others, same all day.
List<QuestDef> questsForDay(DateTime day) {
  final rnd = Random(stableHash(dayKey(day)));
  final others = [..._otherQuests]..shuffle(rnd);
  return [_xpQuests[rnd.nextInt(_xpQuests.length)], ...others.take(2)];
}

/// Time left until quests refresh at local midnight.
Duration untilTomorrow(DateTime now) =>
    DateTime(now.year, now.month, now.day + 1).difference(now);
