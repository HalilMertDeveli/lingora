import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/legacy_emoji.dart';
import '../models/course.dart';
import 'catalog.dart';
import 'course_repository.dart';
import 'progress.dart';

/// "Kurslarım": how each track is presented on the course shelf (the
/// screen behind the top bar's course badge) and which tracks the learner
/// has on their shelf.

/// Presentation of a track on the shelf: its own colour, who it is for and
/// its level span. Static, so the shelf draws without loading any course.
class CourseLook {
  const CourseLook({
    required this.color,
    required this.short,
    required this.forWhom,
    required this.level,
    this.highlights = const [],
  });

  /// The track's own colour: card accents, badge tile, switch curtain.
  final Color color;

  /// Short name for the top bar badge ("YDS", "Turizm").
  final String short;

  /// One sentence: who the course is for.
  final String forWhom;

  /// Level span ("A1 → C1").
  final String level;

  /// What is inside, for tracks without a learning path (vocab, notes).
  /// Tracks with a path list their own sections instead.
  final List<String> highlights;
}

CourseLook courseLook(Track t) => switch (t.id) {
  'tr_en' => const CourseLook(
    color: Color(0xFF2F6FDE),
    short: 'Genel İngilizce',
    forWhom: 'Sıfırdan başlayıp günlük hayatta ve işte rahat konuşmak isteyenler için.',
    level: 'A1 → C1',
  ),
  'pro_tourism' => const CourseLook(
    color: Color(0xFF0E9384),
    short: 'Turizm',
    forWhom: 'Otelde, restoranda ve turda yabancı misafirle konuşanlar için.',
    level: 'A2 → B2',
  ),
  'pro_interview' => const CourseLook(
    color: Color(0xFF7048E8),
    short: 'İş görüşmesi',
    forWhom: 'İngilizce iş görüşmesine hazırlananlar için.',
    level: 'B1 → B2',
  ),
  'pro_dev' => const CourseLook(
    color: Color(0xFF2B8A3E),
    short: 'Yazılımcı',
    forWhom: 'Yazılım ekiplerinde İngilizce çalışan geliştiriciler için.',
    level: 'B1 → C1',
  ),
  'pro_software' => const CourseLook(
    color: Color(0xFF0B7285),
    short: 'Yazılım kelimeleri',
    forWhom: 'Yazılım dünyasının kelimelerini hızlıca öğrenmek isteyenler için.',
    level: 'B1+',
    highlights: ['Kelime haritası: bildiklerini ayıkla', 'Aralıklı tekrar kartları', 'Commit, PR, stand-up dili'],
  ),
  'yds' => const CourseLook(
    color: Color(0xFFD9480F),
    short: 'YDS / YÖKDİL',
    forWhom: 'YDS ve YÖKDİL sınavına hazırlananlar için.',
    level: 'B2 → C1',
  ),
  'lgs' => const CourseLook(
    color: Color(0xFFC2255C),
    short: 'LGS',
    forWhom: 'LGS İngilizce sorularına hazırlanan 8. sınıf öğrencileri için.',
    level: 'A2 · 8. sınıf',
  ),
  'notes' => const CourseLook(
    color: Color(0xFFB7791F),
    short: 'Notlarım',
    forWhom: 'Gramer notlarını ve kendi kelimelerini tekrar etmek isteyenler için.',
    level: 'Her seviye',
    highlights: ['Hazır gramer notları', 'Kendi notların ve kelimelerin', 'Notlardan pratik soruları'],
  ),
  _ => CourseLook(color: const Color(0xFF2F6FDE), short: t.title, forWhom: t.subtitle, level: ''),
};

/// Course id of [t]'s learning path, or null for tracks without one
/// (vocab, notes). Exam tracks use their study path (`exam_<id>`).
String? pathCourseId(Track t) => switch (t.kind) {
  TrackKind.course => t.id,
  TrackKind.exam => examPathId(t.id),
  _ => null,
};

/// The path outline of [t] for the shelf (see [loadCourseOutline]); null
/// for tracks without a path or without a readable outline.
final trackOutlineProvider = FutureProvider.family<Course?, String>((ref, trackId) async {
  final id = pathCourseId(trackById(trackId));
  if (id == null) return null;
  return loadCourseOutline(appBundle, id);
});

/// Done and total steps of a track's path.
typedef TrackStats = ({int done, int total});

/// [stats] as a 0–1 fraction.
double statsFraction(TrackStats s) => s.total == 0 ? 0 : s.done / s.total;

/// Steps done on [outline]'s path, counted from the learner's progress.
/// Node ids are unique across courses, so the count is per course.
TrackStats trackStats(Course outline, Progress p) {
  final nodes = outline.allNodes;
  return (done: nodes.where((n) => p.isDone(n.id)).length, total: nodes.length);
}

