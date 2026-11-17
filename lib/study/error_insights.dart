import 'dart:math';

import '../core/tr_errors.dart';
import '../data/practice.dart';
import '../data/progress.dart';
import '../models/course.dart';
import 'question_types.dart';
import 'study_state.dart';
import 'tr_error_log.dart';

/// Detaylı hata analizi (Premium): everything here is computed on the device
/// from the answer log ([AnswerLog]: question type, path unit, day, time)
/// and the hata dedektörü history ([TrErrorLog]). Pure functions, so the
/// numbers are tested apart from the screen.

/// Answers before the analysis opens (about three lessons).
const minAnswersForInsights = 30;

/// Graded answers in a typical lesson, for "N ders daha çöz".
const answersPerLesson = 10;

/// Answers a topic or type needs before it can be called weak.
const minAnswersForWeak = 4;

/// Answers each side of a trend needs.
const minAnswersForTrend = 5;

/// Relative drop in the error rate that counts as "düzeldi".
const minImprovement = 0.2;

/// Days in the "recent" side of a trend.
const trendDays = 14;

/// Lessons still to do before the analysis opens; 0 once it is open.
int lessonsUntilInsights(int answered) =>
    answered >= minAnswersForInsights ? 0 : ((minAnswersForInsights - answered) / answersPerLesson).ceil();

/// Turkish names of the exercise kinds that are not exam-style types.
const _exerciseLabels = {
  'select': 'Resimli seçim',
  'translate': 'Çeviri yazma',
  'fillBlank': 'Boşluk doldurma',
  'listen': 'Dinleyip yazma',
  'match': 'Eşleştirme',
  'choice': 'Çoktan seçmeli',
};

/// Display name of an answer-log type key (a [QType] or [ExerciseType] name).
String typeLabel(String key) => QType.byName(key)?.label ?? _exerciseLabels[key] ?? 'Diğer';

/// Type key of an answer (see `recordLessonAnswer`).
String typeKeyOf(AnswerLog a) => a.type ?? 'other';

/// Type key of a path exercise, as `recordLessonAnswer` would log it.
String itemTypeKey(Exercise ex, {String? unitId, bool vocabLesson = false}) =>
    exerciseType(ex, unitId: unitId, vocabLesson: vocabLesson)?.name ?? ex.type.name;

/// Answers and wrong answers of one topic, type or heat-map cell.
class Bucket {
  const Bucket(this.key, this.label, this.answered, this.wrong);
  final String key;
  final String label;
  final int answered;
  final int wrong;

  int get correct => answered - wrong;
  double get accuracy => answered == 0 ? 0 : correct / answered;
  double get errorRate => answered == 0 ? 0 : wrong / answered;

  /// Accuracy as a whole percentage.
  int get percent => (accuracy * 100).round();

  @override
  String toString() => 'Bucket($key: $correct/$answered)';
}

Map<String, Bucket> _group(
  Iterable<AnswerLog> log,
  String? Function(AnswerLog) keyOf,
  String Function(String) label,
) {
  final answered = <String, int>{};
  final wrong = <String, int>{};
  for (final a in log) {
    final k = keyOf(a);
    if (k == null) continue;
    answered[k] = (answered[k] ?? 0) + 1;
    if (!a.correct) wrong[k] = (wrong[k] ?? 0) + 1;
  }
  return {for (final e in answered.entries) e.key: Bucket(e.key, label(e.key), e.value, wrong[e.key] ?? 0)};
}

/// Answers per grammar topic (path unit) of the open course; units of other
/// courses ([titles] has no name for them) are left out.
Map<String, Bucket> topicBuckets(Iterable<AnswerLog> log, Map<String, String> titles) =>
    _group(log, (a) => titles.containsKey(a.unitId) ? a.unitId : null, (k) => titles[k]!);

/// Answers per question type.
Map<String, Bucket> typeBuckets(Iterable<AnswerLog> log) =>
    _group(log, (a) => typeKeyOf(a) == 'other' ? null : typeKeyOf(a), typeLabel);

