import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/practice.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/resume.dart';
import 'package:lingora/main.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/nav/nav_target.dart';
import 'package:lingora/screens/lesson_result_screen.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/screens/session_resume.dart';
import 'package:lingora/screens/story_screen.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeNotifications, FakeSpeech;

final _course = Course.fromJson(
  jsonDecode(File('assets/courses/tr_en.json').readAsStringSync()) as Map<String, dynamic>,
);
final _now = DateTime(2026, 11, 16, 9);
final _onboarded = jsonEncode(const Progress(onboarded: true, remindersEnabled: false).toJson());

/// Starts the app the way a cold start does: a fresh widget tree over
/// [values], the only thing that survives the process.
Future<void> _start(WidgetTester tester, Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      // A new scope is a new process: no provider state carries over.
      key: UniqueKey(),
      overrides: [
        courseProvider.overrideWith((ref) async => _course),
        courseOutlineProvider.overrideWith((ref) async => _course),
        prefsProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => _now),
        speechProvider.overrideWithValue(FakeSpeech()),
        notificationServiceProvider.overrideWithValue(FakeNotifications()),
      ],
      child: const LingoraApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Home button, then Android kills the process: the tree goes away while the
/// app is in the background. Returns what shared_preferences kept.
Future<Map<String, Object>> _killInBackground(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pumpWidget(const SizedBox());
  final prefs = await SharedPreferences.getInstance();
  final kept = {for (final k in prefs.getKeys()) k: prefs.get(k)!};
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  return kept;
}

Future<String?> _saved() async => (await SharedPreferences.getInstance()).getString(resumeKey);

Future<ResumeRecord?> _record() async {
  final raw = await _saved();
  return raw == null ? null : ResumeRecord.decode(raw);
}

String _lessonRecord({
  required List<String> queue,
  required int total,
  required int pos,
  LessonMode mode = LessonMode.lesson,
  String nodeId = 'u1l1',
  String title = 'Selamlaşma',
  int answered = 0,
  int mistakes = 0,
  int solved = 0,
  DateTime? savedAt,
  String trackId = 'tr_en',
}) => ResumeRecord(
  trackId: trackId,
  savedAt: savedAt ?? _now.subtract(const Duration(minutes: 5)),
  lesson: LessonSnapshot(
    nodeId: nodeId,
    title: title,
    color: 0xFF58CC02,
    mode: mode,
    queue: queue,
    total: total,
    pos: pos,
    answered: answered,
    mistakes: mistakes,
    solved: solved,
  ),
).encode();

final _u1l1 = [for (var i = 0; i < 8; i++) 'u1l1#$i'];

/// Top-to-bottom, left-to-right order of [texts] on screen.
List<String> _order(WidgetTester tester, List<String> texts) {
  final placed = [for (final t in texts) (t, tester.getTopLeft(find.text(t).last))];
  placed.sort((a, b) => a.$2.dy != b.$2.dy ? a.$2.dy.compareTo(b.$2.dy) : a.$2.dx.compareTo(b.$2.dx));
  return [for (final p in placed) p.$1];
}

