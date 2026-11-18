import 'dart:math';

import '../models/course.dart';
import 'placement.dart';

/// Seviye Karnesi: a monthly level test (about 15 minutes) and the report
/// it writes. Questions come from the placement bank (grammar, vocabulary,
/// reading) and from the general course's listening dialogues; nothing new
/// is invented and the grammar path is not touched.
///
/// The result is an *estimate*: per skill it is the level of a short
/// adaptive staircase (see [estimateSkillLevel]), overall it is the median
/// of the skills that were actually measured. The report keeps only what
/// was measured: right answers out of asked questions, per skill.

/// Skills the monthly test measures.
enum LevelSkill {
  grammar('Dil bilgisi', 'DİL BİLGİSİ', '🧩'),
  vocabulary('Kelime', 'KELİME', '🔤'),
  reading('Okuma', 'OKUMA', '📖'),
  listening('Dinleme', 'DİNLEME', '🎧');

  const LevelSkill(this.title, this.caps, this.emoji);
  final String title;

  /// [title] in capitals with the Turkish dotted İ (Dart's toUpperCase
  /// would give "DIL").
  final String caps;
  final String emoji;
}

/// Days between two monthly tests.
const levelTestCooldownDays = 30;

/// Questions per skill in one test (4 skills × 4 = 16, about 15 minutes with
/// the reading passages and the listening dialogues).
const levelTestPerSkill = 4;

/// Reports kept on the device and in the cloud (three years of months).
const levelReportsKept = 36;

/// One question of the monthly test.
class LevelItem {
  const LevelItem({
    required this.id,
    required this.level,
    required this.skill,
    required this.prompt,
    required this.choices,
    required this.answer,
    this.passage,
    this.explanation,
    this.listening,
  });

  final String id;
  final Cefr level;
  final LevelSkill skill;
  final String prompt;
  final List<String> choices;

  /// Index of the correct choice.
  final int answer;

  /// Text to read first (reading).
  final String? passage;
  final String? explanation;

  /// Dialogue to hear first (listening). Its transcript is not shown.
  final ListeningPiece? listening;

  factory LevelItem.fromPlacement(PlacementQuestion q) => LevelItem(
    id: q.id,
    level: q.level,
    skill: switch (q.skill) {
      PlacementSkill.grammar => LevelSkill.grammar,
      PlacementSkill.vocabulary => LevelSkill.vocabulary,
      PlacementSkill.reading => LevelSkill.reading,
    },
    prompt: q.prompt,
    choices: q.choices,
    answer: q.answer,
    passage: q.passage,
    explanation: q.explanation,
  );

  /// One question of a listening node: its first multiple-choice question
  /// (true/false as a fallback; "who said it" needs the transcript feel and
  /// is skipped). Null when the node has no usable question or level.
  static LevelItem? fromListening(PathNode node) {
    final piece = node.listening;
    if (piece == null) return null;
    final level = Cefr.values.where((c) => c.code == (node.cefr ?? piece.cefr)).firstOrNull;
    if (level == null) return null;
    final q =
        piece.questions.where((q) => q.kind == ListeningQuestionKind.choice).firstOrNull ??
        piece.questions.where((q) => q.kind == ListeningQuestionKind.trueFalse).firstOrNull;
    if (q == null) return null;
    final answer = q.choices.indexOf(q.answer);
    if (answer < 0) return null;
    return LevelItem(
      id: 'lis_${node.id}',
      level: level,
      skill: LevelSkill.listening,
      prompt: q.prompt,
      choices: q.choices,
      answer: answer,
      listening: piece,
    );
  }
}

/// Listening items of a course: one per listening node.
List<LevelItem> listeningItems(Iterable<PathNode> nodes) => [
  for (final n in nodes) ?LevelItem.fromListening(n),
];

/// Estimated level from one skill's answers (item level, right?): the
/// highest level L for which at least half of the answers to questions at L
/// or above are right. Null when not even A1 reaches that (pre-A1) or when
/// nothing was answered.
Cefr? estimateSkillLevel(List<(Cefr, bool)> answers) {
  for (final level in Cefr.values.reversed) {
    final at = answers.where((a) => a.$1.index >= level.index).toList();
    if (at.isEmpty) continue;
    final right = at.where((a) => a.$2).length;
    if (right > 0 && right * 2 >= at.length) return level;
  }
  return null;
}

/// Overall estimate: the median of the measured skills, the lower one of the
/// two middles (pre-A1 counts below A1). Null for pre-A1 or nothing measured.
Cefr? overallLevel(Iterable<Cefr?> skills) {
  final ranks = [for (final s in skills) s?.index ?? -1]..sort();
  if (ranks.isEmpty) return null;
  final mid = ranks[(ranks.length - 1) ~/ 2];
  return mid < 0 ? null : Cefr.values[mid];
}