/// The [count] weakest of [buckets] with at least [minAnswers] answers and a
/// mistake: lowest accuracy first, the more answered first on a tie.
List<Bucket> weakest(Iterable<Bucket> buckets, {int count = 3, int minAnswers = minAnswersForWeak}) =>
    (buckets.where((b) => b.answered >= minAnswers && b.wrong > 0).toList()..sort((a, b) {
          final c = a.accuracy.compareTo(b.accuracy);
          return c != 0 ? c : b.answered.compareTo(a.answered);
        }))
        .take(count)
        .toList();

/// The day [days] days before [day] ("yyyy-mm-dd").
String daysBefore(String day, int days) {
  final d = DateTime.parse(day);
  return dayKey(DateTime(d.year, d.month, d.day - days));
}

/// This week (the last 7 days, today included) against the 7 days before.
class WeekCompare {
  const WeekCompare(this.thisWeek, this.lastWeek);
  final Bucket thisWeek;
  final Bucket lastWeek;

  /// Change in accuracy, in percentage points; null without both weeks.
  int? get deltaPoints =>
      thisWeek.answered == 0 || lastWeek.answered == 0 ? null : thisWeek.percent - lastWeek.percent;
}

WeekCompare weekCompare(Iterable<AnswerLog> log, String today) {
  final start = daysBefore(today, 6);
  final lastStart = daysBefore(today, 13);
  final b = _group(
    log,
    (a) => a.day.compareTo(start) >= 0
        ? 'this'
        : a.day.compareTo(lastStart) >= 0
        ? 'last'
        : null,
    (k) => k,
  );
  return WeekCompare(
    b['this'] ?? const Bucket('this', 'this', 0, 0),
    b['last'] ?? const Bucket('last', 'last', 0, 0),
  );
}

/// Accuracy per day over the last [days] days, oldest first (null: no answers).
List<Bucket?> dailyAccuracy(Iterable<AnswerLog> log, String today, {int days = 14}) {
  final b = _group(log, (a) => a.day, (k) => k);
  return [for (var i = days - 1; i >= 0; i--) b[daysBefore(today, i)]];
}

/// A mistake that got rarer: error rate before and in the last [trendDays].
class Improvement {
  const Improvement(this.label, this.before, this.after, {this.trCategory});
  final String label;
  final double before;
  final double after;

  /// Set for a hata dedektörü category (then the rates are per check).
  final TrErrorCategory? trCategory;

  /// Relative drop, 0.4 for "%40 azaldı".
  double get drop => before == 0 ? 0 : (before - after) / before;
  int get dropPercent => (drop * 100).round();
}

/// Topics, types and hata dedektörü categories whose error rate fell by at
/// least [minImprovement] between before and the last [trendDays] days,
/// biggest drop first.
List<Improvement> improvements(
  Iterable<AnswerLog> log,
  Map<String, String> titles,
  TrErrorLog trLog,
  String today, {
  int count = 3,
}) {
  final cut = daysBefore(today, trendDays - 1);
  final before = log.where((a) => a.day.compareTo(cut) < 0).toList();
  final after = log.where((a) => a.day.compareTo(cut) >= 0).toList();
  final out = <Improvement>[];
  void compare(Map<String, Bucket> b, Map<String, Bucket> a) {
    for (final e in b.entries) {
      final now = a[e.key];
      if (now == null || e.value.answered < minAnswersForTrend || now.answered < minAnswersForTrend) continue;
      final i = Improvement(e.value.label, e.value.errorRate, now.errorRate);
      if (i.before > 0 && i.drop >= minImprovement) out.add(i);
    }
  }

  compare(topicBuckets(before, titles), topicBuckets(after, titles));
  compare(typeBuckets(before), typeBuckets(after));
  var checksBefore = 0, checksAfter = 0;
  for (final e in trLog.checks.entries) {
    e.key.compareTo(cut) < 0 ? checksBefore += e.value : checksAfter += e.value;
  }
  if (checksBefore >= minAnswersForTrend && checksAfter >= minAnswersForTrend) {
    for (final c in TrErrorCategory.values) {
      final n0 = trLog.events.where((e) => e.category == c && e.day.compareTo(cut) < 0).length;
      final n1 = trLog.events.where((e) => e.category == c && e.day.compareTo(cut) >= 0).length;
      final i = Improvement(c.label, n0 / checksBefore, n1 / checksAfter, trCategory: c);
      if (n0 >= 2 && i.drop >= minImprovement) out.add(i);
    }
  }
  out.sort((a, b) => b.drop.compareTo(a.drop));
  return out.take(count).toList();
}

