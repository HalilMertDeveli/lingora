import '../data/progress.dart';
import 'learning_evidence.dart';
import 'study_state.dart';

/// "Gerçek ilerleme": what the learner can now do, from real answers only.
/// No XP, no percentages, no estimates: every number is a count of things
/// that happened and can be checked in the logs.

/// Questions missed in a recent window and asked again on a later day.
class MistakeTurnaround {
  const MistakeTurnaround({required this.missed, required this.retried, required this.nowRight});

  /// Different questions answered wrong in the window.
  final int missed;

  /// Of those, the ones answered again on a later day than a miss.
  final int retried;

  /// Of the retried ones, those whose latest answer is right (and no wrong
  /// answer on that same day: getting it right minutes after seeing the
  /// solution does not count).
  final int nowRight;
}

/// Looks at answers from the last [days] days up to [today] (day keys).
MistakeTurnaround mistakeTurnaround(List<AnswerLog> answers, {required String today, int days = 7}) {
  final start = dayKey(DateTime.parse(today).subtract(Duration(days: days)));
  final byKey = <String, List<AnswerLog>>{};
  for (final a in answers) {
    if (a.blank) continue;
    byKey.putIfAbsent(a.key, () => []).add(a);
  }
  var missed = 0, retried = 0, nowRight = 0;
  for (final list in byKey.values) {
    final firstMiss = list.indexWhere(
      (a) => !a.correct && a.day.compareTo(start) >= 0 && a.day.compareTo(today) <= 0,
    );
    if (firstMiss < 0) continue;
    missed++;
    final missDay = list[firstMiss].day;
    final later = list.skip(firstMiss + 1).where((a) => a.day.compareTo(missDay) > 0);
    if (later.isEmpty) continue;
    retried++;
    final last = list.last;
    final wrongThatDay = list.any((a) => a.day == last.day && !a.correct);
    if (last.correct && !wrongThatDay) nowRight++;
  }
  return MistakeTurnaround(missed: missed, retried: retried, nowRight: nowRight);
}

class RealProgress {
  const RealProgress({
    required this.wordsPassed,
    required this.wordsPassedThisWeek,
    required this.mistakesCleared,
    required this.turnaround,
  });

  /// Words that passed at least one spaced review.
  final int wordsPassed;
  final int wordsPassedThisWeek;

  /// Questions taken out of the error notebook by right answers on the days
  /// they came back.
  final int mistakesCleared;
  final MistakeTurnaround turnaround;

  bool get isEmpty => wordsPassed == 0 && mistakesCleared == 0 && turnaround.missed == 0;
}

RealProgress realProgress(LearningEvidence e, StudyLog log, DateTime now) {
  final today = dayKey(now);
  final weekAgo = dayKey(now.subtract(const Duration(days: 6)));
  return RealProgress(
    wordsPassed: e.wordsPassed.length,
    wordsPassedThisWeek: e.wordsPassed.values.where((d) => d.compareTo(weekAgo) >= 0).length,
    mistakesCleared: e.mistakesCleared.length,
    turnaround: mistakeTurnaround(log.answers, today: today),
  );
}

/// The sentence about recent mistakes, or null when there were none.
String? turnaroundSentence(MistakeTurnaround t) {
  if (t.missed == 0) return null;
  if (t.retried == 0) {
    return 'Son 7 günde karıştırdığın ${t.missed} soru henüz yeniden sorulmadı. '
        'Hatalarını çalış\'ta sırası gelince döner.';
  }
  return 'Son 7 günde karıştırıp sonraki bir gün yeniden çözdüğün ${t.retried} sorunun '
      '${t.nowRight}\'${_suffix(t.nowRight)} artık doğru yapıyorsun.';
}

/// Turkish accusative suffix after a numeral ("4'ünü", "5'ini", "0'ını").
String _suffix(int n) {
  final last = n % 10;
  final tens = (n ~/ 10) % 10;
  if (n == 0) return 'ını';
  if (last == 0) {
    return switch (tens) {
      1 || 3 => 'unu', // on, otuz
      2 || 5 => 'sini', // yirmi, elli
      4 || 6 => 'ını', // kırk, altmış
      7 || 8 => 'ini', // yetmiş, seksen
      9 => 'ını', // doksan
      _ => 'ünü', // yüz
    };
  }
  return switch (last) {
    1 || 5 || 8 => 'ini', // bir, beş, sekiz
    2 => 'sini', // iki
    3 || 4 => 'ünü', // üç, dört
    6 => 'sını', // altı
    7 => 'sini', // yedi
    _ => 'unu', // dokuz
  };
}