/// One skill's line on the report.
class SkillScore {
  const SkillScore({required this.level, required this.right, required this.total});

  /// Null: below A1.
  final Cefr? level;
  final int right;
  final int total;

  Map<String, dynamic> toJson() => {'level': level?.code, 'right': right, 'total': total};

  factory SkillScore.fromJson(Map<String, dynamic> j) => SkillScore(
    level: j['level'] == null ? null : Cefr.values.where((c) => c.code == j['level']).firstOrNull,
    right: (j['right'] as num?)?.toInt() ?? 0,
    total: (j['total'] as num?)?.toInt() ?? 0,
  );
}

/// The result of one monthly test.
class LevelReport {
  const LevelReport({required this.day, required this.overall, required this.skills, this.seconds = 0});

  /// `dayKey` of the test day; also the report's id.
  final String day;

  /// Null: below A1 (or nothing measured).
  final Cefr? overall;

  /// Only the skills that were measured.
  final Map<LevelSkill, SkillScore> skills;
  final int seconds;

  int get right => skills.values.fold(0, (a, s) => a + s.right);
  int get total => skills.values.fold(0, (a, s) => a + s.total);

  DateTime get date => DateTime.parse(day);

  Map<String, dynamic> toJson() => {
    'day': day,
    'overall': overall?.code,
    'skills': {for (final e in skills.entries) e.key.name: e.value.toJson()},
    'seconds': seconds,
  };

  factory LevelReport.fromJson(Map<String, dynamic> j) {
    final raw = (j['skills'] as Map?) ?? const {};
    return LevelReport(
      day: j['day'] as String,
      overall: j['overall'] == null ? null : Cefr.values.where((c) => c.code == j['overall']).firstOrNull,
      skills: {
        for (final s in LevelSkill.values)
          if (raw[s.name] case final Map m) s: SkillScore.fromJson(Map<String, dynamic>.from(m)),
      },
      seconds: (j['seconds'] as num?)?.toInt() ?? 0,
    );
  }
}

/// "A1 öncesi" for null, else the CEFR code.
String levelLabel(Cefr? level) => level?.code ?? 'A1 öncesi';

/// Rank used by charts: pre-A1 is 0, A1 is 1 … C1 is 5.
int levelRank(Cefr? level) => level == null ? 0 : level.index + 1;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Reports sorted oldest first.
List<LevelReport> sortedReports(Iterable<LevelReport> reports) =>
    [...reports]..sort((a, b) => a.day.compareTo(b.day));

/// Day the next test opens, or null when none was taken yet.
DateTime? nextLevelTestDay(List<LevelReport> reports) {
  if (reports.isEmpty) return null;
  final last = sortedReports(reports).last.date;
  return _dateOnly(last).add(const Duration(days: levelTestCooldownDays));
}

/// Whether a test may be taken on [now]: once per [levelTestCooldownDays].
bool canTakeLevelTest(List<LevelReport> reports, DateTime now) {
  final next = nextLevelTestDay(reports);
  return next == null || !_dateOnly(now).isBefore(next);
}

/// Whole days until the next test (0 when it is open).
int daysUntilLevelTest(List<LevelReport> reports, DateTime now) {
  final next = nextLevelTestDay(reports);
  if (next == null) return 0;
  return max(0, next.difference(_dateOnly(now)).inDays);
}

/// Merges two report lists (device and cloud): one report per day, the one
/// with more answers on a clash, newest [levelReportsKept] kept.
List<LevelReport> mergeLevelReports(List<LevelReport> a, List<LevelReport> b) {
  final byDay = <String, LevelReport>{};
  for (final r in [...a, ...b]) {
    final have = byDay[r.day];
    if (have == null || r.total > have.total) byDay[r.day] = r;
  }
  final all = sortedReports(byDay.values);
  return all.length <= levelReportsKept ? all : all.sublist(all.length - levelReportsKept);
}

/// Change of one skill since the previous report (in CEFR steps); null when
/// the skill was not measured in both.
int? skillChange(LevelReport current, LevelReport? previous, LevelSkill skill) {
  final now = current.skills[skill];
  final before = previous?.skills[skill];
  if (now == null || before == null) return null;
  return levelRank(now.level) - levelRank(before.level);
}

/// What to study next month: up to two weakest measured skills, each with
/// the level to aim at (one above the measured one, C1 at most).
class StudySuggestion {
  const StudySuggestion(this.skill, this.target);
  final LevelSkill skill;
  final Cefr target;
}