/// Topic × type accuracy for the most answered topics and types.
class HeatMap {
  const HeatMap(this.rows, this.cols, this.cells);
  final List<Bucket> rows;
  final List<Bucket> cols;

  /// Keyed by `topic|type`; missing: no answers.
  final Map<String, Bucket> cells;

  Bucket? cell(String topic, String type) => cells['$topic|$type'];
  bool get isEmpty => rows.isEmpty || cols.isEmpty;
}

HeatMap heatMap(Iterable<AnswerLog> log, Map<String, String> titles, {int maxRows = 6, int maxCols = 4}) {
  List<Bucket> most(Map<String, Bucket> m, int n) =>
      (m.values.toList()..sort((a, b) => b.answered.compareTo(a.answered))).take(n).toList();
  final rows = most(topicBuckets(log, titles), maxRows);
  // Columns: the types most answered within those topics, so every row and
  // column has something in it.
  final inRows = {for (final r in rows) r.key};
  final cols = most(typeBuckets(log.where((a) => inRows.contains(a.unitId))), maxCols);
  final cells = _group(
    log,
    (a) => titles.containsKey(a.unitId) && typeKeyOf(a) != 'other' ? '${a.unitId}|${typeKeyOf(a)}' : null,
    (k) => k,
  );
  return HeatMap(rows, cols, cells);
}

/// One category of the learner's Türk hata kalıpları: how often, their
/// latest sentence and its fix.
class TrPattern {
  const TrPattern(this.category, this.count, this.example);
  final TrErrorCategory category;
  final int count;

  /// The learner's latest mistake of this kind (null: counted before the
  /// history was kept).
  final TrErrorEvent? example;
}

/// Categories by all-time count ([Progress.errorStats]), most frequent
/// first, each with its newest example from [trLog].
List<TrPattern> trPatterns(Map<String, int> errorStats, TrErrorLog trLog) {
  final counts = <TrErrorCategory, int>{
    for (final e in errorStats.entries)
      if (TrErrorCategory.byName(e.key) case final c? when e.value > 0) c: e.value,
  };
  for (final e in trLog.events) {
    counts[e.category] = max(counts[e.category] ?? 0, 1);
  }
  final list = [
    for (final e in counts.entries)
      TrPattern(
        e.key,
        e.value,
        trLog.events.lastWhere((v) => v.category == e.key, orElse: () => _none).orNull,
      ),
  ]..sort((a, b) => b.count.compareTo(a.count));
  return list;
}

const _none = TrErrorEvent(day: '', category: TrErrorCategory.article, wrong: '', corrected: '');

extension on TrErrorEvent {
  TrErrorEvent? get orNull => day.isEmpty ? null : this;
}