/// What the shelf remembers, stored under [CourseShelfNotifier.key] apart
/// from the learning progress.
@immutable
class CourseShelf {
  const CourseShelf({this.added = const [], this.lastStudied = const {}, this.hintArmed = true});

  /// Tracks the learner added with "Bu kursa başla", oldest first.
  final List<String> added;

  /// Last time each track was studied (milliseconds since epoch).
  final Map<String, int> lastStudied;

  /// The one-time "Kursunu buradan değiştirebilirsin" hint on the badge is
  /// waiting to be shown (on first start and after a course is added).
  final bool hintArmed;

  CourseShelf copyWith({List<String>? added, Map<String, int>? lastStudied, bool? hintArmed}) => CourseShelf(
    added: added ?? this.added,
    lastStudied: lastStudied ?? this.lastStudied,
    hintArmed: hintArmed ?? this.hintArmed,
  );

  Map<String, dynamic> toJson() => {'added': added, 'last': lastStudied, 'hint': hintArmed};

  factory CourseShelf.fromJson(Map<String, dynamic> j) => CourseShelf(
    added: (j['added'] as List?)?.cast<String>() ?? const [],
    lastStudied: (j['last'] as Map?)?.cast<String, int>() ?? const {},
    hintArmed: j['hint'] as bool? ?? true,
  );
}

class CourseShelfNotifier extends Notifier<CourseShelf> {
  static const key = 'course_shelf_v1';

  @override
  CourseShelf build() {
    // Whenever XP is earned, the selected track was just studied.
    ref.listen(progressProvider.select((p) => p.totalXp), (prev, next) {
      if (prev != null && next > prev) markStudied();
    });
    final raw = ref.read(prefsProvider).getString(key);
    if (raw == null) return const CourseShelf();
    try {
      return CourseShelf.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const CourseShelf();
    }
  }

  void _save(CourseShelf s) {
    state = s;
    ref.read(prefsProvider).setString(key, jsonEncode(s.toJson()));
  }

  /// Stamps the selected track as studied now. Also called after the
  /// onboarding first lesson, which can end before this notifier listens.
  void markStudied() {
    final id = ref.read(progressProvider).trackId;
    final now = ref.read(clockProvider)().millisecondsSinceEpoch;
    _save(state.copyWith(lastStudied: {...state.lastStudied, id: now}));
  }

  /// Puts [trackId] on the shelf, selects it and arms the badge hint.
  void add(String trackId) {
    _save(state.copyWith(added: state.added.contains(trackId) ? null : [...state.added, trackId], hintArmed: true));
    ref.read(progressProvider.notifier).setTrack(trackId);
  }

  /// Keeps [trackId] on the shelf (the course left when switching), so it
  /// stays under "Devam ettiğin kurslar" even before any progress.
  void keep(String trackId) {
    if (!state.added.contains(trackId)) _save(state.copyWith(added: [...state.added, trackId]));
  }

  /// The badge hint was shown (or the badge used): not again until the next
  /// course is added.
  void hintDone() {
    if (state.hintArmed) _save(state.copyWith(hintArmed: false));
  }
}

final courseShelfProvider = NotifierProvider<CourseShelfNotifier, CourseShelf>(CourseShelfNotifier.new);

/// Ids of the tracks the learner is following: the selected one, the ones
/// added from the shelf and any with progress on their path. Ordered by
/// last study time, most recent first; the selected track always first.
List<String> followedTrackIds({
  required String current,
  required CourseShelf shelf,
  required Set<String> withProgress,
}) {
  final known = {for (final t in allTracks) t.id};
  final ids = {current, ...shelf.added, ...withProgress}.where(known.contains).toList();
  int last(String id) => shelf.lastStudied[id] ?? 0;
  ids.sort((a, b) {
    if (a == current) return -1;
    if (b == current) return 1;
    final byTime = last(b).compareTo(last(a));
    if (byTime != 0) return byTime;
    return allTracks.indexWhere((t) => t.id == a).compareTo(allTracks.indexWhere((t) => t.id == b));
  });
  return ids;
}

/// "Bugün", "Dün", "3 gün önce"… for a last study time.
String lastStudiedLabel(int? millis, DateTime now) {
  if (millis == null) return 'Henüz çalışılmadı';
  final then = DateTime.fromMillisecondsSinceEpoch(millis);
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(then.year, then.month, then.day)).inDays;
  if (days <= 0) return 'Son çalışma: bugün';
  if (days == 1) return 'Son çalışma: dün';
  if (days < 7) return 'Son çalışma: $days gün önce';
  if (days < 30) return 'Son çalışma: ${days ~/ 7} hafta önce';
  return 'Son çalışma: ${days ~/ 30} ay önce';
}