List<StudySuggestion> studySuggestions(LevelReport report, {int count = 2}) {
  final entries = report.skills.entries.toList()
    ..sort((a, b) {
      final byLevel = levelRank(a.value.level).compareTo(levelRank(b.value.level));
      if (byLevel != 0) return byLevel;
      // Same level: fewer right answers first.
      final ar = a.value.total == 0 ? 0.0 : a.value.right / a.value.total;
      final br = b.value.total == 0 ? 0.0 : b.value.right / b.value.total;
      return ar.compareTo(br);
    });
  return [
    for (final e in entries.take(count))
      StudySuggestion(e.key, Cefr.values[min(levelRank(e.value.level), Cefr.values.length - 1)]),
  ];
}

/// One run of the monthly test. Each skill has its own staircase: it starts
/// at [start] (last month's level for that skill, else the placement level,
/// else A2), moves one level up after a right answer and one down after a
/// wrong one. Skills take turns: grammar, vocabulary, reading, listening.
class LevelTestSession {
  LevelTestSession(
    List<LevelItem> bank, {
    Map<LevelSkill, Cefr> start = const {},
    Cefr fallbackStart = Cefr.a2,
    this.perSkill = levelTestPerSkill,
    int seed = 0,
  }) : bank = [...bank]..shuffle(Random(seed)) {
    for (final s in LevelSkill.values) {
      if (this.bank.any((q) => q.skill == s)) _level[s] = start[s] ?? fallbackStart;
    }
    _schedule = [
      for (var i = 0; i < perSkill; i++)
        for (final s in LevelSkill.values)
          if (_level.containsKey(s)) s,
    ];
    _current = _pick();
  }

  /// The bank in this run's order (shuffled by the seed, so each month asks
  /// in a different order).
  final List<LevelItem> bank;
  final int perSkill;
  final Map<LevelSkill, Cefr> _level = {};
  late List<LevelSkill> _schedule;
  final List<(LevelItem, bool)> answers = [];
  final Set<LevelSkill> skipped = {};
  LevelItem? _current;

  LevelItem? get current => _current;

  /// Questions planned in total (shrinks when a skill is skipped).
  int get planned => answers.length + _schedule.length;

  bool get isFinished => _current == null;

  /// Records the answer to [current]. Returns whether it was right.
  bool answer(int choice) {
    final q = _current;
    if (q == null) throw StateError('No question to answer');
    final ok = choice == q.answer;
    answers.add((q, ok));
    final i = q.level.index + (ok ? 1 : -1);
    _level[q.skill] = Cefr.values[i.clamp(0, Cefr.values.length - 1)];
    _schedule.removeAt(0);
    _current = _pick();
    return ok;
  }

  /// Drops [skill] from this test (e.g. no sound right now). Its answers so
  /// far are discarded, so the report does not claim it was measured.
  void skip(LevelSkill skill) {
    skipped.add(skill);
    answers.removeWhere((a) => a.$1.skill == skill);
    _schedule.removeWhere((s) => s == skill);
    _current = _pick();
  }

  LevelItem? _pick() {
    while (_schedule.isNotEmpty) {
      final skill = _schedule.first;
      final level = _level[skill]!;
      final asked = {for (final a in answers) a.$1.id, if (_current != null) _current!.id};
      // Nearest level with an unasked question, the lower one first.
      for (var d = 0; d < Cefr.values.length; d++) {
        for (final i in {level.index - d, level.index + d}) {
          if (i < 0 || i >= Cefr.values.length) continue;
          final q = bank
              .where((q) => q.skill == skill && q.level.index == i && !asked.contains(q.id))
              .firstOrNull;
          if (q != null) return q;
        }
      }
      // This skill ran out of questions.
      _schedule.removeAt(0);
    }
    return null;
  }

  /// Answers of one skill as (level, right?).
  List<(Cefr, bool)> answersOf(LevelSkill skill) => [
    for (final (q, ok) in answers)
      if (q.skill == skill) (q.level, ok),
  ];

  /// The report of this run, dated [day].
  LevelReport report(String day, {int seconds = 0}) {
    final skills = <LevelSkill, SkillScore>{
      for (final s in LevelSkill.values)
        if (answersOf(s) case final a when a.isNotEmpty)
          s: SkillScore(level: estimateSkillLevel(a), right: a.where((x) => x.$2).length, total: a.length),
    };
    return LevelReport(
      day: day,
      overall: overallLevel([for (final s in skills.values) s.level]),
      skills: skills,
      seconds: seconds,
    );
  }
}

/// Turkish month name for chart labels.
const monthNamesTr = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
const monthNamesTrLong = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// "18 Kasım 2026".
String longDateTr(DateTime d) => '${d.day} ${monthNamesTrLong[d.month - 1]} ${d.year}';
