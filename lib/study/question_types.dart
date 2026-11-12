import '../models/course.dart';
import '../models/exam.dart';

/// Question types of an exam-style (`choice`) question, for the error
/// notebook, the mock report and time targets. The names are the shared
/// `qtype` values of the content (docs/sinav/yds-faz1-yontem.md §4) and the
/// keys of `targetSeconds` in assets/plans/yds_1_yil.json.
enum QType {
  vocabulary('Kelime', 45, 6, 5),
  grammar('Dilbilgisi', 45, 10, 9),
  cloze('Cloze test', 70, 10, 9),
  sentenceCompletion('Cümle tamamlama', 90, 10, 9),
  translation('Çeviri', 120, 6, 6),
  reading('Okuma', 180, 20, 17),
  dialogue('Diyalog tamamlama', 100, 6, 5),
  restatement('Restatement', 100, 3, 3),
  paragraphCompletion('Paragraf tamamlama', 135, 4, 4),
  irrelevantSentence('Anlam bütünlüğünü bozan', 135, 5, 5),
  other('Diğer', 60, 0, 0);

  const QType(this.label, this.targetSeconds, this.inExam, this.target72);
  final String label;

  /// Time to aim for per question in the real exam (yds-arastirma §2.8).
  /// Over the 80 questions they add up to about 2 h 45 min, leaving 15–20
  /// minutes for checking. Reading includes reading the text.
  final int targetSeconds;

  /// Questions of this type in a YDS (yds-plan.md §3).
  final int inExam;

  /// Right answers of this type in the 72-right (90 points) plan.
  final int target72;

  static QType? byName(String? name) => QType.values.where((t) => t.name == name).firstOrNull;
}

/// Types of the YDS path's teaching units (ids never change).
const _unitTypes = {
  'ys3u1': QType.cloze,
  'ys3u2': QType.sentenceCompletion,
  'ys3u3': QType.translation,
  'ys3u4': QType.translation,
  'ys3u5': QType.reading,
  'ys3u6': QType.reading,
  'ys3u7': QType.dialogue,
  'ys3u8': QType.restatement,
  'ys3u9': QType.paragraphCompletion,
  'ys3u10': QType.irrelevantSentence,
  'ys3u11': QType.reading,
  'ys3u12': QType.reading,
  'ys3u13': QType.reading,
  'ys3u14': QType.reading,
};

/// Exam bank / pack section ids (assets/exams/yds.json, yds_full.json).
const _sectionTypes = {
  'yds_vocab': QType.vocabulary,
  'yds_grammar': QType.grammar,
  'yds_conj': QType.grammar,
  'yds_cloze': QType.cloze,
  'yds_completion': QType.sentenceCompletion,
  'yds_translation': QType.translation,
  'yds_reading': QType.reading,
  'yds_dialogue': QType.dialogue,
  'yds_restatement': QType.restatement,
  'yds_paragraph': QType.paragraphCompletion,
  'yds_irrelevant': QType.irrelevantSentence,
};

/// Words that make an option a structure (grammar) choice, not a word one.
const _functionWords = {
  'a', 'an', 'the', 'to', 'of', 'in', 'on', 'at', 'by', 'for', 'with', 'from', 'into', 'onto', 'upon', //
  'about', 'since', 'until', 'unless', 'although', 'though', 'because', 'while', 'whereas', 'when',
  'whenever', 'if', 'whether', 'that', 'which', 'who', 'whom', 'whose', 'what', 'where', 'than', 'as',
  'so', 'such', 'but', 'and', 'or', 'nor', 'yet', 'however', 'therefore', 'moreover', 'despite',
  'unlike', 'besides', 'instead', 'otherwise', 'thus', 'hence', 'nevertheless', 'nonetheless',
  'furthermore', 'meanwhile', 'any', 'some', 'much', 'many', 'few', 'little', 'more', 'most', 'less',
  'least', 'all', 'both', 'either', 'neither', 'each', 'every', 'no', 'none', 'not', 'is', 'are', 'was',
  'were', 'be', 'been', 'being', 'has', 'have', 'had', 'do', 'does', 'did', 'will', 'would', 'shall',
  'should', 'can', 'could', 'may', 'might', 'must', 'ought', 'need', 'used', 'having', 'through',
  'throughout', 'within', 'without', 'among', 'between', 'during', 'against', 'towards', 'toward',
  'beyond', 'above', 'below', 'under', 'over', 'after', 'before', 'like', 'even', 'only', 'just', 'once',
  'whatever', 'whichever', 'whoever', 'whereby', 'wherever', 'rather', 'hardly', 'scarcely', 'barely',
  'too', 'enough', 'very', 'quite', 'also', 'still', 'already',
};

