/// Everything the user can study. Courses use the learning path; exams use
/// question banks with topic practice and mini mock exams.
enum TrackKind { course, exam, notes, vocab }

class Track {
  const Track({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.emoji,
    this.badge,
    this.flag,
  });

  /// Asset name: `assets/courses/<id>.json` or `assets/exams/<id>.json`.
  final String id;
  final TrackKind kind;
  final String title;
  final String subtitle;
  final String emoji;

  /// Short label such as "MESLEK" or "SINAV".
  final String? badge;

  /// Flag image for language courses (shown instead of the emoji/icon).
  final String? flag;
}

const defaultTrackId = 'tr_en';

/// Course id of an exam track's study path: `assets/courses/exam_<id>.json`
/// plus its section files. A track without one keeps the question bank home.
String examPathId(String examTrackId) => 'exam_$examTrackId';

const courseCatalog = [
  Track(
    id: 'tr_en',
    kind: TrackKind.course,
    title: 'Genel İngilizce',
    subtitle: 'A1–C1, günlük hayattan iş hayatına',
    emoji: '🇬🇧',
    flag: 'assets/flags/gb.png',
  ),
  Track(
    id: 'pro_tourism',
    kind: TrackKind.course,
    title: 'Turizm İngilizcesi',
    subtitle: 'Resepsiyon, restoran, rehberlik',
    emoji: '🏨',
    badge: 'MESLEK',
  ),
  Track(
    id: 'pro_interview',
    kind: TrackKind.course,
    title: 'İş Görüşmesi İngilizcesi',
    subtitle: 'Kendini anlat, soruları yanıtla',
    emoji: '💼',
    badge: 'MESLEK',
  ),
];

/// Vocabulary tracks: knowledge map, triage and spaced review
/// (lib/screens/vocab/).
const vocabCatalog = [
  Track(
    id: 'pro_software',
    kind: TrackKind.vocab,
    title: 'Yazılımcı İngilizcesi',
    subtitle: 'Commit, PR, stand-up, mülakat kelimeleri',
    emoji: '💻',
    badge: 'MESLEK',
  ),
];

const examCatalog = [
  Track(
    id: 'yds',
    kind: TrackKind.exam,
    title: 'YDS / YÖKDİL',
    subtitle: 'Kelime, dil bilgisi, okuma',
    emoji: '🎓',
    badge: 'SINAV',
  ),
  Track(
    id: 'lgs',
    kind: TrackKind.exam,
    title: 'LGS İngilizce',
    subtitle: '8. sınıf konuları',
    emoji: '📝',
    badge: 'SINAV',
  ),
];

/// The user's own Notion notes, turned into study material.
const notesTrack = Track(
  id: 'notes',
  kind: TrackKind.notes,
  title: 'Notlarım',
  subtitle: "Notion'daki kendi notların: sözlük, gramer, günlük",
  emoji: '📒',
  badge: 'KİŞİSEL',
);

const allTracks = [...courseCatalog, ...vocabCatalog, ...examCatalog, notesTrack];

Track trackById(String id) => allTracks.firstWhere((t) => t.id == id, orElse: () => allTracks.first);
