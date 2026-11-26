import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/app_settings.dart';
import 'package:lingora/data/catalog.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/course_shelf.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/vocab_practice.dart';
import 'package:lingora/main.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/models/vocab.dart';
import 'package:lingora/nav/course_badge.dart';
import 'package:lingora/screens/my_courses_screen.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/ui/first_tour.dart';
import 'package:lingora/ui/mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeNotifications, FakeSpeech;

Course _load(String id) =>
    Course.fromJson(jsonDecode(File('assets/courses/$id.json').readAsStringSync()) as Map<String, dynamic>);

final _general = _load('tr_en');
final _dev = _load('pro_dev');
final _vocab = VocabBundle.fromJson(
  jsonDecode(File('assets/vocab/software.json').readAsStringSync()) as Map<String, dynamic>,
);
final _now = DateTime(2026, 11, 17, 9);

/// Pumps the onboarded app with [progress] and the shelf in [shelf].
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Progress? progress,
  CourseShelf? shelf,
  String mode = 'adult',
  bool animations = false,
  bool settle = true,
}) async {
  final p = progress ?? const Progress(onboarded: true, remindersEnabled: false);
  SharedPreferences.setMockInitialValues({
    'progress_v1': jsonEncode(p.toJson()),
    AppSettingsNotifier.key: jsonEncode({'mode': mode, 'theme': 'light'}),
    if (shelf != null) CourseShelfNotifier.key: jsonEncode(shelf.toJson()),
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 860));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: !animations);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final container = ProviderContainer(
    overrides: [
      courseProvider.overrideWith((ref) async => _general),
      courseOutlineProvider.overrideWith((ref) async => _general),
      trackOutlineProvider.overrideWith(
        (ref, id) async => switch (id) {
          'tr_en' => _general,
          'pro_dev' => _dev,
          _ => null,
        },
      ),
      vocabProvider.overrideWith((ref) async => _vocab),
      prefsProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => _now),
      speechProvider.overrideWithValue(FakeSpeech()),
      notificationServiceProvider.overrideWithValue(FakeNotifications()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const LingoraApp()));
  if (settle) await tester.pumpAndSettle();
  return container;
}

const _noHint = CourseShelf(hintArmed: false);

final _screen = find.byKey(const Key('courses-screen'));

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('topbar-track')));
  await tester.pumpAndSettle();
  expect(_screen, findsOneWidget);
}

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    200,
    scrollable: find.descendant(of: _screen, matching: find.byType(Scrollable)),
  );
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