/// Connectors a sentence-completion option often starts with.
const _connectors = {
  'although',
  'though',
  'because',
  'since',
  'while',
  'whereas',
  'unless',
  'if',
  'as',
  'when',
  'before',
  'after',
  'so',
  'but',
  'however',
  'despite',
  'even',
  'once',
  'until',
  'whether',
};

final _turkish = RegExp('[çğışöüÇĞİŞÖÜ]');
final _numberedBlank = RegExp(r'\(\d\)');

/// Type of a `choice` question. A bank/pack [section] or a known teaching
/// unit ([unitId]) decides; then [vocabLesson]; otherwise the text decides
/// (rules agreed with yds-arastirma).
QType questionType({
  required String question,
  String? passage,
  List<String> options = const [],
  String? unitId,
  String? section,
  bool vocabLesson = false,
}) {
  if (_sectionTypes[section] case final t?) return t;
  if (_unitTypes[unitId] case final t?) return t;
  if (vocabLesson || (unitId?.startsWith('ys2') ?? false)) return QType.vocabulary;
  final q = question.toLowerCase();
  final p = (passage ?? '').trim();
  if (q.contains('anlam bütünlüğünü') || (p.contains('(I)') && p.contains('(V)'))) {
    return QType.irrelevantSentence;
  }
  if (q.contains('diyalog')) return QType.dialogue;
  if (q.contains('paragraf') && q.contains('boş')) return QType.paragraphCompletion;
  if (q.contains('yakın anlam') || q.contains('closest in meaning')) return QType.restatement;
  if (p.isNotEmpty) {
    final blank = p.contains('--') || q.contains('numaralı boşluk') || _numberedBlank.hasMatch(q);
    return blank ? QType.cloze : QType.reading;
  }
  if (options.isEmpty) return QType.other;
  final turkishOptions = options.where(_turkish.hasMatch).length;
  if (turkishOptions >= options.length - 1 || _turkish.hasMatch(question)) return QType.translation;
  if (!question.contains('--')) return QType.restatement;
  List<String> words(String o) => o.toLowerCase().trim().split(RegExp(r'\s+'));
  final longest = options.map((o) => words(o).length).reduce((a, b) => a > b ? a : b);
  final connectorStarts = options.where((o) => _connectors.contains(words(o).first)).length;
  if (longest > 4 || connectorStarts * 2 > options.length) return QType.sentenceCompletion;
  final structure = options.every((o) => words(o).any(_functionWords.contains));
  if (structure || longest > 1) return QType.grammar;
  // Single content words: in grammar units it is still a grammar question.
  return (unitId?.startsWith('ys1') ?? false) ? QType.grammar : QType.vocabulary;
}

/// Type of a mock or bank question.
QType examQuestionType(ExamQuestion q, {String? unitId}) => questionType(
  question: q.text,
  passage: q.passage,
  options: q.options,
  section: q.section,
  unitId: unitId,
);

/// Type of a path exercise: the content's own `qtype` when it has one; null
/// for non-`choice` exercises.
QType? exerciseType(Exercise ex, {String? unitId, bool vocabLesson = false}) {
  if (ex.type != ExerciseType.choice) return null;
  if (QType.byName(ex.qtype) case final t?) return t;
  return questionType(
    question: ex.question ?? '',
    passage: ex.passage,
    options: ex.options,
    unitId: unitId,
    vocabLesson: vocabLesson,
  );
}
