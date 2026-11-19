import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/level_report.dart';
import '../../data/placement.dart' show Cefr;
import '../../data/progress.dart';
import '../firebase/firebase_providers.dart';

/// "Günün okuması": a short original text per CEFR band, written once a day
/// by the generateDailyReadings Cloud Function into
/// `daily/{yyyy-mm-dd}/levels/{A1..C1}`. The last [keepDays] days stay on
/// the phone for offline reading.

const dailyReadingLevels = ['A1', 'A2', 'B1', 'B2', 'C1'];

class DailyGloss {
  const DailyGloss({required this.word, required this.meaningTr, this.example = ''});
  final String word;
  final String meaningTr;
  final String example;

  factory DailyGloss.fromJson(Map<String, dynamic> j) => DailyGloss(
    word: j['word'] as String? ?? '',
    meaningTr: j['meaning_tr'] as String? ?? '',
    example: j['example'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'word': word, 'meaning_tr': meaningTr, 'example': example};
}

class DailyQuestion {
  const DailyQuestion({
    required this.question,
    required this.options,
    required this.answer,
    this.explanationTr = '',
  });
  final String question;
  final List<String> options;
  final int answer;
  final String explanationTr;

  factory DailyQuestion.fromJson(Map<String, dynamic> j) => DailyQuestion(
    question: j['question'] as String? ?? '',
    options: [for (final o in j['options'] as List<dynamic>? ?? const []) '$o'],
    answer: (j['answer'] as num?)?.toInt() ?? 0,
    explanationTr: j['explanation_tr'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'question': question,
    'options': options,
    'answer': answer,
    'explanation_tr': explanationTr,
  };
}

class DailyReading {
  const DailyReading({
    required this.date,
    required this.level,
    required this.title,
    required this.text,
    this.kind = 'story',
    this.summaryTr = '',
    this.glossary = const [],
    this.questions = const [],
    this.talkPrompt = '',
  });

  /// "2026-11-19" (Turkish calendar day).
  final String date;
  final String level;
  final String kind;
  final String title;
  final String text;
  final String summaryTr;
  final List<DailyGloss> glossary;
  final List<DailyQuestion> questions;
  final String talkPrompt;

  String get id => '${date}_$level';

  bool get valid =>
      title.isNotEmpty &&
      text.isNotEmpty &&
      questions.every((q) => q.options.length >= 2 && q.answer >= 0 && q.answer < q.options.length);

  factory DailyReading.fromJson(Map<String, dynamic> j) => DailyReading(
    date: j['date'] as String? ?? '',
    level: j['level'] as String? ?? '',
    kind: j['kind'] as String? ?? 'story',
    title: j['title'] as String? ?? '',
    text: j['text'] as String? ?? '',
    summaryTr: j['summary_tr'] as String? ?? '',
    glossary: [
      for (final g in j['glossary'] as List<dynamic>? ?? const [])
        if (g is Map) DailyGloss.fromJson(g.cast<String, dynamic>()),
    ],
    questions: [
      for (final q in j['questions'] as List<dynamic>? ?? const [])
        if (q is Map) DailyQuestion.fromJson(q.cast<String, dynamic>()),
    ],
    talkPrompt: j['talk_prompt'] as String? ?? '',
  );

  /// Only plain JSON (Firestore timestamps are dropped).
  Map<String, dynamic> toJson() => {
    'date': date,
    'level': level,
    'kind': kind,
    'title': title,
    'text': text,
    'summary_tr': summaryTr,
    'glossary': [for (final g in glossary) g.toJson()],
    'questions': [for (final q in questions) q.toJson()],
    'talk_prompt': talkPrompt,
  };
}

/// Turkish calendar day ("2026-11-19") of [now]; Türkiye is UTC+3 all year.
String trDayKey(DateTime now) => dayKey(now.toUtc().add(const Duration(hours: 3)));

/// Where the readings come from; Firestore in the app, a fake in tests.
abstract class DailyReadingSource {
  /// Null when that day/level was not written (yet).
  Future<DailyReading?> fetch(String date, String level);
}

class FirestoreDailyReadingSource implements DailyReadingSource {
  FirestoreDailyReadingSource(this._db);
  final FirebaseFirestore _db;

