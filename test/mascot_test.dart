import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/app_settings.dart';
import 'package:lingora/data/break_reminder.dart';
import 'package:lingora/data/catalog.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/screens/lesson_result_screen.dart';
import 'package:lingora/screens/onboarding_screen.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/ui/mascot.dart';
import 'package:lingora/ui/session.dart';

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
  test('mascot, icon, logo and flag assets exist and are declared', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/mascot/'));
    expect(File(mascotAsset).existsSync(), isTrue);
    expect(File('assets/mascot/cayci_dayi.svg').existsSync(), isTrue, reason: 'owner original kept');
    expect(File('assets/icon/icon.png').existsSync(), isTrue);
    expect(File('assets/brand/google_g.png').existsSync(), isTrue);
    for (final m in Mood.values) {
      expect(File(pofudukPose(m)).existsSync(), isTrue, reason: pofudukPose(m));
    }
    expect(File(pofudukAvatar).existsSync(), isTrue);
    expect(File(pofudukAccount).existsSync(), isTrue);
    for (final a in Accent.values) {
      expect(File(a.flag).existsSync(), isTrue, reason: a.flag);
    }
    for (final c in guestCountries.keys) {
      expect(File(flagAsset(c)).existsSync(), isTrue, reason: c);
    }
    for (final t in courseCatalog) {
      if (t.flag != null) expect(File(t.flag!).existsSync(), isTrue, reason: t.flag);
    }
  });

  group('Mascot', () {
    testWidgets('kid mode: Pofuduk is the host, big and animated', (tester) async {
      await _pump(
        tester,
        const Scaffold(
          body: Center(child: Mascot(mood: Mood.cheer, size: 150)),
        ),
      );
      expect(find.byType(Dayi), findsNothing);
      expect(tester.widget<Pofuduk>(find.byType(Pofuduk)).animate, isTrue);
      expect(tester.getSize(find.byType(Pofuduk)), const Size(150, 150));
      expect(find.bySemanticsLabel('Pofuduk'), findsOneWidget);
      expect(find.byKey(const ValueKey('pofuduk-cheer')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('each mood has its own Pofuduk pose', () {
      expect(pofudukPose(Mood.cheer), endsWith('gozluk.png'), reason: 'celebration: sunglasses');
      expect(pofudukPose(Mood.calm), endsWith('meditasyon.png'), reason: 'break: meditation');
      expect(pofudukPose(Mood.wave), endsWith('selam.png'), reason: 'welcome: waving');
      expect(pofudukPose(Mood.sad), endsWith('uzgun.png'));
      expect(pofudukPose(Mood.happy), endsWith('dans.png'));
    });

    for (final b in Brightness.values) {
      testWidgets('adult mode (${b.name}): small and still; decorative ones hidden', (tester) async {
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
          b: b,
        );
        expect(find.byType(Dayi), findsOneWidget, reason: 'adults are hosted by Çaycı Dayı');
        expect(find.byType(Pofuduk), findsNothing);
        expect(tester.widget<Dayi>(find.byType(Dayi)).animate, isFalse);
        expect(tester.getSize(find.byType(Dayi)).width, 72);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('EmptyState shows the mascot with the message', (tester) async {
      await _pump(tester, const Scaffold(body: EmptyState(message: 'Şu an tekrar edilecek kelime yok.')));
      expect(find.text('Şu an tekrar edilecek kelime yok.'), findsOneWidget);
      expect(find.byKey(const ValueKey('pofuduk-calm')), findsOneWidget);
    });

    testWidgets('onboarding: kid mode greets with Çaycı Dayı, adult shows the logo', (tester) async {
      await _pump(tester, const Scaffold(body: LingoraLogo()));
      expect(find.byKey(const ValueKey('dilbaz-logo')), findsOneWidget);
    });
  });

  group('end of lesson', () {
    for (final (accuracy, perfect, mood) in [
      (100, true, 'cheer'),
      (92, false, 'cheer'),
      (70, false, 'happy'),
    ]) {
      testWidgets('accuracy $accuracy: mascot is $mood', (tester) async {
        await _pump(
          tester,
          LessonResultScreen(
            reward: _reward,
            accuracy: accuracy,
            duration: const Duration(minutes: 3),
            perfect: perfect,
          ),
        );
        expect(find.byKey(ValueKey('pofuduk-$mood')), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
      });
    }

    for (final mode in AppMode.values) {
      testWidgets('${mode.name}: Pofuduk celebrates, dances for the streak and meditates on breaks', (
        tester,
      ) async {
        await _pump(
          tester,
          const LessonResultScreen(
            reward: _reward,
            accuracy: 100,
            duration: Duration(minutes: 2),
            perfect: true,
          ),
          mode: mode,
        );
        expect(find.byKey(const ValueKey('pofuduk-cheer')), findsOneWidget);
        await _pump(tester, const StreakCelebrationScreen(streak: 4), mode: mode);
        expect(find.byKey(const ValueKey('pofuduk-happy')), findsOneWidget);
        await _pump(tester, const BreakReminderScreen(), mode: mode);
        expect(find.text('Kısa bir çay molası?'), findsOneWidget);
        expect(find.byKey(const ValueKey('pofuduk-calm')), findsOneWidget);
      });
    }

    for (final mode in AppMode.values) {
      testWidgets('${mode.name}: the feedback panel shows the mode\'s host', (tester) async {
        await _pump(
          tester,
          Scaffold(body: AnswerFeedbackPanel(correct: true, onContinue: () {})),
          mode: mode,
        );
        expect(find.byType(Dayi), mode == AppMode.adult ? findsOneWidget : findsNothing);
        expect(find.byType(Pofuduk), mode == AppMode.kid ? findsOneWidget : findsNothing);
      });
    }
  });

  test('BreakTracker suggests a break after 3 lessons or 20 minutes', () {
    final t = BreakTracker();
    expect(t.recordLesson(const Duration(minutes: 3)), isFalse);
    expect(t.recordLesson(const Duration(minutes: 3)), isFalse);
    expect(t.recordLesson(const Duration(minutes: 3)), isTrue);
    expect(t.recordLesson(const Duration(minutes: 3)), isFalse, reason: 'counters restart');
    expect(t.recordLesson(const Duration(minutes: 18)), isTrue);
  });

  test('mascot orange is readable in every palette', () {
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
