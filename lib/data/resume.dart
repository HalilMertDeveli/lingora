import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/course.dart';
import 'practice.dart';
import 'progress.dart';

/// "Kaldığın yerden devam": a small record of the lesson (or story) on
/// screen, so a lesson survives Android killing the app in the background.
///
/// Written when a session opens, after every answer and when the app goes to
/// the background; removed when the session finishes or the user quits it.
/// On a cold start [HomeScreen] reopens a recent record at the saved spot.
const resumeKey = 'resume_session_v1';

/// The selected bottom tab ([AppTab.name]), kept across process death.
const homeTabKey = 'home_tab_v1';

/// Older records are dropped: after half a day a fresh start is better.
const resumeMaxAge = Duration(hours: 12);

/// What a [LessonScreen] needs to rebuild itself at the same question.
///
/// Items are stored as their keys ("nodeId#index") and resolved against the
/// course on restore. The queue is the original items followed by the
/// re-queued ones, so `queue.take(total)` gives the screen's `items` back.
@immutable
class LessonSnapshot {
  const LessonSnapshot({
    required this.nodeId,
    required this.title,
    required this.color,
    required this.mode,
    required this.queue,
    required this.total,
    required this.pos,
    this.rewardXp = 0,
    this.badge,
    this.passHeadline,
    this.logSource,
    this.readingWords = 0,
    this.solved = 0,
    this.answered = 0,
    this.mistakes = 0,
    this.combo = 0,
    this.bestCombo = 0,
    this.questStats = const {},
    this.elapsedSeconds = 0,
    this.hearts,
    this.heartsLeft,
  });

  final String nodeId;
  final String title;
  final int color;
  final LessonMode mode;
  final List<String> queue;
  final int total;
  final int pos;
  final int rewardXp;
  final String? badge;
  final String? passHeadline;
  final String? logSource;
  final int readingWords;
  final int solved;
  final int answered;
  final int mistakes;
  final int combo;
  final int bestCombo;
  final Map<String, int> questStats;
  final int elapsedSeconds;

  /// Hearts of a skip exam (see lib/data/skip_exam.dart); null elsewhere.
  final int? hearts;

  /// Hearts the skip exam still had when it was saved.
  final int? heartsLeft;

  Map<String, Object?> toJson() => {
    'nodeId': nodeId,
    'title': title,
    'color': color,
    'mode': mode.name,
    'queue': queue,
    'total': total,
    'pos': pos,
    'rewardXp': rewardXp,
    'badge': ?badge,
    'passHeadline': ?passHeadline,
    'logSource': ?logSource,
    'readingWords': readingWords,
    'solved': solved,
    'answered': answered,
    'mistakes': mistakes,
    'combo': combo,
    'bestCombo': bestCombo,
    'questStats': questStats,
    'elapsedSeconds': elapsedSeconds,
    'hearts': ?hearts,
    'heartsLeft': ?heartsLeft,
  };

  /// Throws on a malformed record (the caller drops it).
  factory LessonSnapshot.fromJson(Map<String, dynamic> j) {
    final queue = [for (final k in j['queue'] as List) k as String];
    final total = j['total'] as int;
    final pos = j['pos'] as int;
    if (total <= 0 || total > queue.length || pos < 0 || pos > queue.length) {
      throw const FormatException('resume: bad queue');
    }
    final hearts = j['hearts'] as int?;
    final heartsLeft = j['heartsLeft'] as int?;
    if (hearts != null && (hearts <= 0 || heartsLeft == null || heartsLeft < 0 || heartsLeft > hearts)) {
      throw const FormatException('resume: bad hearts');
    }
    return LessonSnapshot(
      nodeId: j['nodeId'] as String,
      title: j['title'] as String,
      color: j['color'] as int,
      mode: LessonMode.values.byName(j['mode'] as String),
      queue: queue,
      total: total,
      pos: pos,
      rewardXp: j['rewardXp'] as int? ?? 0,
      badge: j['badge'] as String?,
      passHeadline: j['passHeadline'] as String?,
      logSource: j['logSource'] as String?,
      readingWords: j['readingWords'] as int? ?? 0,
      solved: j['solved'] as int? ?? 0,
      answered: j['answered'] as int? ?? 0,
      mistakes: j['mistakes'] as int? ?? 0,
      combo: j['combo'] as int? ?? 0,
      bestCombo: j['bestCombo'] as int? ?? 0,
      questStats: {
        for (final e in ((j['questStats'] as Map?) ?? const {}).entries) e.key as String: e.value as int,
      },
      elapsedSeconds: j['elapsedSeconds'] as int? ?? 0,
      hearts: hearts,
      heartsLeft: hearts == null ? null : heartsLeft,
    );
  }
}

/// What a [StoryScreen] needs to show the same step again.
@immutable
class StorySnapshot {
  const StorySnapshot({
    required this.nodeId,
    required this.color,
    this.shown = 0,
    this.picked,
    this.pickedRight,
    this.questions = 0,
    this.wrong = 0,
    this.revealed = false,
    this.rate = 1,
    this.elapsedSeconds = 0,
  });

  final String nodeId;
  final int color;
  final int shown;
  final String? picked;
  final bool? pickedRight;
  final int questions;
  final int wrong;
  final bool revealed;
  final double rate;
  final int elapsedSeconds;