void main() {
  group('shelf model', () {
    test('followed courses: current first, then by last study, unknown ids dropped', () {
      final ids = followedTrackIds(
        current: 'pro_dev',
        shelf: const CourseShelf(added: ['yds', 'gone', 'lgs'], lastStudied: {'lgs': 20, 'yds': 10}),
        withProgress: {'tr_en'},
      );
      expect(ids, ['pro_dev', 'lgs', 'yds', 'tr_en']);
    });

    test('last study labels', () {
      final now = DateTime(2026, 11, 17, 9);
      int ago(int days) => now.subtract(Duration(days: days)).millisecondsSinceEpoch;
      expect(lastStudiedLabel(null, now), 'Henüz çalışılmadı');
      expect(lastStudiedLabel(ago(0), now), 'Son çalışma: bugün');
      expect(lastStudiedLabel(ago(1), now), 'Son çalışma: dün');
      expect(lastStudiedLabel(ago(3), now), 'Son çalışma: 3 gün önce');
      expect(lastStudiedLabel(ago(15), now), 'Son çalışma: 2 hafta önce');
    });

    test('a course studied before any path step says so, not "Henüz başlamadın"', () {
      final t = trackById('tr_en');
      expect(progressLine(t, (done: 0, total: 10)), 'Henüz başlamadın · 10 adım');
      expect(progressLine(t, (done: 0, total: 10), studied: true), 'Başladın · yolda 10 adım');
      expect(progressLine(t, (done: 5, total: 10), studied: true), '%50 tamamlandı · 5/10 adım');
    });

    test('the shelf survives a JSON round trip', () {
      const s = CourseShelf(added: ['yds'], lastStudied: {'yds': 5}, hintArmed: false);
      final back = CourseShelf.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.added, ['yds']);
      expect(back.lastStudied, {'yds': 5});
      expect(back.hintArmed, isFalse);
    });

    test('progress is counted per course from its own steps', () {
      final first = _dev.allNodes.first.id;
      final p = Progress(completed: {first: 1, _general.allNodes.first.id: 1});
      final s = trackStats(_dev, p);
      expect(s.done, 1);
      expect(s.total, _dev.allNodes.length);
    });
  });

  group('Kurslarım', () {
    testWidgets('lists the current course, followed courses and courses to add', (tester) async {
      final devNode = _dev.allNodes.first.id;
      await _pump(
        tester,
        progress: Progress(onboarded: true, remindersEnabled: false, completed: {devNode: 1}),
        shelf: CourseShelf(hintArmed: false, lastStudied: {'pro_dev': _now.millisecondsSinceEpoch}),
      );
      await _open(tester);

      expect(find.text('ŞU AN ÇALIŞTIĞIN'), findsOneWidget);
      final current = find.byKey(const Key('course-current'));
      expect(find.descendant(of: current, matching: find.text('Genel İngilizce')), findsOneWidget);
      expect(find.descendant(of: current, matching: find.text('Devam et')), findsOneWidget);

      // Yazılımcı Dersleri has progress, so it is a followed course.
      expect(find.text('DEVAM ETTİĞİN KURSLAR'), findsOneWidget);
      final dev = find.byKey(const Key('course-card-pro_dev'));
      expect(dev, findsOneWidget);
      expect(find.descendant(of: dev, matching: find.text('Son çalışma: bugün')), findsOneWidget);
      expect(find.descendant(of: dev, matching: find.textContaining('1/${_dev.allNodes.length} adım')), findsOneWidget);

      await _scrollTo(tester, find.byKey(const Key('course-add-yds')));
      expect(find.text('YENİ BİR KURS EKLE'), findsOneWidget);
      expect(find.byKey(const Key('course-add-pro_dev')), findsNothing, reason: 'already followed');
    });

    testWidgets('"Devam et" on another course switches to it and keeps every course\'s progress', (tester) async {
      final devNode = _dev.allNodes.first.id;
      final generalNode = _general.allNodes.first.id;
      final c = await _pump(
        tester,
        progress: Progress(onboarded: true, remindersEnabled: false, completed: {devNode: 1, generalNode: 2}),
        shelf: _noHint,
      );
      await _open(tester);
      await tester.tap(find.byKey(const Key('course-continue-pro_dev')));
      await tester.pumpAndSettle();

      expect(_screen, findsNothing);
      final p = c.read(progressProvider);
      expect(p.trackId, 'pro_dev');
      expect(p.completed, {devNode: 1, generalNode: 2});

      // The general course stays on the shelf and switching back keeps it.
      await _open(tester);
      expect(find.byKey(const Key('course-card-tr_en')), findsOneWidget);
      await tester.tap(find.byKey(const Key('course-continue-tr_en')));
      await tester.pumpAndSettle();
      expect(c.read(progressProvider).trackId, 'tr_en');
      expect(c.read(progressProvider).completed, {devNode: 1, generalNode: 2});
    });

    testWidgets('the current course\'s "Devam et" just closes the screen', (tester) async {
      final c = await _pump(tester, shelf: _noHint);
      await _open(tester);
      await tester.tap(find.byKey(const Key('course-continue-tr_en')));
      await tester.pumpAndSettle();
      expect(_screen, findsNothing);
      expect(c.read(progressProvider).trackId, 'tr_en');
    });

    testWidgets('adding a course shows a preview first, then starts it', (tester) async {
      final c = await _pump(tester, shelf: _noHint);
      await _open(tester);
      final add = find.byKey(const Key('course-add-yds'));
      await _scrollTo(tester, add);
      await tester.tap(add);
      await tester.pumpAndSettle();

      final preview = find.byKey(const Key('course-preview'));
      expect(preview, findsOneWidget);
      expect(find.descendant(of: preview, matching: find.text('YDS / YÖKDİL')), findsOneWidget);
      expect(find.descendant(of: preview, matching: find.textContaining('B2 → C1')), findsOneWidget);

      // Vazgeç keeps everything as it was.
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(preview, findsNothing);
      expect(c.read(progressProvider).trackId, 'tr_en');

      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('course-start')));
      await tester.pumpAndSettle();

      expect(_screen, findsNothing);
      expect(c.read(progressProvider).trackId, 'yds');
      expect(c.read(courseShelfProvider).added, containsAll(['yds', 'tr_en']));

      await _open(tester);
      expect(find.byKey(const Key('course-card-tr_en')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('course-current')), matching: find.text('YDS / YÖKDİL')),
        findsOneWidget,
      );
    });

    testWidgets('switching plays a curtain in the course colour that then clears', (tester) async {
      // With animations on the path keeps moving, so frames are pumped by hand.
      final c = await _pump(
        tester,
        shelf: const CourseShelf(added: ['pro_dev'], hintArmed: false),
        animations: true,
        settle: false,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('topbar-track')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('course-continue-pro_dev')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('course-curtain')), findsOneWidget);
      expect(find.text('Yolun hazırlanıyor'), findsOneWidget);
      expect(c.read(progressProvider).trackId, 'pro_dev');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('course-curtain')), findsNothing);
    });

    testWidgets('kid mode shows Pofuduk on the shelf, never Çaycı Dayı', (tester) async {
      await _pump(tester, shelf: _noHint, mode: 'kid');
      await _open(tester);
      expect(find.descendant(of: _screen, matching: find.byType(Pofuduk)), findsOneWidget);
      expect(find.byType(Dayi), findsNothing);
    });

    testWidgets('adult mode keeps the shelf free of the mascot', (tester) async {
      await _pump(tester, shelf: _noHint);
      await _open(tester);
      expect(find.descendant(of: _screen, matching: find.byType(Dayi)), findsNothing);
      expect(find.descendant(of: _screen, matching: find.byType(Pofuduk)), findsNothing);
    });

    testWidgets('the badge reads as a button with the course name', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, shelf: _noHint);
      expect(find.bySemanticsLabel(RegExp('^Kursun: Genel İngilizce\\. Kurslarını görmek')), findsOneWidget);
      handle.dispose();
    });
  });

  group('badge hint', () {
    final hint = find.byKey(const Key('course-hint'));

    testWidgets('shows once on first start and goes away by itself', (tester) async {
      final c = await _pump(tester, settle: false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(hint, findsOneWidget);
      expect(find.text('Kursunu buradan değiştirebilirsin'), findsOneWidget);
      expect(c.read(courseShelfProvider).hintArmed, isFalse, reason: 'shown once');

      await tester.pump(CourseBadge.hintDuration);
      await tester.pumpAndSettle();
      expect(hint, findsNothing);
    });

    testWidgets('is not shown again after it was seen', (tester) async {
      await _pump(tester, shelf: _noHint, settle: false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(hint, findsNothing);
    });

    testWidgets('a tap closes it', (tester) async {
      await _pump(tester, settle: false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(hint);
      await tester.pump();
      expect(hint, findsNothing);
    });

    testWidgets('waits for the first-run tour: none while it is up', (tester) async {
      FirstTour.enabled = true;
      addTearDown(() => FirstTour.enabled = false);
      final c = await _pump(tester, settle: false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(TourOverlay), findsOneWidget);
      expect(hint, findsNothing);
      expect(c.read(courseShelfProvider).hintArmed, isTrue, reason: 'still waiting for the tour');
    });

    testWidgets('a learner who skips the tour gets the hint right away', (tester) async {
      FirstTour.enabled = true;
      addTearDown(() => FirstTour.enabled = false);
      final first = _general.allNodes.first.id;
      await _pump(
        tester,
        progress: Progress(onboarded: true, remindersEnabled: false, completed: {first: 1}, lessonsDone: 1),
        settle: false,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(TourOverlay), findsNothing);
      expect(hint, findsOneWidget);
      await tester.pump(CourseBadge.hintDuration);
    });

    testWidgets('comes back once after a new course is added', (tester) async {
      final c = await _pump(tester, shelf: _noHint);
      await _open(tester);
      final add = find.byKey(const Key('course-add-lgs'));
      await _scrollTo(tester, add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('course-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(hint, findsOneWidget);
      expect(c.read(courseShelfProvider).hintArmed, isFalse);
      await tester.pumpAndSettle();
      expect(hint, findsNothing);
    });
  });
}
