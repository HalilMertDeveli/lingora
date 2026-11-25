import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/course.dart';
import '../study/question_types.dart';
import 'practice.dart';
import 'progress.dart';

// Help on retrying a failed unit test (YDS/YÖKDİL mini exams and every other
// unit test with a pass mark). The gate stays: a test is still passed only
// with a pass mark, but each failed attempt makes the next one a little kinder.
//
// * Attempt 1: no help, pass with [testPassPercent].
// * Attempt [hintFromAttempt]+: questions missed before show "İpucu" (a short
//   rule and a note about the wrong options), the right option "winks" (glows
//   twice) and the wrong one picked last time is marked.
// * Attempt [eliminateFromAttempt]+: also up to [maxEliminatedOptions] wrong
//   options of those questions are greyed out, and the pass mark drops to
//   [easedPassPercent].
// Everything is offline: rules come from the unit guide, the question's own
// explanation and [qTypeTips].

/// First attempt that shows hints on questions missed before.
const hintFromAttempt = 2;

/// First attempt that greys out wrong options and uses [easedPassPercent].
const eliminateFromAttempt = 3;

/// Pass mark from [eliminateFromAttempt] on (instead of [testPassPercent]).
const easedPassPercent = 70;

/// Wrong options greyed out on a question missed before.
const maxEliminatedOptions = 2;

/// Options always left to choose from (the right one and at least one more).
const minOptionsLeft = 2;

/// Topics named in "Hatalarının özeti".
const summaryTopicCount = 3;

/// Longest rule line in a hint or the summary.
const hintRuleMaxChars = 220;

/// Pass mark of test attempt [attempt] (1-based).
int passPercentFor(int attempt) => attempt >= eliminateFromAttempt ? easedPassPercent : testPassPercent;

/// What failed attempts of one test left behind.
class TestRecord {
  const TestRecord({this.failed = 0, this.missed = const {}, this.picked = const {}});

  static const empty = TestRecord();

  /// Failed attempts so far.
  final int failed;

  /// Item key ("nodeId#index") → times answered wrong over the attempts.
  final Map<String, int> missed;

  /// Item key → the wrong option last picked on a choice question.
  final Map<String, int> picked;

  /// The attempt about to start (1-based).
  int get nextAttempt => failed + 1;

  /// Adds one failed attempt with its wrong answers.
  TestRecord withFail(Iterable<String> missedKeys, Map<String, int> wrongPicks) => TestRecord(
    failed: failed + 1,
    missed: {...missed, for (final k in missedKeys) k: (missed[k] ?? 0) + 1},
    picked: {...picked, ...wrongPicks},
  );

  Map<String, Object> toJson() => {'failed': failed, 'missed': missed, 'picked': picked};

  static TestRecord fromJson(Object? j) {
    if (j is! Map) return empty;
    Map<String, int> ints(Object? m) => {
      if (m is Map)
        for (final e in m.entries)
          if (e.key is String && e.value is int) e.key as String: e.value as int,
    };
    final failed = j['failed'];
    return TestRecord(
      failed: failed is int ? failed : 0,
      missed: ints(j['missed']),
      picked: ints(j['picked']),
    );
  }
}

/// Failed attempts per test node, kept on the device.
class TestRetryStore {
  TestRetryStore(this._prefs);
  final SharedPreferences _prefs;

  static String keyOf(String nodeId) => 'test_retry_v1.$nodeId';

  TestRecord load(String nodeId) {
    final raw = _prefs.getString(keyOf(nodeId));
    if (raw == null) return TestRecord.empty;
    try {
      return TestRecord.fromJson(jsonDecode(raw));
    } on FormatException {
      return TestRecord.empty;
    }
  }

  /// Records a failed attempt; returns the new record.
  TestRecord recordFail(String nodeId, Iterable<String> missedKeys, Map<String, int> wrongPicks) {
    final next = load(nodeId).withFail(missedKeys, wrongPicks);
    _prefs.setString(keyOf(nodeId), jsonEncode(next.toJson()));
    return next;
  }

  /// Forgets the attempts once the test is passed.
  void clear(String nodeId) => _prefs.remove(keyOf(nodeId));
}

final testRetryStoreProvider = Provider<TestRetryStore>((ref) => TestRetryStore(ref.watch(prefsProvider)));

/// The help an attempt gets from the attempts before it.
class RetryHelp {
  const RetryHelp(this.record);
  final TestRecord record;

  int get attempt => record.nextAttempt;
  int get passPercent => passPercentFor(attempt);
  bool get eased => passPercent < testPassPercent;

  /// Whether question [key] gets "İpucu" (missed before, hints are on).
  bool hintsFor(String key) => attempt >= hintFromAttempt && record.missed.containsKey(key);

  /// The option of [item] that winks when the question comes back: the right
  /// one, on questions missed before (from [hintFromAttempt] on).
  int? winkFor(LessonItem item) => hintsFor(item.key) ? item.ex.answerIndex : null;

