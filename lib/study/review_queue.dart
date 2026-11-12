import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/practice.dart';
import '../data/progress.dart';
import '../models/course.dart';
import '../models/vocab.dart';

/// Word cards of the learning paths and today's review queue. Cards use the
/// spaced-repetition boxes of [Progress] (`wordBox`, `wordDue`).
///
/// * YDS path: the match pairs of `vocab: true` lessons, id `ydm_<word>`,
///   once the lesson is done (a bridge until `assets/vocab/yds.json`).
/// * General course: the match pairs of every finished lesson, `gm_<word>`.

const ydsWordPrefix = 'ydm_';
const generalWordPrefix = 'gm_';

/// Counter key ("day:newWords") of words started on a day.
const newWordsMetric = 'newWords';

/// New words a day when the plan does not say.
const defaultNewWordsPerDay = 20;

/// Cards that fit in a 30-minute review block (about 12 seconds a card).
/// More due cards than this make it a review day: fewer new words.
const reviewBudgetCards = 150;

String wordCardId(String prefix, String en) =>
    '$prefix${en.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_')}';

/// A word card: id, English, Turkish and an example sentence if any.
typedef WordCard = ({String id, String en, String tr, String? example});

/// YDS word cards (`assets/vocab/yds.json`, ids `yd_`), null until shipped.
Future<List<VocabEntry>?> loadYdsVocab(AssetBundle bundle) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    if (!manifest.listAssets().contains(ydsVocabAsset)) return null;
    return VocabBundle.fromJson(jsonDecode(await bundle.loadString(ydsVocabAsset)) as Map<String, dynamic>)
        .entries;
  } catch (e) {
    debugPrint('YDS kelime kartları okunamadı: $e');
    return null;
  }
}

const ydsVocabAsset = 'assets/vocab/yds.json';

final ydsVocabProvider = FutureProvider<List<VocabEntry>?>((ref) => loadYdsVocab(rootBundle));

/// Word cards [course] offers for the lessons done in [p], in path order.
/// On the YDS path, [ydsCards] (yds.json) join once a lesson of their
/// `topic` unit is done; match pairs of `vocab` lessons fill in the words
/// those cards do not cover.
/// With [everyUnit] (maintenance after the year plan) every unit's cards
/// are offered, reached or not.
List<WordCard> courseWordCards(
  Course course,
  Progress p, {
  List<VocabEntry> ydsCards = const [],
  bool everyUnit = false,
}) {
  final yds = course.id.startsWith('exam_yds');
  final prefix = yds ? ydsWordPrefix : generalWordPrefix;
  if (!yds && course.id.startsWith('exam_')) return const [];
  final seen = <String>{};
  final byTopic = <String, List<VocabEntry>>{};
  if (yds) {
    for (final e in ydsCards) {
      byTopic.putIfAbsent(e.topic, () => []).add(e);
    }
  }
  final result = <WordCard>[];
  for (final u in course.units) {
    final started = everyUnit || u.nodes.any((n) => n.type == NodeType.lesson && p.isDone(n.id));
    if (started) {
      for (final e in byTopic[u.id] ?? const <VocabEntry>[]) {
        if (e.senses.isEmpty || !seen.add(e.word.trim().toLowerCase())) continue;
        result.add((
          // A full card for a bridge word keeps the bridge card's key, so its
          // progress carries over (yds-faz2-icerik F2c).
          id: e.id.startsWith(ydsWordPrefix) ? wordCardId(ydsWordPrefix, e.word) : e.id,
          en: e.word,
          tr: e.senses.first.tr,
          example: e.examples.isEmpty ? null : e.examples.first.en,
        ));
      }
    }
    for (final n in u.nodes) {
      if (n.type != NodeType.lesson || (yds && !n.vocab) || !(everyUnit || p.isDone(n.id))) continue;
      for (final ex in n.exercises.where((e) => e.type == ExerciseType.match)) {
        for (final (tr, en) in ex.pairs) {
          if (seen.add(en.trim().toLowerCase())) {
            result.add((id: wordCardId(prefix, en), en: en, tr: tr, example: null));
          }
        }
      }
    }
  }
  return result;
}

class ReviewQueue {
  const ReviewQueue({
    required this.due,
    required this.fresh,
    required this.reviewDay,
    required this.mistakes,
  });

  /// Cards due today, most overdue first.
  final List<WordCard> due;

  /// New cards allowed today.
  final List<WordCard> fresh;

  /// Too many cards due: new words were cut ("Bugün tekrar günü").
  final bool reviewDay;

  /// Error notebook questions due today.
  final List<LessonItem> mistakes;

  List<WordCard> get cards => [...due, ...fresh];
  bool get isEmpty => due.isEmpty && fresh.isEmpty && mistakes.isEmpty;
}

/// Words started on [day].
int newWordsOn(Progress p, String day) => p.counters['$day:$newWordsMetric'] ?? 0;

/// Today's queue for [course]: due cards, then up to [newPerDay] new cards
/// (fewer on a review day), and the notebook questions due.
ReviewQueue reviewQueue(
  Course course,
  Progress p, {
  required String today,
  int newPerDay = defaultNewWordsPerDay,
  List<VocabEntry> ydsCards = const [],
  bool everyUnit = false,
}) {
  final cards = courseWordCards(course, p, ydsCards: ydsCards, everyUnit: everyUnit);
  final due = [
    for (final c in cards)
      if (p.wordDue[c.id] case final d? when d.compareTo(today) <= 0) c,
  ]..sort((a, b) => p.wordDue[a.id]!.compareTo(p.wordDue[b.id]!));
  final reviewDay = due.length > reviewBudgetCards;
  final allowed = (reviewDay ? newPerDay ~/ 4 : newPerDay) - newWordsOn(p, today);
  final fresh = [
    for (final c in cards)
      if (!p.wordBox.containsKey(c.id)) c,
  ].take(allowed.clamp(0, newPerDay)).toList();
  return ReviewQueue(
    due: due,
    fresh: fresh,
    reviewDay: reviewDay,
    mistakes: mistakeItems(course, p.mistakesDue(today), limit: 1000),
  );
}
