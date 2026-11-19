import '../goals/learn_goal.dart';

/// "Bugün ne yapacağım?": the day's short sequence on the Öğren tab, e.g.
/// "5 dk tekrar → 1 ders → kısa dinleme". Built from what is really due:
/// reviews waiting today, the next lesson on the path and the learner's
/// goal. A step is done only by the real thing (cards graded today, a
/// lesson finished today, a text read today…), never by opening it.
enum TodayStepKind {
  review('Tekrar', 5),
  lesson('Ders', 5),
  listening('Kısa dinleme', 3),
  reading('Kısa okuma', 4);

  const TodayStepKind(this.label, this.minutes);
  final String label;

  /// About how long the step takes.
  final int minutes;
}

class TodayStep {
  const TodayStep({required this.kind, required this.title, required this.detail, required this.done});

  final TodayStepKind kind;

  /// Short name in the sequence line ("5 dk tekrar", "1 ders").
  final String title;

  /// What exactly ("12 kart", the lesson's name).
  final String detail;
  final bool done;
}

class TodaySequence {
  const TodaySequence(this.steps);
  final List<TodayStep> steps;

  bool get isEmpty => steps.isEmpty;
  int get doneCount => steps.where((s) => s.done).length;
  bool get allDone => steps.isNotEmpty && doneCount == steps.length;
  TodayStep? get next => steps.where((s) => !s.done).firstOrNull;
  int get minutesLeft => steps.where((s) => !s.done).fold(0, (a, s) => a + s.kind.minutes);

  /// "5 dk tekrar → 1 ders → kısa dinleme".
  String get summary => steps.map((s) => s.title).join(' → ');
}

/// What today looks like, from real data (see todaySequenceProvider).
class TodayInputs {
  const TodayInputs({
    this.cardsDue = 0,
    this.mistakesDue = 0,
    this.reviewedToday = 0,
    this.nextLesson,
    this.lessonsToday = 0,
    this.listening,
    this.listenedToday = false,
    this.readingWordsToday = 0,
    this.goal,
  });

  /// Spaced-repetition cards waiting today.
  final int cardsDue;

  /// Error-notebook questions due today.
  final int mistakesDue;

  /// Cards graded and notebook questions answered today.
  final int reviewedToday;

  /// Title of the next lesson on the path (null: none left).
  final String? nextLesson;

  /// Lessons finished today.
  final int lessonsToday;

  /// Title of a listening piece open on the path (null: none).
  final String? listening;

  /// A listening piece was finished today.
  final bool listenedToday;
  final int readingWordsToday;
  final GoalKind? goal;
}

TodaySequence buildTodaySequence(TodayInputs i) {
  final steps = <TodayStep>[];
  // 1. Review: whatever is due, or what was already reviewed today.
  final dueNow = i.cardsDue + i.mistakesDue;
  if (dueNow > 0 || i.reviewedToday > 0) {
    steps.add(
      TodayStep(
        kind: TodayStepKind.review,
        title: '5 dk tekrar',
        detail: dueNow == 0
            ? 'Bugünkü tekrar bitti'
            : i.cardsDue > 0
            ? '${i.cardsDue} kart'
            : '${i.mistakesDue} hata sorusu',
        done: dueNow == 0 && i.reviewedToday > 0,
      ),
    );
  }
  // 2. The next lesson on the path.
  if (i.nextLesson != null || i.lessonsToday > 0) {
    steps.add(
      TodayStep(
        kind: TodayStepKind.lesson,
        title: '1 ders',
        detail: i.lessonsToday > 0 && i.nextLesson == null ? 'Bugünkü ders bitti' : i.nextLesson ?? '',
        done: i.lessonsToday > 0,
      ),
    );
  }
  // 3. By goal: an exam learner reads (YDS is reading-heavy); everyone else
  // listens when a piece is open, else reads.
  final read = i.goal == GoalKind.exam || (i.listening == null && !i.listenedToday);
  steps.add(
    read
        ? TodayStep(
            kind: TodayStepKind.reading,
            title: 'kısa okuma',
            detail: 'Okuma evinden bir metin',
            done: i.readingWordsToday > 0,
          )
        : TodayStep(
            kind: TodayStepKind.listening,
            title: 'kısa dinleme',
            detail: i.listening ?? 'Bugünkü dinleme bitti',
            done: i.listenedToday,
          ),
  );
  return TodaySequence(steps);
}
