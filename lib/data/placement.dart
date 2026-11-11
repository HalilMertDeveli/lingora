import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/grammar_lesson.dart';
import 'catalog.dart';
import 'progress.dart';
import 'sections.dart';

/// CEFR levels covered by the placement test, lowest first.
enum Cefr {
  a1('A1', 'Başlangıç'),
  a2('A2', 'Temel'),
  b1('B1', 'Orta'),
  b2('B2', 'İleri orta'),
  c1('C1', 'İleri');

  const Cefr(this.code, this.name);
  final String code;
  final String name;

  static Cefr byCode(String code) => values.firstWhere((l) => l.code == code);
}

enum PlacementSkill { grammar, vocabulary, reading }

class PlacementQuestion {
  const PlacementQuestion({
    required this.id,
    required this.level,
    required this.skill,
    required this.prompt,
    required this.choices,
    required this.answer,
    required this.explanation,
    this.passage,
  });

  final String id;
  final Cefr level;
  final PlacementSkill skill;

  /// Short English text to read first (reading questions).
  final String? passage;
  final String prompt;
  final List<String> choices;

  /// Index of the correct choice.
  final int answer;

  /// Why the answer is right, in Turkish.
  final String explanation;

  factory PlacementQuestion.fromJson(Map<String, dynamic> j) => PlacementQuestion(
    id: j['id'] as String,
    level: Cefr.byCode(j['level'] as String),
    skill: PlacementSkill.values.byName(j['skill'] as String),
    passage: j['passage'] as String?,
    prompt: j['prompt'] as String,
    choices: (j['choices'] as List).cast<String>(),
    answer: j['answer'] as int,
    explanation: j['explanation'] as String,
  );
}

List<PlacementQuestion> parsePlacementBank(String raw) =>
    (jsonDecode(raw) as List).map((q) => PlacementQuestion.fromJson(q as Map<String, dynamic>)).toList();

final placementBankProvider = FutureProvider<List<PlacementQuestion>>(
  (ref) async => parsePlacementBank(await rootBundle.loadString('assets/placement/questions.json')),
);

/// Most questions in one test.
const placementMaxQuestions = 14;

/// The test may end here once the level has settled.
const placementMinQuestions = 12;

/// Questions in a row at one level that count as "settled".
const placementSettleRun = 6;

const placementStartLevel = Cefr.a2;

/// One adaptive placement test. Starts at A2, moves one level up after a
/// correct answer and one down after a wrong one, rotating skills.
class PlacementSession {
  PlacementSession(this.bank) : _level = placementStartLevel {
    _current = _pick();
  }

  final List<PlacementQuestion> bank;
  final List<(PlacementQuestion, bool)> answers = [];
  Cefr _level;
  PlacementQuestion? _current;

  PlacementQuestion? get current => _current;

  /// Level the next question is aimed at.
  Cefr get level => _level;

  bool get isFinished {
    if (_current == null || answers.length >= placementMaxQuestions) return true;
    if (answers.length < placementMinQuestions) return false;
    final tail = answers.sublist(answers.length - placementSettleRun);
    return tail.every((a) => a.$1.level == tail.first.$1.level);
  }

  /// Records the answer to [current] and moves on. Returns whether it was right.
  bool answer(int choice) {
    final q = _current;
    if (q == null || isFinished) throw StateError('No question to answer');
    final ok = choice == q.answer;
    answers.add((q, ok));
    final i = q.level.index + (ok ? 1 : -1);
    _level = Cefr.values[i.clamp(0, Cefr.values.length - 1)];
    _current = _pick();
    return ok;
  }

  PlacementQuestion? _pick() {
    final asked = {for (final a in answers) a.$1.id};
    final lastSkill = answers.isEmpty ? null : answers.last.$1.skill;
    // Nearest level that still has questions, preferring the lower one.
    final order = [
      for (var d = 0; d < Cefr.values.length; d++)
        for (final i in {_level.index - d, _level.index + d})
          if (i >= 0 && i < Cefr.values.length) Cefr.values[i],
    ];
    for (final level in order) {
      final left = [
        for (final q in bank)
          if (q.level == level && !asked.contains(q.id)) q,
      ];
      if (left.isEmpty) continue;
      return left.firstWhere((q) => q.skill != lastSkill, orElse: () => left.first);
    }
    return null;
  }