  /// The wrong option picked on [item] last time, on a question missed before.
  int? lastPickFor(LessonItem item) => hintsFor(item.key) ? record.picked[item.key] : null;

  /// Options of [item] greyed out on this attempt (none for most questions).
  Set<int> eliminatedFor(LessonItem item) {
    if (attempt < eliminateFromAttempt || !record.missed.containsKey(item.key)) return const {};
    return eliminateOptions(item.ex, seed: item.key, picked: record.picked[item.key]);
  }
}

/// Up to [count] wrong options of a choice question to grey out, always
/// leaving [minOptionsLeft]. The option picked last time comes first (it was
/// a trap for this learner); the rest are chosen by a seed so a question
/// loses the same options every time it is shown.
Set<int> eliminateOptions(
  Exercise ex, {
  required String seed,
  int? picked,
  int count = maxEliminatedOptions,
}) {
  final answer = ex.answerIndex;
  if (ex.type != ExerciseType.choice || answer == null) return const {};
  final n = min(count, ex.options.length - minOptionsLeft);
  if (n <= 0) return const {};
  final wrong = [
    for (var i = 0; i < ex.options.length; i++)
      if (i != answer) i,
  ]..shuffle(Random(_stableHash(seed)));
  if (picked != null && wrong.remove(picked)) wrong.insert(0, picked);
  return wrong.take(n).toSet();
}

/// String hash that stays the same between app runs.
int _stableHash(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}

/// Short Turkish strategy lines per exam question type (the fallback rule).
const qTypeTips = <QType, String>{
  QType.vocabulary:
      'Boşluğun hemen önüne ve arkasına bak: hangi tür kelime (isim, fiil, sıfat) gerekiyor? '
      'Sonra şıkları cümlede tek tek dene; anlamı bozanları ele.',
  QType.grammar:
      'Cümlenin zamanını ve yapısını bul: zaman ifadeleri (since, by the time, yesterday) '
      've boşluktan sonra gelen yapı hangi şıkkın uyduğunu gösterir.',
  QType.cloze:
      'Boşluğun yalnız cümlesine değil, önceki ve sonraki cümleye de bak; '
      'paragrafın zamanı ve anlamı doğru şıkkı daraltır.',
  QType.sentenceCompletion:
      'Verilen yarının zamanına ve bağlacına dikkat et: zıtlık mı, sebep mi, sonuç mu? '
      'Zamanı ya da anlamı uymayan şıkları ele.',
  QType.translation:
      'Önce cümlenin ana fiilini ve zamanını bul, sonra şıklarda bu ikisinin doğru '
      'karşılandığına bak. Tek kelimedeki fark çoğu zaman tuzaktır.',
  QType.reading:
      'Soruyu önce oku, sonra metinde ilgili cümleyi bul. Metinde açıkça yazmayan, '
      'fazla genel ya da fazla kesin şıklar genelde yanlıştır.',
  QType.dialogue:
      'Boşluktan sonraki cevaba bak: boşluk ona uyan bir soru ya da tepki olmalı. '
      'Konuşmanın tonunu (şaşırma, itiraz, onay) kaçırma.',
  QType.restatement:
      'Ana fikri ve zamanı koruyan şıkkı ara. Olumsuzluk, karşılaştırma ve '
      'kesinlik (all, some, never) farkları en sık tuzaktır.',
  QType.paragraphCompletion:
      'Boşluğun önündeki ve arkasındaki cümleyi birlikte oku; boşluk ikisini '
      'bağlamalı. Konuyu değiştiren şıkkı ele.',
  QType.irrelevantSentence:
      'Paragrafın ana konusunu ilk cümleden çıkar. Konuyla ilgili gibi görünüp '
      'akışı bozan cümleyi ara.',
};

/// The hint of a question missed before: a short rule and, when the
/// explanation has one, a note about wrong options. Neither names the right
/// option. Null when there is nothing safe to show.
class TestHint {
  const TestHint({this.rule, this.clue});
  final String? rule;
  final String? clue;
}

TestHint? hintFor(Exercise ex, {String? guide, QType? type}) {
  final forbidden = _answerWords(ex);
  bool safe(String? s) => s != null && !forbidden.any(s.toLowerCase().contains);
  final fromGuide = guideRule(guide);
  final tip = type == null ? null : qTypeTips[type];
  final rule = safe(fromGuide) ? fromGuide : (safe(tip) ? tip : null);
  final clue = explanationClue(ex);
  if (rule == null && clue == null) return null;
  return TestHint(rule: rule, clue: clue);
}

/// Words that would give a question's answer away: the right option, the
/// Turkish an explanation puts after it ("'careful' (dikkatli)") and, for
/// other types, the answer text.
List<String> _answerWords(Exercise ex) {
  final words = <String>{};
  void add(String? s) {
    final t = s?.trim().toLowerCase() ?? '';
    if (t.length >= 3) words.add(t);
  }

  if (ex.type == ExerciseType.choice) {
    final right = ex.correctOption;
    add(right);
    final m = RegExp("['‘’\"“]${RegExp.escape(right)}['‘’\"”]\\s*\\(([^)]+)\\)")
        .firstMatch(ex.explanation ?? '');
    if (m != null) {
      for (final part in m.group(1)!.split(RegExp('[,;/]'))) {
        add(part);
      }
    }
  } else {
    add(ex.displayAnswer);
  }
  return words.toList();
}

