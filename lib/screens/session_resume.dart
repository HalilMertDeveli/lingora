import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/course_repository.dart';
import '../data/practice.dart';
import '../data/resume.dart';
import '../models/course.dart';
import 'lesson_screen.dart';
import 'story_screen.dart';

/// Shown when a saved session opens again after a cold start.
const resumeMessage = 'Kaldığın yerden devam ediyorsun';

/// The screen [record] was saved from, rebuilt from [course] at the saved
/// question; null when its content is gone.
Widget? restoredScreen(ResumeRecord record, Course course) {
  final lesson = record.lesson;
  if (lesson != null) {
    final queue = resolveItems(course, lesson.queue);
    if (queue == null) return null;
    final items = queue.take(lesson.total).toList();
    LessonScreen build({LessonResume? resume, List<LessonItem>? fresh}) => LessonScreen(
      nodeId: lesson.nodeId,
      title: lesson.title,
      items: fresh ?? items,
      color: Color(lesson.color),
      mode: lesson.mode,
      rewardXp: lesson.rewardXp,
      badge: lesson.badge,
      passHeadline: lesson.passHeadline,
      logSource: lesson.logSource,
      readingWords: lesson.readingWords,
      resume: resume,
      // A failed test starts over with the same questions, reshuffled.
      retry: lesson.mode == LessonMode.test ? () => build(fresh: [...items]..shuffle(Random())) : null,
    );
    return build(resume: (snapshot: lesson, requeued: queue.skip(lesson.total).toList()));
  }
  final story = record.story!;
  final node = course.allNodes.where((n) => n.id == story.nodeId).firstOrNull;
  if (node == null || node.type != NodeType.story || node.steps.isEmpty || story.shown >= node.steps.length) {
    return null;
  }
  return StoryScreen(node: node, color: Color(story.color), resume: story);
}

/// Reopens the session saved before the app was killed, if there is a
/// recent one for the current track. Anything that cannot be restored is
/// dropped silently. Returns whether a session was opened.
Future<bool> resumeSavedSession(BuildContext context, WidgetRef ref) async {
  final store = ref.read(resumeStoreProvider);
  final record = store.load();
  if (record == null) return false;
  if (record.trackId != ref.read(trackProvider).id) {
    store.clear();
    return false;
  }
  Course course;
  try {
    course = await ref.read(courseProvider.future);
  } catch (_) {
    return false; // keep the record: the course may load next time
  }
  if (!context.mounted) return false;
  final screen = restoredScreen(record, course);
  if (screen == null) {
    store.clear();
    return false;
  }
  final nav = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.maybeOf(context);
  nav.push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => screen));
  messenger?.showSnackBar(
    const SnackBar(
      key: Key('resume-snack'),
      content: Text(resumeMessage),
      duration: Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      // Above the lesson's "Kontrol et" bar, which stays usable.
      margin: EdgeInsets.fromLTRB(16, 0, 16, 104),
    ),
  );
  return true;
}
