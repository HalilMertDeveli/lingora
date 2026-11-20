import '../data/option_glosses.dart';
import '../models/course.dart';
import 'question_types.dart';

/// What kind of mistake a wrong exam-style answer was, decided by the
/// question type (and, for cloze, by its options): the "Hata türü" line of
/// the error notebook.
enum MistakeKind {
  vocabulary('Kelime'),
  grammar('Gramer kuralı'),
  reading('Okuma / çeldirici'),
  meaning('Çeviri / anlam');

  const MistakeKind(this.label);
  final String label;

  /// The rule-based reason for this kind of mistake (free for everyone).
  String get rule => switch (this) {
    vocabulary =>
      'Şıklar aynı türden kelimeler; cümlenin anlamına uyan kelimeyi bilmek gerekiyordu. '
          'Boşluğun öncesi ve sonrası hangi anlamın gerektiğini gösterir.',
    grammar =>
      'Bu soru bir yapı kuralını ölçüyor: zaman uyumu, bağlaç ya da edat. '
          'Boşluğun çevresindeki yapı hangi şıkkın dilbilgisi olarak oturduğunu belirler.',
    reading =>
      'Bu bir okuma/çeldirici sorusu: yanlış şıklar çoğu zaman metindeki kelimeleri kullanır ama metnin '
          'söylediğini vermez. Cevabı metindeki cümleyle karşılaştırarak doğrula.',
    meaning =>
      'Bu soru anlamın tamamını ölçüyor: özne, zaman ve olumlu/olumsuz anlam doğru şıkta birebir korunur. '
          'Tek bir kelimenin karşılığına bakmak yanıltabilir.',
  };

  /// Kind of a question of type [t]; [options] decide for cloze (single
  /// content words are a word question, anything else structure).
  static MistakeKind of(QType t, {List<String> options = const []}) => switch (t) {
    QType.vocabulary => vocabulary,
    QType.sentenceCompletion => grammar,
    // A grammar unit's "Ünitenin kelimeleri" asks single content words: a
    // word mistake, not a rule one.
    // Without options (a study-log entry) the type decides.
    QType.grammar || QType.cloze => options.isEmpty || structureOptions(options) ? grammar : vocabulary,
    QType.translation || QType.restatement => meaning,
    QType.reading || QType.dialogue || QType.paragraphCompletion || QType.irrelevantSentence => reading,
    QType.other => structureOptions(options) ? grammar : vocabulary,
  };
}

/// Why a notebook question went wrong, as the app can tell without AI.
class MistakeDiagnosis {
  const MistakeDiagnosis({
    required this.kind,
    required this.answer,
    this.picked,
    this.pickedWhy,
    this.rightWhy,
  });

  final MistakeKind kind;

  /// The right option ("B) ...").
  final String answer;

  /// The learner's option ("D) ..."), when it was kept.
  final String? picked;

  /// Why the learner's option is wrong (the option's gloss), when known.
  final String? pickedWhy;

  /// One line on why the right option fits (gloss or the explanation's first
  /// sentence).
  final String? rightWhy;

  /// The short reason shown in the notebook: the picked option's own reason
  /// when there is one, else the rule for this kind of mistake.
  String get reason => pickedWhy ?? kind.rule;
}

/// Diagnosis of the wrong answer [picked] (an option index; null when not
/// kept) on choice exercise [ex]; null for other exercises. [gloss] gives
/// option-level reasons when the content has them.
MistakeDiagnosis? diagnoseMistake(Exercise ex, {int? picked, OptionGloss? gloss, String? unitId}) {
  final type = exerciseType(ex, unitId: unitId);
  final answer = ex.answerIndex;
  if (type == null || answer == null || answer < 0 || answer >= ex.options.length) return null;
  final pick = picked != null && picked >= 0 && picked < ex.options.length && picked != answer
      ? picked
      : null;
  String label(int i) => '${_letters[i % _letters.length]}) ${ex.options[i]}';
  final pickedWhy = pick == null ? null : gloss?.whyOf(pick);
  return MistakeDiagnosis(
    kind: MistakeKind.of(type, options: ex.options),
    answer: label(answer),
    picked: pick == null ? null : label(pick),
    pickedWhy: pickedWhy == null ? null : _withoutVerdict(pickedWhy),
    rightWhy: basicWhyLine(gloss, answer, explanation: ex.explanation ?? ''),
  );
}

const _letters = ['A', 'B', 'C', 'D', 'E', 'F'];

/// "Olmaz: ..." / "Yanlış: ..." glosses read as a reason on their own.
String _withoutVerdict(String s) {
  final m = RegExp(r'^(olmaz|yanlış|hatalı)\s*[:\-–]\s*', caseSensitive: false).firstMatch(s);
  return m == null ? s : s.substring(m.end);
}
