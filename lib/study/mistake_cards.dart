import '../data/mistake_card.dart';
import '../data/progress.dart';
import '../data/option_glosses.dart';
import '../models/course.dart';
import '../models/vocab.dart';
import 'mistake_diagnosis.dart';
import 'review_queue.dart';

/// Id prefix of a mistake card that is not a single word (a structure or a
/// whole sentence).
const mistakeCardPrefix = 'mk_';

final _blank = RegExp(r'-{2,}|_{2,}');

/// [sentence] with its blank ("----", "___") filled with [answer]; null
/// when it has none.
String? filledSentence(String? sentence, String answer) {
  if (sentence == null || !_blank.hasMatch(sentence)) return null;
  return sentence.replaceFirst(_blank, answer).replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Turkish of English words the course knows: its match pairs and the YDS
/// word bank ([ydsCards]).
Map<String, String> wordMeanings(Course course, {List<VocabEntry> ydsCards = const []}) {
  final out = <String, String>{};
  for (final e in ydsCards) {
    if (e.senses.isNotEmpty) out.putIfAbsent(e.word.trim().toLowerCase(), () => e.senses.first.tr);
  }
  for (final n in course.allNodes) {
    for (final ex in n.exercises) {
      if (ex.type != ExerciseType.match) continue;
      for (final (tr, en) in ex.pairs) {
        out.putIfAbsent(en.trim().toLowerCase(), () => tr);
      }
    }
  }
  return out;
}

String _sentenceId(String en) =>
    '$mistakeCardPrefix${en.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '')}';

/// The review card of a wrong answer to [ex] (question [key] of [course]),
/// or null when the mistake is not about one item a card can teach (a
/// reading passage, a match set, speaking). [picked] is the chosen option
/// of a choice question, [typed] the learner's own sentence. [premium]
/// adds the picked option's own reason when the content has one; the AI
/// analysis replaces [MistakeCardInfo.why] later.
MistakeCardInfo? mistakeCardFor(
  Exercise ex, {
  required String key,
  required Course course,
  required String day,
  int? picked,
  String typed = '',
  OptionGloss? gloss,
  String? unitId,
  Map<String, String> meanings = const {},
  bool premium = false,
}) {
  final yds = course.id.startsWith('exam_yds');
  String wordId(String en) => wordCardId(yds ? ydsWordPrefix : generalWordPrefix, en);
  String? meaning(String en) => meanings[en.trim().toLowerCase()];

  switch (ex.type) {
    case ExerciseType.choice:
      final d = diagnoseMistake(ex, picked: picked, gloss: gloss, unitId: unitId);
      final answer = ex.answerIndex;
      if (d == null || answer == null) return null;
      if (d.kind == MistakeKind.reading || d.kind == MistakeKind.meaning) return null;
      final en = ex.options[answer].trim();
      final example = filledSentence(ex.question, en);
      final single = !en.contains(' ');
      final tr = gloss?.trOf(answer) ?? meaning(en) ?? d.rightWhy ?? 'Doğru seçenek';
      final pickedText = picked != null && picked != answer && picked >= 0 && picked < ex.options.length
          ? ex.options[picked].trim()
          : null;
      final why = premium && d.pickedWhy != null
          ? d.pickedWhy!
          : pickedText != null
          ? '“$pickedText” bu cümleye uymuyor; doğrusu “$en”. ${d.kind.label} hatası.'
          : '${d.kind.label} hatası: bu boşluğa “$en” gelir.';
      return MistakeCardInfo(
        id: d.kind == MistakeKind.vocabulary && single ? wordId(en) : _sentenceId(en),
        en: en,
        tr: tr,
        why: why,
        day: day,
        example: example,
        kind: d.kind.label,
        source: key,
      );
    case ExerciseType.fillBlank || ExerciseType.select:
      final answer = (ex.answer ?? '').trim();
      if (answer.isEmpty) return null;
      final sentence = filledSentence(ex.text ?? ex.prompt, answer);
      final tr = meaning(answer);
      final typedNote = typed.trim().isEmpty ? '' : ' Senin cevabın: “${typed.trim()}”.';
      if (tr != null) {
        return MistakeCardInfo(
          id: wordId(answer),
          en: answer,
          tr: tr,
          why: 'Boşluğa “$answer” gelir.$typedNote',
          day: day,
          example: sentence,
          kind: MistakeKind.vocabulary.label,
          source: key,
        );
      }
      // No word meaning known: the whole right sentence with its Turkish.
      final t = ex.translation?.trim() ?? '';
      if (sentence == null || t.isEmpty) return null;
      return MistakeCardInfo(
        id: _sentenceId(sentence),
        en: sentence,
        tr: t,
        why: 'Boşluğa “$answer” gelir.$typedNote',
        day: day,
        kind: MistakeKind.grammar.label,
        source: key,
      );
    case ExerciseType.translate:
      final en = ex.answers.isEmpty ? '' : ex.answers.first.trim();
      final tr = (ex.prompt ?? '').trim();
      if (en.isEmpty || tr.isEmpty) return null;
      return MistakeCardInfo(
        id: _sentenceId(en),
        en: en,
        tr: tr,
        why: typed.trim().isEmpty
            ? 'Cümleyi bu sırayla kur: özne, fiil, gerisi.'
            : 'Senin cümlen: “${typed.trim()}”. Doğrusu yukarıda; kelime sırasına ve eklere bak.',
        day: day,
        kind: 'Cümle kurma',
        source: key,
      );
    default:
      return null;
  }
}

/// The learner's mistakes as every screen counts them (Pratik, Profil,
/// hata defteri), from [Progress] only, so the screens never disagree.
class MistakeTotals {
  const MistakeTotals({required this.notebook, required this.cards, required this.missedOnce});

  /// From [p].
  factory MistakeTotals.of(Progress p) => MistakeTotals(
    notebook: p.mistakes.length,
    cards: p.mistakeCards.length,
    missedOnce: p.mistakeMisses.length,
  );

  /// Questions in the error notebook.
  final int notebook;

  /// "Tekrar kartları" made from wrong answers.
  final int cards;

  /// Questions answered wrong but not (yet) saved in the notebook: a
  /// question is saved at its [mistakeSaveMisses]th wrong answer.
  final int missedOnce;

  bool get none => notebook == 0 && cards == 0 && missedOnce == 0;

  /// Pratik's "Hatalarını çalış" line when nothing is due today.
  String get practiceLine => notebook > 0
      ? 'Hata defterinde $notebook soru, sırası gelince döner'
      : cards > 0
      ? 'Hata defteri boş; yanlışların $cards tekrar kartında'
      : missedOnce > 0
      ? '$missedOnce soruyu karıştırdın; yine yanlış olursa deftere girer'
      : 'Şu an çalışılacak hata yok';

  /// Profil's line when no sentence-error category is recorded yet.
  String? get profileLine => none
      ? null
      : 'Hata defterinde $notebook soru, tekrar kartlarında $cards yanlışın var. '
            'Cümle kurarken yaptığın hatalar (ek, sıra, yazım) da burada toplanır.';
}

/// The review cards of [cards] as "Tekrar kartları" word cards.
List<WordCard> mistakeWordCards(List<MistakeCardInfo> cards) => [
  for (final c in cards) (id: c.id, en: c.en, tr: c.tr, example: c.example, unit: c.kind),
];