  /// Estimated level; null means "start from scratch".
  Cefr? get estimate => estimateLevel([for (final (q, ok) in answers) (q.level, ok)]);
}

/// Highest level with at least two correct answers and a 60% hit rate.
/// Null when no level reaches that bar (a beginner).
Cefr? estimateLevel(List<(Cefr, bool)> results) {
  for (final level in Cefr.values.reversed) {
    final at = results.where((r) => r.$1 == level);
    final right = at.where((r) => r.$2).length;
    if (right >= 2 && right / at.length >= 0.6) return level;
  }
  return null;
}

/// Answer to "Neden İngilizce öğreniyorsun?".
enum LearnReason {
  school('🎒', 'Okul / LGS', 'Derslerim ve LGS için'),
  academic('🎓', 'Akademik / YDS', 'YDS, YÖKDİL, yüksek lisans'),
  work('💼', 'İş', 'İş görüşmesi ve ofis hayatı'),
  tourism('🏖️', 'Turizm', 'Otel, restoran, rehberlik'),
  general('🌍', 'Genel', 'Günlük hayat ve kendim için');

  const LearnReason(this.emoji, this.title, this.subtitle);
  final String emoji;
  final String title;
  final String subtitle;
}

/// What the result screen suggests and what "apply" changes.
class PlacementRecommendation {
  const PlacementRecommendation({
    required this.level,
    required this.reason,
    required this.trackId,
    this.nextTrackId,
    this.knownUnits = 0,
    this.knownLessons = 0,
    this.knownNodeIds = const [],
    this.openSection,
  });

  /// Null for a beginner.
  final Cefr? level;
  final LearnReason reason;

  /// Track to start now.
  final String trackId;

  /// Track to move on to later, if any.
  final String? nextTrackId;

  /// General-course units and grammar-path lessons treated as known.
  final int knownUnits;
  final int knownLessons;
  final List<String> knownNodeIds;

  /// General-course section the plan opens ("Bölüm 3"), if past the first.
  final int? openSection;
}

/// Section of the general course the placement test opens for [level]:
/// A2 → 3, B1 → 5, B2 and above → 7. Null keeps the normal start.
int? placementSection(Cefr? level) => switch (level) {
  Cefr.a2 => 3,
  Cefr.b1 => 5,
  Cefr.b2 || Cefr.c1 => 7,
  _ => null,
};

/// General-course units (of 12, A1→A2) a learner at [level] can skip.
/// Conservative: the last units of a level are kept for review.
int knownCourseUnits(Cefr? level) => switch (level) {
  null => 0,
  Cefr.a1 => 4,
  Cefr.a2 => 9,
  _ => 12,
};

/// Node id of a grammar-path lesson (same as `lessonNodeId`).
String grammarNodeId(GrammarLesson l) => 'gl_${l.id}';

