import '../data/practice.dart';
import '../data/progress.dart';
import '../models/course.dart';
import '../models/vocab.dart';
import 'review_queue.dart';

/// "Neden yanıldın?" (yds-faz1-yontem §4): one tap after a wrong answer,
/// skippable, each leading to a targeted suggestion.
enum MistakeReason {
  vocab('Kelimeyi bilmiyordum', '🔤'),
  structure('Yapıyı/kuralı bilmiyordum', '🧱'),
  misread('Yanlış okudum / acele ettim', '👀'),
  twoOptions('İki şık arasında kaldım', '⚖️'),
  time('Süre yetmedi', '⏱️'),
  guess('Tahmin ettim', '🎲');

  const MistakeReason(this.label, this.emoji);
  final String label;
  final String emoji;

  static MistakeReason? byName(String? name) => values.where((r) => r.name == name).firstOrNull;

  /// The suggestion shown once the reason is picked.
  String get advice => switch (this) {
    vocab => 'Sorudaki ve şıklardaki kelimeleri tekrar kartlarına ekleyelim.',
    structure || guess => 'Ünitenin rehberine göz at, sonra o üniteden 10 soru çöz.',
    misread => 'Önce soru kökünü oku, sonra şıklara bak. Boşluktan önceki ve sonraki sözcükler çoğu zaman cevabı verir.',
    time =>
      'Bir soruda 2 dakikayı aşınca işaretle ve geç; sona kalan sürede dön. Okumaya en az 60 dakika bırak.',
    twoOptions =>
      'Açıklamayı bir kez daha oku: iki şıkkı ayıran sözcük ne? Bu soru 3 gün sonra yeniden gelir.',
  };
}

/// Word cards whose word appears in [ex]'s question, passage or options:
/// the cards a "Kelimeyi bilmiyordum" adds. [course]'s vocabulary lessons
/// and [ydsCards] count whether or not the learner reached them.
List<WordCard> wordsInQuestion(Exercise ex, Course course, {List<VocabEntry> ydsCards = const []}) {
  final everything = Progress(
    completed: {
      for (final n in course.allNodes)
        if (n.type == NodeType.lesson) n.id: 1,
    },
  );
  final text = [ex.question, ex.passage, ex.text, ...ex.options].whereType<String>().join(' ').toLowerCase();
  final words = text.split(RegExp(r"[^a-z'\-]+")).toSet();
  return [
    for (final c in courseWordCards(course, everything, ydsCards: ydsCards))
      if (c.en.contains(' ') ? text.contains(c.en.toLowerCase()) : words.contains(c.en.toLowerCase())) c,
  ];
}

/// The unit holding notebook question [key].
Unit? unitOfItem(Course course, String key) {
  final node = key.contains('#') ? key.substring(0, key.lastIndexOf('#')) : key;
  return course.units.where((u) => u.nodes.any((n) => n.id == node)).firstOrNull;
}

/// Up to [count] questions of [unit] (its lessons and test), for "o üniteden
/// 10 soru".
List<LessonItem> unitQuestions(Unit unit, {int count = 10}) {
  final items = [
    for (final n in unit.nodes)
      if (n.type == NodeType.lesson || n.type == NodeType.test)
        for (final it in lessonItems(n))
          if (it.ex.type != ExerciseType.speak && it.ex.type != ExerciseType.match) it,
  ]..shuffle();
  return items.take(count).toList();
}