  @override
  Future<DailyReading?> fetch(String date, String level) async {
    final snap = await _db.doc('daily/$date/levels/$level').get().timeout(const Duration(seconds: 8));
    final data = snap.data();
    if (data == null) return null;
    final r = DailyReading.fromJson(data);
    return r.valid ? r : null;
  }
}

final dailyReadingSourceProvider = Provider<DailyReadingSource?>((ref) {
  final db = ref.watch(firestoreProvider);
  if (db == null || ref.watch(currentUidProvider) == null) return null;
  return FirestoreDailyReadingSource(db);
});

/// Offline copy of the last [keepDays] days (all bands fetched).
class DailyReadingCache {
  DailyReadingCache(this._prefs);
  final SharedPreferences _prefs;

  static const key = 'growth.daily_reading.cache';
  static const keepDays = 5;

  Map<String, DailyReading> _all() {
    final raw = _prefs.getString(key);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in m.entries)
          if (e.value is Map) e.key: DailyReading.fromJson((e.value as Map).cast<String, dynamic>()),
      };
    } on Object {
      return {};
    }
  }

  void put(DailyReading r, String today) {
    final all = _all()..[r.id] = r;
    final days = {for (final x in all.values) x.date}.toList()..sort();
    final keep = days.where((d) => d.compareTo(today) <= 0).toList().reversed.take(keepDays).toSet();
    all.removeWhere((_, x) => !keep.contains(x.date));
    _prefs.setString(key, jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}));
  }

  /// The newest cached reading of [level] on or before [today].
  DailyReading? latest(String level, String today) {
    final list = _all().values.where((r) => r.level == level && r.date.compareTo(today) <= 0).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list.firstOrNull;
  }

  /// Every cached reading of [level], newest first.
  List<DailyReading> history(String level) =>
      _all().values.where((r) => r.level == level).toList()..sort((a, b) => b.date.compareTo(a.date));
}

final dailyReadingCacheProvider = Provider<DailyReadingCache>(
  (ref) => DailyReadingCache(ref.watch(prefsProvider)),
);

/// The band suggested for the learner: the last Seviye Karnesi, else a guess
/// from the track (YDS → B2, LGS → A2), else A2.
String suggestedDailyLevel(Progress p) {
  final reports = sortedReports(p.levelReports);
  final measured = reports.isEmpty ? null : reports.last.overall;
  if (measured != null) return measured.code;
  return switch (p.trackId) {
    'yds' => Cefr.b2.code,
    'lgs' => Cefr.a2.code,
    _ => Cefr.a2.code,
  };
}

/// The band the learner reads: their own pick, else [suggestedDailyLevel].
class DailyLevelNotifier extends Notifier<String> {
  static const key = 'growth.daily_reading.level';

  @override
  String build() {
    final picked = ref.read(prefsProvider).getString(key);
    if (picked != null && dailyReadingLevels.contains(picked)) return picked;
    return suggestedDailyLevel(ref.watch(progressProvider));
  }

  void pick(String level) {
    if (!dailyReadingLevels.contains(level)) return;
    ref.read(prefsProvider).setString(key, level);
    state = level;
  }
}

final dailyLevelProvider = NotifierProvider<DailyLevelNotifier, String>(DailyLevelNotifier.new);

/// Today's reading for the learner's band. Before today's is written (just
/// after midnight) or offline, the newest one on the phone.
final dailyReadingProvider = FutureProvider<DailyReading?>((ref) async {
  final level = ref.watch(dailyLevelProvider);
  final now = ref.read(clockProvider)();
  final today = trDayKey(now);
  final cache = ref.read(dailyReadingCacheProvider);
  final source = ref.watch(dailyReadingSourceProvider);
  if (source != null) {
    final yesterday = trDayKey(now.subtract(const Duration(days: 1)));
    for (final day in [today, yesterday]) {
      final cached = cache.latest(level, day);
      if (cached != null && cached.date == day) return cached;
      try {
        final r = await source.fetch(day, level);
        if (r != null) {
          cache.put(r, today);
          return r;
        }
      } on Object {
        break; // offline: fall back to the phone's copy
      }
    }
  }
  return cache.latest(level, today);
});

/// Readings finished (questions answered), by [DailyReading.id].
class DailyReadDone extends Notifier<Set<String>> {
  static const key = 'growth.daily_reading.done';

  @override
  Set<String> build() => (ref.read(prefsProvider).getStringList(key) ?? const []).toSet();

  void mark(DailyReading r) {
    if (state.contains(r.id)) return;
    // Keep the list short: only ids of the last weeks matter.
    final next = {...state, r.id}.toList()..sort();
    final kept = next.length > 40 ? next.sublist(next.length - 40) : next;
    ref.read(prefsProvider).setStringList(key, kept);
    state = kept.toSet();
  }
}

final dailyReadDoneProvider = NotifierProvider<DailyReadDone, Set<String>>(DailyReadDone.new);
