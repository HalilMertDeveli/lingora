import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/break_reminder.dart';
import 'package:lingora/data/catalog.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/screens/lesson_result_screen.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/ui/mascot.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  AppMode mode = AppMode.kid,
  Brightness b = Brightness.light,
}) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(mode: mode, brightness: b),
      builder: (_, c) => PaletteScope(palette: Palette.of(mode, b), child: c!),
      home: child,
    ),
  );
  await tester.pump();
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

const _reward = LessonReward(xp: 15, streak: 3, streakExtended: false, todayXp: 15, dailyGoal: 20);

void main() {
  test('every pose has an image asset declared in pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/mascot/'));
    for (final pose in PofuPose.values) {
      expect(File(pose.asset).existsSync(), isTrue, reason: pose.asset);
    }
    expect(File('assets/mascot/face.png').existsSync(), isTrue);
    expect(File('assets/brand/google_g.png').existsSync(), isTrue);
    for (final t in courseCatalog) {
      if (t.flag != null) expect(File(t.flag!).existsSync(), isTrue, reason: t.flag);
    }
  });

  test('moods map to the agreed poses', () {
    expect(PofuPose.of(Mood.cheer), PofuPose.cool);
    expect(PofuPose.of(Mood.happy), PofuPose.hello);
    expect(PofuPose.of(Mood.idle), PofuPose.hello);
    expect(PofuPose.of(Mood.calm), PofuPose.calm);
    expect(PofuPose.of(Mood.sad), PofuPose.sad);
    expect(PofuPose.of(Mood.think), PofuPose.point);
    expect(PofuPose.of(Mood.joy), PofuPose.dance);
  });

  group('Mascot', () {
    testWidgets('kid mode: big, animated Pofu', (tester) async {
      await _pump(
        tester,
        const Scaffold(
          body: Center(child: Mascot(mood: Mood.cheer, size: 150)),
        ),
      );
      final pofu = tester.widget<Pofu>(find.byType(Pofu));
      expect(pofu.animate, isTrue);
      expect(tester.getSize(find.byType(Pofu)), const Size(150, 150));
      expect(find.byKey(const ValueKey('pofu-cool')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('adult mode: small and still; decorative ones hidden', (tester) async {
      await _pump(
        tester,
        const Scaffold(
          body: Column(
            children: [
              Mascot(mood: Mood.happy, size: 150),
              Mascot(mood: Mood.joy, size: 150, decorative: true),
            ],
          ),
        ),
        mode: AppMode.adult,
      );
      expect(find.byType(Pofu), findsOneWidget);
      expect(tester.widget<Pofu>(find.byType(Pofu)).animate, isFalse);
      expect(tester.getSize(find.byType(Pofu)).width, 72);
      expect(find.byKey(const ValueKey('pofu-hello')), findsOneWidget);
    });

    for (final b in Brightness.values) {
      testWidgets('dark themes give Pofu a light spot (${b.name})', (tester) async {
        await _pump(
          tester,
          const Scaffold(body: Mascot(mood: Mood.calm)),
          b: b,
        );
        final spot = find.descendant(
          of: find.byKey(const ValueKey('pofu-calm')),
          matching: find.byWidgetPredicate(
            (w) => w is DecoratedBox && (w.decoration as BoxDecoration).color == Palette.mascotSpot,
          ),
        );
        expect(spot, b == Brightness.dark ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('EmptyState shows Pofu with the message', (tester) async {
      await _pump(tester, const Scaffold(body: EmptyState(message: 'Şu an tekrar edilecek kelime yok.')));
      expect(find.text('Şu an tekrar edilecek kelime yok.'), findsOneWidget);
      expect(find.byKey(const ValueKey('pofu-calm')), findsOneWidget);
    });
  });

  group('end of lesson', () {
    for (final (accuracy, perfect, pose) in [
      (100, true, 'cool'),
      (92, false, 'cool'),
      (70, false, 'hello'),
    ]) {
      testWidgets('accuracy $accuracy shows Pofu $pose', (tester) async {
        await _pump(
          tester,
          LessonResultScreen(
            reward: _reward,
            accuracy: accuracy,
            duration: const Duration(minutes: 3),
            perfect: perfect,
          ),
        );
        expect(find.byKey(ValueKey('pofu-$pose')), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
      });
    }

    testWidgets('streak and break screens use calm Pofu', (tester) async {
      await _pump(tester, const StreakCelebrationScreen(streak: 4));
      expect(find.byKey(const ValueKey('pofu-calm')), findsOneWidget);
      await _pump(tester, const BreakReminderScreen());
      expect(find.text('Kısa bir mola?'), findsOneWidget);
      expect(find.byKey(const ValueKey('pofu-calm')), findsOneWidget);
    });
  });

  test('BreakTracker suggests a break after 3 lessons or 20 minutes', () {
    final t = BreakTracker();
    expect(t.recordLesson(const Duration(minutes: 3)), isFalse);
    expect(t.recordLesson(const Duration(minutes: 3)), isFalse);
    expect(t.recordLesson(const Duration(minutes: 3)), isTrue);
    expect(t.recordLesson(const Duration(minutes: 3)), isFalse, reason: 'counters restart');
    expect(t.recordLesson(const Duration(minutes: 18)), isTrue);
  });

  test('Pofu orange is readable in every palette', () {
    for (final p in [Palette.adultLight, Palette.adultDark, Palette.kidLight, Palette.kidDark]) {
      expect(
        _contrast(p.mascot, p.onMascot),
        greaterThanOrEqualTo(4.5),
        reason: 'button text ${p.brightness}',
      );
      expect(
        _contrast(p.mascot, p.card),
        greaterThanOrEqualTo(4.5),
        reason: 'links on cards ${p.brightness}',
      );
      expect(_contrast(p.mascot, p.mascotBg), greaterThanOrEqualTo(3), reason: 'icons in inputs');
      expect(_contrast(p.ink, p.mascotBg), greaterThanOrEqualTo(7), reason: 'input text');
    }
  });
}