/// Sentences of a choice question's explanation that say why some wrong
/// options do not fit, without the right one. At most two; null when none.
String? explanationClue(Exercise ex) {
  final text = ex.explanation?.trim() ?? '';
  if (ex.type != ExerciseType.choice || text.isEmpty) return null;
  final forbidden = _answerWords(ex);
  final wrong = [
    for (final (i, o) in ex.options.indexed)
      if (i != ex.answerIndex && o.trim().length >= 2) o.trim().toLowerCase(),
  ];
  final kept = <String>[];
  for (final sentence in text.split(RegExp(r'(?<=[.!?])\s+'))) {
    final s = sentence.trim();
    final lower = s.toLowerCase();
    if (s.isEmpty || lower.startsWith('doğru cevap') || lower.startsWith('cevap')) continue;
    if (forbidden.any(lower.contains)) continue;
    if (!wrong.any(lower.contains)) continue;
    kept.add(s);
    if (kept.length == 2) break;
  }
  return kept.isEmpty ? null : kept.join(' ');
}

/// Guide sections a short rule is taken from, best first.
const _ruleSections = ['Sınav ipucu', 'Nasıl çözülür', 'Kural', 'Strateji', 'Nasıl uygulanır'];

/// A short plain-text rule from a unit guide (markdown with "## " sections):
/// the first paragraph of its tip or rule section, at most
/// [hintRuleMaxChars] long. Null without a guide.
String? guideRule(String? guide) {
  if (guide == null || guide.trim().isEmpty) return null;
  final sections = <String, String>{};
  for (final part in guide.split(RegExp(r'^## ', multiLine: true))) {
    final nl = part.indexOf('\n');
    if (nl < 0) continue;
    sections[part.substring(0, nl).trim()] = part.substring(nl + 1).trim();
  }
  final body = _ruleSections.map((s) => sections[s]).nonNulls.firstOrNull;
  if (body == null) return null;
  final paragraph = body.split(RegExp(r'\n\s*\n')).first;
  final plain = paragraph
      .replaceAll(RegExp(r'\*\*|__|\*|`'), '')
      .replaceAll(RegExp(r'^\s*(?:[-•]|\d+\.)\s*', multiLine: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return plain.isEmpty ? null : shorten(plain, hintRuleMaxChars);
}

/// [s] cut to [max] characters: at a sentence end when one is close, else at
/// a word, with "…".
String shorten(String s, int max) {
  if (s.length <= max) return s;
  final cut = s.substring(0, max);
  final end = cut.lastIndexOf(RegExp(r'[.!?](\s|$)'));
  if (end >= max ~/ 2) return cut.substring(0, end + 1);
  final space = cut.lastIndexOf(' ');
  return '${cut.substring(0, space > 0 ? space : max).trimRight()}…';
}

/// One line of "Hatalarının özeti".
class MissedTopic {
  const MissedTopic({required this.label, required this.count, this.tip});
  final String label;
  final int count;

  /// Short rule for the topic, when there is one.
  final String? tip;
}

/// Topic of a test question: the exam question type of a choice question
/// (grammar ones named after their unit, e.g. "Zamanlar"), else the lesson
/// it came from.
({String label, String? tip}) topicOf(LessonItem item, {Unit? unit, PathNode? lesson, String? testNodeId}) {
  final type = exerciseType(item.ex, unitId: unit?.id);
  if (type != null && type != QType.other) {
    final label = type == QType.grammar && unit != null ? unit.title : type.label;
    return (label: label, tip: qTypeTips[type]);
  }
  if (lesson != null && lesson.id != testNodeId) return (label: lesson.title, tip: null);
  return (label: unit?.title ?? 'Diğer', tip: null);
}

/// The topics of [missed] questions, most missed first, at most
/// [summaryTopicCount]. [course] resolves each question's unit and lesson.
List<MissedTopic> missSummary(List<LessonItem> missed, {Course? course, String? testNodeId}) {
  final nodes = {for (final n in course?.allNodes ?? const <PathNode>[]) n.id: n};
  final counts = <String, int>{};
  final tips = <String, String?>{};
  for (final item in missed) {
    final nodeId = item.key.contains('#') ? item.key.substring(0, item.key.lastIndexOf('#')) : item.key;
    final unit = course?.units.where((u) => u.nodes.any((n) => n.id == nodeId)).firstOrNull;
    final t = topicOf(item, unit: unit, lesson: nodes[nodeId], testNodeId: testNodeId);
    counts[t.label] = (counts[t.label] ?? 0) + 1;
    tips[t.label] ??= t.tip;
  }
  final order = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return [
    for (final label in order.take(summaryTopicCount))
      MissedTopic(label: label, count: counts[label]!, tip: tips[label]),
  ];
}