  Map<String, Object?> toJson() => {
    'nodeId': nodeId,
    'color': color,
    'shown': shown,
    'picked': ?picked,
    'pickedRight': ?pickedRight,
    'questions': questions,
    'wrong': wrong,
    'revealed': revealed,
    'rate': rate,
    'elapsedSeconds': elapsedSeconds,
  };

  factory StorySnapshot.fromJson(Map<String, dynamic> j) {
    final shown = j['shown'] as int? ?? 0;
    if (shown < 0) throw const FormatException('resume: bad step');
    return StorySnapshot(
      nodeId: j['nodeId'] as String,
      color: j['color'] as int,
      shown: shown,
      picked: j['picked'] as String?,
      pickedRight: j['pickedRight'] as bool?,
      questions: j['questions'] as int? ?? 0,
      wrong: j['wrong'] as int? ?? 0,
      revealed: j['revealed'] as bool? ?? false,
      rate: (j['rate'] as num?)?.toDouble() ?? 1,
      elapsedSeconds: j['elapsedSeconds'] as int? ?? 0,
    );
  }
}

/// A saved session: exactly one of [lesson] and [story], for [trackId].
@immutable
class ResumeRecord {
  const ResumeRecord({required this.trackId, required this.savedAt, this.lesson, this.story})
    : assert((lesson == null) != (story == null));

  final String trackId;
  final DateTime savedAt;
  final LessonSnapshot? lesson;
  final StorySnapshot? story;

  String encode() => jsonEncode({
    'v': 1,
    'trackId': trackId,
    'savedAt': savedAt.millisecondsSinceEpoch,
    if (lesson != null) 'lesson': lesson!.toJson(),
    if (story != null) 'story': story!.toJson(),
  });

  /// Null when [raw] is not a valid record.
  static ResumeRecord? decode(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['v'] != 1) return null;
      final lesson = j['lesson'] == null
          ? null
          : LessonSnapshot.fromJson(j['lesson'] as Map<String, dynamic>);
      final story = j['story'] == null ? null : StorySnapshot.fromJson(j['story'] as Map<String, dynamic>);
      if ((lesson == null) == (story == null)) return null;
      return ResumeRecord(
        trackId: j['trackId'] as String,
        savedAt: DateTime.fromMillisecondsSinceEpoch(j['savedAt'] as int),
        lesson: lesson,
        story: story,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Reads and writes the [resumeKey] record.
class ResumeStore {
  ResumeStore(this._prefs, this._clock);
  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  /// The screen that wrote the record last (see [clearIfOwner]).
  Object? _owner;

  void save({required Object owner, required String trackId, LessonSnapshot? lesson, StorySnapshot? story}) {
    _owner = owner;
    final record = ResumeRecord(trackId: trackId, savedAt: _clock(), lesson: lesson, story: story);
    _prefs.setString(resumeKey, record.encode());
  }

  void clear() {
    _owner = null;
    _prefs.remove(resumeKey);
  }

  /// Clears the record only when [owner] wrote it: a screen closing after its
  /// replacement opened (a test's retry) must not remove the new record.
  void clearIfOwner(Object owner) {
    if (identical(_owner, owner)) clear();
  }

  bool get hasRecord => _prefs.containsKey(resumeKey);

  /// The saved session when there is a valid one younger than
  /// [resumeMaxAge]; anything else is removed and null returned.
  ResumeRecord? load() {
    final raw = _prefs.getString(resumeKey);
    if (raw == null) return null;
    final record = ResumeRecord.decode(raw);
    final age = record == null ? null : _clock().difference(record.savedAt);
    // A clock set back by more than the limit is as suspect as an old record.
    if (record == null || age!.abs() > resumeMaxAge) {
      clear();
      return null;
    }
    return record;
  }
}

final resumeStoreProvider = Provider<ResumeStore>(
  (ref) => ResumeStore(ref.watch(prefsProvider), ref.watch(clockProvider)),
);

/// A [LessonSnapshot] with its items resolved: the questions that were
/// re-queued after mistakes come after the screen's own items.
typedef LessonResume = ({LessonSnapshot snapshot, List<LessonItem> requeued});

/// Whether a session screen that is being disposed was closed in the
/// foreground (the user left it, so its record goes) rather than torn down
/// with the app in the background (the record stays for the next start).
bool closedInForeground() => switch (WidgetsBinding.instance.lifecycleState) {
  null || AppLifecycleState.resumed => true,
  _ => false,
};

/// The exercise behind [key] ("nodeId#index") in [nodes], or null.
Exercise? exerciseForKey(Map<String, PathNode> nodes, String key) {
  final hash = key.lastIndexOf('#');
  if (hash < 0) return null;
  final node = nodes[key.substring(0, hash)];
  final i = int.tryParse(key.substring(hash + 1));
  if (node == null || i == null || i < 0 || i >= node.exercises.length) return null;
  return node.exercises[i];
}

/// [keys] as lesson items from [course]; null when any of them is gone.
List<LessonItem>? resolveItems(Course course, List<String> keys) {
  final nodes = {for (final n in course.allNodes) n.id: n};
  final items = <LessonItem>[];
  for (final key in keys) {
    final ex = exerciseForKey(nodes, key);
    if (ex == null) return null;
    items.add((key: key, ex: ex));
  }
  return items;
}
