import 'dart:math';

import 'progress.dart' show reviewIntervals;

/// How well a flipped review card was remembered ("Tekrar kartları").
/// [good] and [again] match `ProgressNotifier.reviewWord(known: …)`; [hard]
/// keeps the word in its box but brings it back sooner, [easy] skips a box.
enum ReviewGrade {
  again('Bilmiyordum'),
  hard('Zor'),
  good('Bildim'),
  easy('Kolay');

  const ReviewGrade(this.label);
  final String label;

  /// Counts as "known" in the session summary.
  bool get known => this != again;
}

/// The box a word moves to and the days until it comes back, from its
/// current [box] (null: a new word).
({int box, int days}) scheduleReview(int? box, ReviewGrade grade) {
  final old = box ?? 0;
  final last = reviewIntervals.length - 1;
  switch (grade) {
    case ReviewGrade.again:
      final b = max(0, old - 2);
      return (box: b, days: reviewIntervals[b]);
    case ReviewGrade.hard:
      return (box: old, days: max(1, reviewIntervals[old] ~/ 2));
    case ReviewGrade.good:
      final b = min(old + 1, last);
      return (box: b, days: reviewIntervals[b]);
    case ReviewGrade.easy:
      final b = min(old + 2, last);
      return (box: b, days: reviewIntervals[b]);
  }
}

/// "bugün", "3 gün", "2 ay".
String intervalLabel(int days) {
  if (days <= 0) return 'bugün';
  if (days < 30) return '$days gün';
  return '${days ~/ 30} ay';
}