/// Builds the recommendation. [courseUnits] are the general course's units as
/// lists of node ids, in path order; [lessons] is the grammar path;
/// [sectionCount] is the number of general-course sections shipped.
///
/// The plan also opens the section for the level ([placementSection]). It is
/// stored by section number, so a section that ships later opens too.
PlacementRecommendation recommend({
  required Cefr? level,
  required LearnReason reason,
  required List<List<String>> courseUnits,
  required List<GrammarLesson> lessons,
  int sectionCount = 1,
}) {
  final rank = level?.index ?? -1;
  final atLeastA2 = rank >= Cefr.a2.index;
  final (track, next) = switch (reason) {
    LearnReason.school => ('lgs', null),
    LearnReason.academic => atLeastA2 ? ('yds', null) : (defaultTrackId, 'yds'),
    LearnReason.work => atLeastA2 ? ('pro_interview', null) : (defaultTrackId, 'pro_interview'),
    LearnReason.tourism => atLeastA2 ? ('pro_tourism', null) : (defaultTrackId, 'pro_tourism'),
    LearnReason.general => rank >= Cefr.b1.index ? (notesTrack.id, null) : (defaultTrackId, null),
  };

  final units = courseUnits.take(knownCourseUnits(level)).toList();
  final section = placementSection(level);
  // Grammar lessons strictly below the estimated level; workshops are kept.
  final known = [
    for (final l in lessons)
      if (l.unit.startsWith(l.level) &&
          Cefr.values.any((c) => c.code == l.level) &&
          Cefr.byCode(l.level).index < rank)
        l,
  ];
  return PlacementRecommendation(
    level: level,
    reason: reason,
    trackId: track,
    nextTrackId: next,
    knownUnits: units.length,
    knownLessons: known.length,
    knownNodeIds: [
      for (final u in units) ...u,
      for (final l in known) grammarNodeId(l),
      if (section != null) sectionPassId(section),
    ],
    openSection: section == null || sectionCount < 2 ? null : min(section, sectionCount),
  );
}

/// Short Turkish description of what a learner at [level] can do.
String levelSummary(Cefr? level) => switch (level) {
  null =>
    'Hiç sorun değil! En baştan, selamlaşma ve temel kelimelerle başlayacağız. Her gün birkaç dakika yeter.',
  Cefr.a1 => 'Basit kelimeleri ve kalıpları tanıyorsun. Kendini tanıtabilir, temel sorular sorabilirsin. Şimdi bunları sağlamlaştırma zamanı.',
  Cefr.a2 => 'Günlük konularda kısa cümleler kurabiliyor, geçmiş ve gelecek planlardan bahsedebiliyorsun. Bir sonraki adım: daha uzun ve bağlantılı cümleler.',
  Cefr.b1 => 'Tanıdık konularda rahatça anlaşabiliyor, kısa metinlerin ana fikrini yakalayabiliyorsun. Perfect zamanlar, koşul cümleleri ve edilgen yapı senin için oturmaya başlamış.',
  Cefr.b2 => 'Karmaşık metinleri anlayıp fikrini gerekçeleriyle savunabiliyorsun. Akademik okuma ve ince gramer ayrıntıları üzerinde çalışabilirsin.',
  Cefr.c1 => 'Çok iyi! Zor metinlerdeki ima ve tutumları seziyor, devrik yapı gibi ileri kalıpları kullanabiliyorsun. Artık kelime derinliği ve akıcılık üzerine gidebilirsin.',
};

/// Sets the track and marks known nodes. Nothing gets locked.
void applyPlacement(ProgressNotifier progress, PlacementRecommendation r) {
  progress.setTrack(r.trackId);
  if (r.knownNodeIds.isNotEmpty) progress.markKnown(r.knownNodeIds);
}

/// The last placement result, kept apart from [Progress] on the device.
class PlacementRecord {
  const PlacementRecord({required this.level, required this.reason, required this.day});
  final Cefr? level;
  final LearnReason reason;
  final String day;

  Map<String, dynamic> toJson() => {'level': level?.code, 'reason': reason.name, 'day': day};

  factory PlacementRecord.fromJson(Map<String, dynamic> j) => PlacementRecord(
    level: j['level'] == null ? null : Cefr.byCode(j['level'] as String),
    reason: LearnReason.values.byName(j['reason'] as String),
    day: j['day'] as String,
  );
}

class PlacementNotifier extends Notifier<PlacementRecord?> {
  static const _key = 'placement_v1';

  @override
  PlacementRecord? build() {
    final raw = ref.read(prefsProvider).getString(_key);
    if (raw == null) return null;
    try {
      return PlacementRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void save(Cefr? level, LearnReason reason) {
    final record = PlacementRecord(level: level, reason: reason, day: dayKey(ref.read(clockProvider)()));
    state = record;
    ref.read(prefsProvider).setString(_key, jsonEncode(record.toJson()));
  }
}

final placementProvider = NotifierProvider<PlacementNotifier, PlacementRecord?>(PlacementNotifier.new);