void main() {
  group('ResumeRecord', () {
    test('round-trips a lesson and a story', () {
      final lesson = ResumeRecord.decode(
        _lessonRecord(queue: [..._u1l1, 'u1l1#0'], total: 8, pos: 3, answered: 4, mistakes: 1),
      )!;
      expect(lesson.trackId, 'tr_en');
      expect(lesson.lesson!.queue, hasLength(9));
      expect(lesson.lesson!.pos, 3);
      expect(lesson.lesson!.mistakes, 1);
      expect(lesson.story, isNull);

      final story = ResumeRecord.decode(
        ResumeRecord(
          trackId: 'tr_en',
          savedAt: _now,
          story: const StorySnapshot(nodeId: 'u1s', color: 1, shown: 4, questions: 1, wrong: 2, rate: 0.75),
        ).encode(),
      )!;
      expect(story.story!.shown, 4);
      expect(story.story!.wrong, 2);
      expect(story.story!.rate, 0.75);
    });

    test('rejects malformed records', () {
      expect(ResumeRecord.decode('not json'), isNull);
      expect(ResumeRecord.decode('{"v": 2}'), isNull);
      expect(ResumeRecord.decode('{"v": 1, "trackId": "tr_en", "savedAt": 0}'), isNull);
      // pos past the queue
      expect(ResumeRecord.decode(_lessonRecord(queue: _u1l1, total: 8, pos: 12)), isNull);
    });

    test('store drops stale and unreadable records', () async {
      SharedPreferences.setMockInitialValues({
        resumeKey: _lessonRecord(
          queue: _u1l1,
          total: 8,
          pos: 1,
          savedAt: _now.subtract(const Duration(hours: 13)),
        ),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = ResumeStore(prefs, () => _now);
      expect(store.load(), isNull);
      expect(prefs.containsKey(resumeKey), isFalse);

      await prefs.setString(resumeKey, '{broken');
      expect(store.load(), isNull);
      expect(prefs.containsKey(resumeKey), isFalse);

      await prefs.setString(
        resumeKey,
        _lessonRecord(queue: _u1l1, total: 8, pos: 1, savedAt: _now.subtract(const Duration(hours: 11))),
      );
      expect(store.load(), isNotNull);
    });

    test('restoredScreen needs every item to still exist', () {
      ResumeRecord rec(List<String> queue) =>
          ResumeRecord.decode(_lessonRecord(queue: queue, total: queue.length, pos: 0))!;
      expect(restoredScreen(rec(_u1l1), _course), isA<LessonScreen>());
      expect(restoredScreen(rec(['u1l1#0', 'gone#0']), _course), isNull);
      expect(restoredScreen(rec(['u1l1#99']), _course), isNull);
      final story = ResumeRecord(
        trackId: 'tr_en',
        savedAt: _now,
        story: const StorySnapshot(nodeId: 'u1l1', color: 1), // not a story
      );
      expect(restoredScreen(story, _course), isNull);
    });
  });

  group('kaldığın yerden devam', () {
    testWidgets('a lesson killed in the background reopens at the same question', (tester) async {
      await _start(tester, {'progress_v1': _onboarded});
      await tester.tap(find.text('Hadi, bir çay daha!'));
      await tester.pumpAndSettle();
      expect((await _record())!.lesson!.pos, 0, reason: 'saved as soon as it opens');

      // Q1 wrong (it comes back at the end), then on to Q2.
      await tester.tap(find.text('coffee'));
      await tester.pump();
      await tester.tap(find.text('Kontrol et'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      expect(find.text('Bu cümleyi çevir'), findsOneWidget);
      const tokens = ['Hello', 'Goodbye', 'Thanks', 'Night'];
      final before = _order(tester, tokens);

      final kept = await _killInBackground(tester);
      expect(kept[resumeKey], isNotNull);

      await _start(tester, kept);
      expect(find.byType(LessonScreen), findsOneWidget);
      expect(find.text('Bu cümleyi çevir'), findsOneWidget);
      expect(find.text('0/8'), findsOneWidget);
      expect(find.text(resumeMessage), findsOneWidget);
      // Same exercise, same option order.
      expect(_order(tester, tokens), before);
      final rec = (await _record())!.lesson!;
      expect(rec.pos, 1);
      expect(rec.queue, [..._u1l1, 'u1l1#0']);
      expect(rec.answered, 1);
      expect(rec.mistakes, 1);

      // Back from the lesson: the path is underneath.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Çık'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bottom-nav')), findsOneWidget);
    });

    testWidgets('killed while the answer feedback shows: the next question opens', (tester) async {
      await _start(tester, {'progress_v1': _onboarded});
      await tester.tap(find.text('Hadi, bir çay daha!'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('hello'));
      await tester.pump();
      await tester.tap(find.text('Kontrol et'));
      await tester.pumpAndSettle();
      expect(find.text('Devam'), findsOneWidget);

      await _start(tester, await _killInBackground(tester));
      expect(find.text('Bu cümleyi çevir'), findsOneWidget);
      expect(find.text('1/8'), findsOneWidget);
    });

    testWidgets('quitting with X removes the record', (tester) async {
      await _start(tester, {'progress_v1': _onboarded});
      await tester.tap(find.text('Hadi, bir çay daha!'));
      await tester.pumpAndSettle();
      expect(await _saved(), isNotNull);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Çık'));
      await tester.pumpAndSettle();
      expect(await _saved(), isNull);

      await _start(tester, await _killInBackground(tester));
      expect(find.byType(LessonScreen), findsNothing);
      expect(find.text(resumeMessage), findsNothing);
    });

    testWidgets('finishing removes the record', (tester) async {
      // Killed right after the last answer: the result is all that is left.
      await _start(tester, {
        'progress_v1': _onboarded,
        resumeKey: _lessonRecord(queue: _u1l1, total: 8, pos: 8, answered: 8, solved: 8),
      });
      expect(find.byType(LessonResultScreen), findsOneWidget);
      expect(await _saved(), isNull);
      final progress = (await SharedPreferences.getInstance()).getString('progress_v1')!;
      expect(progress, contains('u1l1'));
    });

    testWidgets('stale, broken, other-track and missing-content records are ignored', (tester) async {
      for (final record in [
        _lessonRecord(queue: _u1l1, total: 8, pos: 2, savedAt: _now.subtract(const Duration(hours: 13))),
        '{"v": 1, "lesson": 42}',
        _lessonRecord(queue: _u1l1, total: 8, pos: 2, trackId: 'other_track'),
        _lessonRecord(queue: ['nope#0', 'nope#1'], total: 2, pos: 1),
      ]) {
        await _start(tester, {'progress_v1': _onboarded, resumeKey: record});
        expect(find.byType(LessonScreen), findsNothing, reason: record);
        expect(find.byKey(const Key('bottom-nav')), findsOneWidget);
        expect(await _saved(), isNull, reason: record);
      }
    });

    testWidgets('practice (Hatalarını çalış) resumes in practice mode', (tester) async {
      await _start(tester, {
        'progress_v1': _onboarded,
        resumeKey: _lessonRecord(
          queue: ['u1l1#0', 'u1l2#0', 'u1l1#2'],
          total: 3,
          pos: 1,
          mode: LessonMode.practice,
          nodeId: 'practice',
          title: 'Hatalarını çalış',
          answered: 1,
          solved: 1,
        ),
      });
      expect(find.byType(LessonScreen), findsOneWidget);
      expect(find.text('HATALARINI ÇALIŞ'), findsOneWidget);
      final screen = tester.widget<LessonScreen>(find.byType(LessonScreen));
      expect(screen.mode, LessonMode.practice);
      expect([for (final it in screen.items) it.key], ['u1l1#0', 'u1l2#0', 'u1l1#2']);
      expect((await _record())!.lesson!.pos, 1);
    });

    testWidgets('a story resumes at its step', (tester) async {
      await _start(tester, {
        'progress_v1': _onboarded,
        resumeKey: ResumeRecord(
          trackId: 'tr_en',
          savedAt: _now,
          story: const StorySnapshot(nodeId: 'u1s', color: 0xFF58CC02, shown: 3),
        ).encode(),
      });
      expect(find.byType(StoryScreen), findsOneWidget);
      expect(find.text('Yeni arkadaşın adı ne?'), findsOneWidget);
      await tester.tap(find.text('Sam').last);
      await tester.pumpAndSettle();
      expect((await _record())!.story!.pickedRight, isTrue);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(await _saved(), isNull);
    });

    testWidgets('the selected tab survives process death', (tester) async {
      await _start(tester, {'progress_v1': _onboarded});
      await tester.tap(find.byKey(Key('tab-${AppTab.profile.name}')));
      await tester.pumpAndSettle();

      await _start(tester, await _killInBackground(tester));
      final bar = tester.widget<NavigationBar>(find.byKey(const Key('bottom-nav')));
      final labels = [for (final d in bar.destinations) (d as NavigationDestination).label];
      expect(labels[bar.selectedIndex], AppTab.profile.label);
    });
  });
}