/// A short Turkish rule and why Turkish speakers make each kind of mistake.
const trRuleAndHabit = <TrErrorCategory, (String, String)>{
  TrErrorCategory.article: (
    'Tekil, sayılabilen isim yalnız durmaz: a/an ya da the alır.',
    'Türkçede artikel yok; "kitap okudum" der geçeriz. Beyin İngilizcede de boşluğu doldurmaya gerek görmez.',
  ),
  TrErrorCategory.toBe: (
    'Sıfat, meslek ya da yer söylerken am/is/are gerekir; asıl fiil varken gelmez.',
    'Türkçede "yorgunum" tek kelime; "-im" eki fiilin işini görür. İngilizcede o ek ayrı bir kelimedir.',
  ),
  TrErrorCategory.thirdPerson: (
    'He/she/it ile geniş zamanda fiil -s alır: she works.',
    'Türkçede her kişinin kendi eki var, "o" için ek yok gibi durur. İngilizcede tam tersine ek yalnızca "o"da çıkar.',
  ),
  TrErrorCategory.tense: (
    'Geçmiş zaman ifadesi varsa fiil geçmiş; did varsa fiil yalın.',
    '"-yor" ve "-di" İngilizcedeki zamanlarla birebir örtüşmez; Türkçe kalıbı çevirince zaman kayar.',
  ),
  TrErrorCategory.sinceFor: (
    'Süren durum için present perfect: for + süre, since + başlangıç.',
    '"Üç yıldır burada yaşıyorum" Türkçede şimdiki zaman; birebir çevirince "I am living" çıkar.',
  ),
  TrErrorCategory.modal: (
    'can, must, should, will sonrası fiil yalın: to yok, -s yok.',
    'Türkçede "-ebilir, -meli" fiile eklenir ve fiil çekimli kalır; İngilizcede modal çekimi tek başına taşır.',
  ),
  TrErrorCategory.verbPattern: (
    'want someone to do, let someone do, make someone do kalıplarını ezberle.',
    '"Gelmesini istiyorum" yapısı Türkçede tek fiilde biter; İngilizcede kişi ve fiil ayrı kalıpla gelir.',
  ),
  TrErrorCategory.preposition: (
    'Edatlar kalıptır: listen to, good at, married to.',
    'Türkçe hâl ekleri (-e, -de, -den) edatlarla birebir eşleşmez; ek hangi edatı çağrıştırıyorsa o seçilir.',
  ),
  TrErrorCategory.plural: (
    'Sayıdan sonra isim çoğul olur: two books.',
    'Türkçede "iki kitap" tekil kalır; sayı zaten çokluğu anlatır, -ler eklemeyiz.',
  ),
  TrErrorCategory.uncountable: (
    'advice, information, homework, news -s ve a/an almaz.',
    'Türkçede "bilgiler, tavsiyeler" doğal; aynı kelimeler İngilizcede sayılamaz.',
  ),
  TrErrorCategory.wordOrder: (
    'Sıra özne + fiil + nesne; sıfat ismin önünde.',
    'Türkçede fiil sonda gelir ve sıra serbesttir; aynı sırayı İngilizceye taşıyınca cümle bozulur.',
  ),
  TrErrorCategory.question: (
    'Soru kelimesinden sonra yardımcı fiil gelir: Where do you live?',
    'Türkçede soru "-mi" ekiyle ya da tonlamayla kurulur, yardımcı fiil gerekmez.',
  ),
  TrErrorCategory.doubleNegative: (
    "Cümlede tek olumsuz yeter: I don't know anything.",
    '"Hiçbir şey bilmiyorum" Türkçede iki olumsuzla doğru; İngilizcede ikisi birbirini götürür.',
  ),
  TrErrorCategory.comparative: (
    'Kısa sıfat -er alır, uzun sıfat more; ikisi birlikte olmaz.',
    'Türkçede "daha" her sıfatın önüne gelir, "more bigger" bu alışkanlıktan doğar.',
  ),
  TrErrorCategory.falseFriend: (
    'Türkçeye benzeyen kelimenin anlamını sözlükte örnek cümleyle doğrula.',
    'sempatik, kontrol, fabrika gibi ödünç kelimeler İngilizcede başka anlama kaymıştır.',
  ),
  TrErrorCategory.wordChoice: (
    'make/do, take/have gibi fiilleri isimleriyle birlikte öğren.',
    'Türkçede tek fiil ("yapmak", "çekmek") birçok işi görür; İngilizcede her biri ayrı fiil ister.',
  ),
  TrErrorCategory.spelling: (
    'I, gün, ay, dil ve millet adları büyük harfle yazılır.',
    'Türkçede bu kelimeler küçük harfle yazılır ve kelime okunduğu gibi yazılır; İngilizcede ikisi de geçmez.',
  ),
};

