import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/course_repository.dart';
import '../data/practice.dart';
import '../data/progress.dart';
import '../models/course.dart';
import '../models/exam.dart';
import 'question_types.dart';
import 'study_state.dart';

/// Unit id of each node of [course].
Map<String, String> unitOfNodes(Course course) => {
  for (final u in course.units)
    for (final n in u.nodes) n.id: u.id,
};

final _unitIndexProvider = Provider<Map<String, String>>((ref) {
  final course = ref.watch(courseProvider).value;
  return course == null ? const {} : unitOfNodes(course);
});

/// Ids of the open course's vocabulary lessons.
final _vocabLessonsProvider = Provider<Set<String>>((ref) {
  final course = ref.watch(courseProvider).value;
  return {...?course?.allNodes.where((n) => n.vocab).map((n) => n.id)};
});

/// Node id of an item key ("nodeId#index").
String nodeOfKey(String itemKey) {
  final hash = itemKey.lastIndexOf('#');
  return hash < 0 ? itemKey : itemKey.substring(0, hash);
}

/// Logs a lesson answer with its type, topic and time. Speaking is left out
/// (it can be skipped).
void recordLessonAnswer(
  WidgetRef ref, {
  required LessonItem item,
  required bool correct,
  required Duration time,
  required String source,
}) {
  // Speaking, shadowing and writing are not scored questions.
  if (const {ExerciseType.speak, ExerciseType.shadow, ExerciseType.write}.contains(item.ex.type)) return;
  final unitId = ref.read(_unitIndexProvider)[nodeOfKey(item.key)];
  ref.read(studyLogProvider.notifier).add([
    AnswerLog(
      key: item.key,
      day: dayKey(ref.read(clockProvider)()),
      correct: correct,
      seconds: time.inSeconds,
      type:
          exerciseType(
            item.ex,
            unitId: unitId,
            vocabLesson: ref.read(_vocabLessonsProvider).contains(nodeOfKey(item.key)),
          )?.name ??
          item.ex.type.name,
      unitId: unitId,
      source: source,
    ),
  ]);
}

/// Logs the answers of a finished exam session: per question its type, time
/// and whether it was right or left blank.
void recordExamAnswers(
  WidgetRef ref, {
  required List<ExamQuestion> questions,
  required Map<int, int> answers,
  required Map<int, Duration> times,
  required String source,
}) {
  final units = ref.read(_unitIndexProvider);
  final today = dayKey(ref.read(clockProvider)());
  ref.read(studyLogProvider.notifier).add([
    for (var i = 0; i < questions.length; i++)
      AnswerLog(
        key: questions[i].id,
        day: today,
        correct: answers[i] == questions[i].answer,
        blank: answers[i] == null,
        seconds: (times[i] ?? Duration.zero).inSeconds,
        unitId: units[nodeOfKey(questions[i].id)],
        type: examQuestionType(questions[i], unitId: units[nodeOfKey(questions[i].id)]).name,
        source: source,
      ),
  ]);
}