/// Exam the score estimate is for.
enum EstimateExam { yds, lgs }

/// Answers that belong to a YDS / YÖKDİL path, bank or mock.
bool isYdsAnswer(AnswerLog a) =>
    !isLgsAnswer(a) &&
    (a.fromMock ||
        a.key.startsWith('yds') ||
        a.key.startsWith('yokdil') ||
        (a.unitId?.startsWith('ys') ?? false));

/// Answers that belong to the LGS path, bank or mocks.
bool isLgsAnswer(AnswerLog a) =>
    a.key.startsWith('lgs') || a.source.contains('lgs') || RegExp(r'^ls\d+u').hasMatch(a.unitId ?? '');

/// Questions in the LGS English test.
const lgsQuestions = 10;

/// LGS answers before a net estimate is shown.
const minAnswersForLgs = 20;

/// Recent LGS answers the estimate looks at.
const lgsWindow = 200;

/// An estimated LGS English net (out of [lgsQuestions]).
class NetRange {
  const NetRange(this.low, this.high, {required this.mid, required this.basis});
  final int low;
  final int high;
  final double mid;

  /// Answers it rests on.
  final int basis;

  @override
  String toString() => '$low–$high';
}

/// Estimated LGS English net: the accuracy of the last [lgsWindow] LGS
/// questions, with the exam's rule that three wrong answers cancel one right
/// one (blanks are assumed none). The range is the 95% margin of that
/// accuracy (wider with fewer answers), at least ±0.5 net, rounded outward.
/// Null with fewer than [minAnswersForLgs] answers.
NetRange? estimateLgsNet(Iterable<AnswerLog> log) {
  final all = log.where((a) => isLgsAnswer(a) && QType.byName(a.type) != null).toList();
  final recent = all.sublist(max(0, all.length - lgsWindow));
  final n = recent.length;
  if (n < minAnswersForLgs) return null;
  double net(double p) => (lgsQuestions * (p - (1 - p) / 3)).clamp(0, lgsQuestions).toDouble();
  final p = recent.where((a) => a.correct).length / n;
  final margin = max(1.96 * sqrt(p * (1 - p) / n), 0.5 / (lgsQuestions * 4 / 3));
  final mid = net(p);
  return NetRange(net(p - margin).floor(), net(p + margin).ceil(), mid: mid, basis: n);
}

/// One item of "Bu hafta şunlara odaklan".
class FocusItem {
  const FocusItem({required this.label, required this.detail, this.unitId, this.typeKey, this.trCategory});
  final String label;
  final String detail;

  /// A topic to drill (path unit).
  final String? unitId;

  /// A question type to drill.
  final String? typeKey;

  /// A hata dedektörü habit to watch (no drill: it comes from free writing).
  final TrErrorCategory? trCategory;

  bool get drillable => unitId != null || typeKey != null;
}

/// The week's plan: the two weakest topics, the weakest type not already
/// covered and the most frequent Türk hata kalıbı.
List<FocusItem> weeklyFocus(List<Bucket> weakTopics, List<Bucket> weakTypes, List<TrPattern> patterns) => [
  for (final t in weakTopics.take(2))
    FocusItem(
      label: t.label,
      detail: '%${t.percent} doğru · ${t.wrong} yanlış. 10 soruluk konu tekrarı.',
      unitId: t.key,
    ),
  for (final t in weakTypes.take(1))
    FocusItem(
      label: t.label,
      detail: '%${t.percent} doğru · ${t.wrong} yanlış. Bu tipten seçilmiş sorular.',
      typeKey: t.key,
    ),
  if (patterns.firstOrNull case final p?)
    FocusItem(
      label: p.category.label,
      detail: 'Yazarken en sık yaptığın hata (${p.count} kez). Yazdığın her cümlede bir kez kontrol et.',
      trCategory: p.category,
    ),
];

/// Questions for a targeted drill of [unitId] or [typeKey], from [course]'s
/// lessons and tests: the ones the learner got wrong first ([wrongKeys]),
/// then others, [maxCount] at most. Speaking, writing and matching are left
/// out. A type drill keeps to the units the learner has studied
/// ([seenUnits]) when they hold enough questions. Empty when fewer than
/// [minCount] fit.
List<LessonItem> drillItems(
  Course course, {
  String? unitId,
  String? typeKey,
  Set<String> wrongKeys = const {},
  Set<String> seenUnits = const {},
  Random? random,
  int minCount = 5,
  int maxCount = 10,
}) {
  final r = random ?? Random();
  List<LessonItem> pool(bool seenOnly) => [
    for (final u in course.units)
      if ((unitId == null || u.id == unitId) && (!seenOnly || seenUnits.contains(u.id)))
        for (final n in u.nodes)
          if (n.type == NodeType.lesson || n.type == NodeType.test)
            for (final it in lessonItems(n))
              if (!ungradedTypes.contains(it.ex.type) &&
                  it.ex.type != ExerciseType.match &&
                  (typeKey == null || itemTypeKey(it.ex, unitId: u.id, vocabLesson: n.vocab) == typeKey))
                it,
  ];
  var items = pool(unitId == null && seenUnits.isNotEmpty);
  if (items.length < minCount && unitId == null) items = pool(false);
  // The same question can sit in a lesson and its unit test: one each.
  final seen = <String>{};
  items = [
    for (final it in items)
      if (seen.add('${it.ex.question}|${it.ex.text}|${it.ex.answers.join('/')}')) it,
  ];
  if (items.length < minCount) return const [];
  final wrong = items.where((it) => wrongKeys.contains(it.key)).toList()..shuffle(r);
  final rest = items.where((it) => !wrongKeys.contains(it.key)).toList()..shuffle(r);
  return [...wrong, ...rest].take(maxCount).toList();
}

/// Everything the analysis screen shows, from one pass over the data.
class ErrorInsights {
  ErrorInsights({
    required List<AnswerLog> log,
    required this.titles,
    required this.trLog,
    required Map<String, int> errorStats,
    required this.today,
  }) : answered = log.length,
       wrong = log.where((a) => !a.correct).length,
       topics = topicBuckets(log, titles),
       // Types of the open course only (another course's types cannot be
       // drilled here); bank and mock answers have no unit and count.
       types = typeBuckets(log.where((a) => a.unitId == null || titles.containsKey(a.unitId))),
       week = weekCompare(log, today),
       daily = dailyAccuracy(log, today),
       trends = improvements(
         log.where((a) => a.unitId == null || titles.containsKey(a.unitId)),
         titles,
         trLog,
         today,
       ),
       heat = heatMap(log, titles),
       patterns = trPatterns(errorStats, trLog),
       wrongKeys = {
         for (final a in log)
           if (!a.correct) a.key,
       },
       seenUnits = {...log.map((a) => a.unitId).whereType<String>()};

  final Map<String, String> titles;
  final TrErrorLog trLog;
  final String today;
  final int answered;
  final int wrong;
  final Map<String, Bucket> topics;
  final Map<String, Bucket> types;
  final WeekCompare week;
  final List<Bucket?> daily;
  final List<Improvement> trends;
  final HeatMap heat;
  final List<TrPattern> patterns;
  final Set<String> wrongKeys;
  final Set<String> seenUnits;

  double get accuracy => answered == 0 ? 0 : (answered - wrong) / answered;
  int get lessonsToGo => lessonsUntilInsights(answered);
  bool get ready => lessonsToGo == 0;

  late final List<Bucket> weakTopics = weakest(topics.values);
  late final List<Bucket> weakTypes = weakest(types.values);
  late final List<FocusItem> focus = weeklyFocus(weakTopics, weakTypes, patterns);
}
