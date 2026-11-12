import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/app_settings.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/quests.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/lesson_result_screen.dart';
import 'package:lingora/screens/path_map.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/ui/motion.dart';
import 'package:lingora/ui/session.dart';
import 'package:lingora/ui/tea_art.dart';
import 'package:lingora/ui/transitions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show pumpApp;

final _course = Course.fromJson(
  jsonDecode(File('assets/courses/tr_en.json').readAsStringSync()) as Map<String, dynamic>,
);

String _progress({int done = 0}) => jsonEncode(
  Progress(onboarded: true, completed: {for (final n in _course.allNodes.take(done)) n.id: 1}).toJson(),
);

/// Shared widgets in a themed app; [reduced] turns on reduced motion.
Future<void> _pumpKit(WidgetTester tester, Widget child, {bool reduced = true}) async {
  if (reduced) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: child),
    ),
  );
}

const _quest = QuestDef('lessons2', QuestMetric.lessons, 2, '2 ders bitir', 10);

LessonReward _reward({bool streak = true, bool quest = true}) => LessonReward(
  xp: 15,
  streak: 3,
  streakExtended: streak,
  todayXp: 25,
  dailyGoal: 30,
  questsCompleted: quest ? const [_quest] : const [],
  questProgress: [QuestStep(quest: _quest, before: quest ? 1 : 0, after: quest ? 2 : 0)],
);

void main() {
  group('path map', () {
    test('the lane winds as a soft S-curve and mirrors odd units', () {
      expect([for (var i = 0; i < 8; i++) laneOffset(i)], [0, 0.707, 1, 0.707, 0, -0.707, -1, -0.707]);
      expect(laneOffset(2, mirror: true), -1);
      expect(laneSwing(1000), 72);
      expect(laneSwing(300), 60);
    });

    test('a glass fills up as the lesson is done', () {
      expect(glassLevel(NodeState.locked), 0);
      expect(glassLevel(NodeState.active), 0.5);
      expect(glassLevel(NodeState.done), greaterThan(0.8));
    });

    testWidgets('done, active and locked glasses differ; the active one is invited', (tester) async {
      await pumpApp(tester, {'progress_v1': _progress(done: 2)});
      final nodes = _course.units.first.nodes;
      TeaNode node(int i) => tester.widget(find.byKey(Key('path-node-${nodes[i].id}')));
      expect(node(0).state, NodeState.done);
      expect(node(2).state, NodeState.active);
      expect(node(3).state, NodeState.locked);
      // Full glass with a gold rim, half glass, empty glass.
      TeaGlassPainter glass(int i) => tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byKey(Key('path-node-${nodes[i].id}')),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((c) => c.painter)
          .whereType<TeaGlassPainter>()
          .single;
      expect(glass(0).level, glassLevel(NodeState.done));
      expect(glass(0).goldRim, isTrue);
      expect(glass(2).level, closeTo(0.5, 0.05));
      expect(glass(3).level, 0);
      expect(glass(3).dim, isTrue);
      expect(find.byKey(const Key('active-glow')), findsOneWidget);
      expect(find.byKey(Key('tea-invite-${nodes[2].id}')), findsOneWidget);
      expect(find.text(nodeInvite(nodes[2].type)), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.lock_rounded), findsWidgets);
      // The host stands beside the lane, and the lane is drawn.
      expect(find.byKey(const Key('path-mascot')), findsWidgets);
      expect(find.byKey(Key('lane-${_course.units.first.id}')), findsOneWidget);
    });

    testWidgets('the reward is a teapot and the unit test a tulip', (tester) async {
      await _pumpKit(
        tester,
        Row(
          children: [
            for (final (t, s) in [
              (NodeType.chest, NodeState.active),
              (NodeType.chest, NodeState.done),
              (NodeType.test, NodeState.locked),
            ])
              TeaNode(type: t, state: s, color: Colors.teal, onTap: () {}),
          ],
        ),
      );
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .toList();
      expect(painters.whereType<TeapotPainter>().map((p) => p.open), [false, true]);
      expect(painters.whereType<TulipPainter>().single.dim, isTrue);
      expect(find.byKey(const Key('steam')), findsNothing, reason: 'only glasses steam');
    });

    testWidgets('tapping a node opens its lesson card; Başla starts the lesson', (tester) async {
      await pumpApp(tester, {'progress_v1': _progress()});
      final first = _course.units.first.nodes.first;
      await tester.tap(find.byKey(Key('path-node-${first.id}')));
      await tester.pumpAndSettle();
      final card = find.byKey(const Key('lesson-card'));
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.text(first.title)), findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining('Ders 1 /')), findsOneWidget);
      expect(find.byKey(const Key('lesson-card-progress')), findsOneWidget);

      // Tapping outside closes it.
      await tester.tapAt(const Offset(10, 990));
      await tester.pumpAndSettle();
      expect(card, findsNothing);

      await tester.tap(find.byKey(Key('path-node-${first.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lesson-card-start')));
      await tester.pumpAndSettle();
      expect(find.text('“merhaba” hangisi?'), findsOneWidget);
    });

    testWidgets('a locked node card explains instead of starting', (tester) async {
      await pumpApp(tester, {'progress_v1': _progress()});
      final locked = _course.units.first.nodes[1];
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('path-node-${locked.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Önce önceki adımları tamamla.'), findsOneWidget);
      expect(find.byKey(const Key('lesson-card-start')), findsNothing);
    });

    testWidgets('unit band opens the unit guide', (tester) async {
      await pumpApp(tester, {'progress_v1': _progress()});
      final unit = _course.units.first;
      await tester.tap(find.byKey(Key('unit-guide-${unit.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unit-guide')), findsOneWidget);
      expect(find.text('Bu ünitedeki adımlar'), findsOneWidget);
      final phrases = unitPhrases(unit);
      expect(phrases, isNotEmpty);
      expect(phrases.map((p) => p.$1), contains('hello'));
      expect(phrases.map((p) => p.$1), isNot(contains('merhaba')), reason: 'English on the left');
    });

    testWidgets('the unit band sticks to the top while its unit scrolls by', (tester) async {
      await pumpApp(tester, {'progress_v1': _progress()});
      expect(find.byKey(const Key('sticky-unit-band')), findsNothing);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sticky-unit-band')), findsOneWidget);
    });

    testWidgets('the next unit band pushes the pinned band up instead of sliding under it', (tester) async {
      await pumpApp(tester, {'progress_v1': _progress()});
      final sticky = find.byKey(const Key('sticky-unit-band'));
      var checked = 0;
      for (var step = 0; step < 40; step++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -60));
        await tester.pumpAndSettle();
        if (sticky.evaluate().isEmpty) continue;
        final pinnedUnit = tester.widget<UnitBand>(sticky).unit;
        // Only the part of the pinned band below the top of the path is drawn.
        final path = tester.getRect(find.byType(Scrollable).first);
        final p = tester.getRect(sticky);
        final pinned = Rect.fromLTRB(p.left, p.top < path.top ? path.top : p.top, p.right, p.bottom);
        if (pinned.height <= 1) continue;
        for (final band in find.byType(UnitBand).evaluate()) {
          final w = band.widget as UnitBand;
          // Its own band scrolling away under it shows the same content.
          if (w.key == const Key('sticky-unit-band') || w.unit.id == pinnedUnit.id) continue;
          final r = tester.getRect(find.byWidget(w));
          if (r.bottom <= path.top) continue;
          checked++;
          final overlaps = r.top < pinned.bottom - 1 && r.bottom > pinned.top + 1;
          expect(overlaps, isFalse, reason: 'pinned $pinned overlaps band $r at step $step');
        }
      }
      expect(checked, greaterThan(0), reason: 'the test must see a pinned band next to a scrolling one');
    });
  });

  group('session', () {
    testWidgets('feedback panel: tea and a praise when right, soft navy with the answer when wrong', (
      tester,
    ) async {
      var next = 0;
      await _pumpKit(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: AnswerFeedbackPanel(correct: true, onContinue: () => next++),
        ),
      );
      expect(find.byKey(const Key('feedback-correct')), findsOneWidget);
      final praise = tester.widget<Text>(find.byKey(const Key('feedback-title'))).data;
      expect(teaPraises, contains(praise));
      final ok = tester.widget<Container>(find.byKey(const Key('feedback-correct')));
      expect((ok.decoration! as BoxDecoration).color, Brand.successBg);
      await tester.tap(find.text('Devam'));
      expect(next, 1);

      await _pumpKit(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: AnswerFeedbackPanel(correct: false, answer: 'Hello', onContinue: () {}),
        ),
      );
      expect(find.byKey(const Key('feedback-wrong')), findsOneWidget);
      expect(find.text('Doğru cevap:'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
      expect(softRetries, contains(tester.widget<Text>(find.byKey(const Key('feedback-soft'))).data));
      final box = tester.widget<Container>(find.byKey(const Key('feedback-wrong')));
      expect((box.decoration! as BoxDecoration).color, Brand.errorBg);
      // Wrong answers are navy, never alarm red.
      final navy = HSLColor.fromColor(Brand.error);
      expect(navy.hue, inInclusiveRange(200, 240));
    });

    testWidgets('feedback panel slides up from below', (tester) async {
      await _pumpKit(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: AnswerFeedbackPanel(correct: true, onContinue: () {}),
        ),
        reduced: false,
      );
      final rest = tester.getTopLeft(find.byKey(const Key('feedback-correct'))).dy;
      await tester.pump(const Duration(milliseconds: 60));
      final moving = tester.getTopLeft(find.byKey(const Key('feedback-correct'))).dy;
      await tester.pumpAndSettle();
      final settled = tester.getTopLeft(find.byKey(const Key('feedback-correct'))).dy;
      expect(rest, greaterThan(settled));
      expect(moving, greaterThan(settled));
    });

    testWidgets('three right answers in a row light the progress bar up', (tester) async {
      Widget header(int combo) =>
          SessionHeader(progress: 0.5, color: Colors.green, combo: combo, onClose: () {});
      await _pumpKit(tester, header(2));
      expect(find.byKey(const Key('combo-label')), findsNothing);
      await _pumpKit(tester, header(3));
      expect(find.byKey(const Key('combo-label')), findsOneWidget);
      expect(find.text('3 DOĞRU ÜST ÜSTE'), findsOneWidget);
    });

    testWidgets('a lesson shows the check bar, then the panel after Kontrol et', (tester) async {
      await pumpApp(tester, {'progress_v1': _progress()});
      await tester.tap(find.text('Hadi, bir çay daha!'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('check-bar')), findsOneWidget);
      expect(find.byKey(const Key('session-progress')), findsOneWidget);
      await tester.tap(find.text('hello'));
      await tester.pump();
      await tester.tap(find.text('Kontrol et'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('feedback-correct')), findsOneWidget);
      expect(find.byKey(const Key('check-bar')), findsNothing);
    });
  });

  group('celebration chain', () {
    test('quests come before the streak, and only when something moved', () {
      expect(celebrationSteps(_reward()), hasLength(2));
      expect(celebrationSteps(_reward(streak: false, quest: false)), isEmpty);
      expect(hasQuestStep(_reward(quest: false)), isFalse);
    });

    testWidgets('result → quests → streak, each with its own Devam', (tester) async {
      final key = GlobalKey<NavigatorState>();
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), navigatorKey: key, home: const Text('home')));
      key.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('lesson')));
      await tester.pumpAndSettle();
      final reward = _reward();
      // Same steps the lesson screen builds.
      final steps = [
        (VoidCallback next) => LessonResultScreen(
          reward: reward,
          accuracy: 100,
          duration: const Duration(seconds: 70),
          perfect: true,
          showStreak: false,
          showQuests: false,
          onContinue: next,
        ),
        ...celebrationSteps(reward),
      ];
      var current = 0;
      Route<void> route(int i) => MaterialPageRoute<void>(
        builder: (_) => steps[i](() {
          if (++current < steps.length) {
            key.currentState!.pushReplacement(route(current));
          } else {
            key.currentState!.pop();
          }
        }),
      );
      key.currentState!.pushReplacement(route(0));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lesson-result')), findsOneWidget);
      expect(find.text('+15'), findsOneWidget, reason: 'XP counter reached its value');
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quest-progress')), findsOneWidget);
      expect(find.text('Görev tamamlandı!'), findsOneWidget);
      expect(find.text('25 / 30 XP'), findsOneWidget);
      expect(find.text('Ödül hazır'), findsOneWidget);
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('streak-celebration')), findsOneWidget);
      expect(find.text('3 günlük seri!'), findsOneWidget);
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('steam, sugar and tulip petals rise and fall on the result screen', (tester) async {
      await _pumpKit(tester, const TeaCelebration(child: SizedBox.expand()), reduced: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('tea-celebration')), findsOneWidget);
      final painter =
          tester.widget<CustomPaint>(find.byKey(const Key('tea-celebration'))).painter! as CelebrationPainter;
      expect(painter.pieces.map((p) => p.kind).toSet(), PieceKind.values.toSet());
      await tester.pump(TeaCelebration.duration);
      expect(find.byKey(const Key('tea-celebration')), findsNothing);
    });
  });

  group('reduced motion', () {
    testWidgets('no celebration, no steam, no breathing glass; panel and bar appear at once', (tester) async {
      await _pumpKit(
        tester,
        Column(
          children: [
            const Expanded(child: TeaCelebration(child: SizedBox.expand())),
            TeaInvite(label: 'Hadi, bir çay daha!', color: Colors.orange, onTap: () {}),
            TeaNode(type: NodeType.lesson, state: NodeState.active, color: Colors.orange, onTap: () {}),
            const Steam(),
            SessionHeader(progress: 0.5, color: Colors.green, onClose: () {}),
            AnswerFeedbackPanel(correct: true, onContinue: () {}),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const Key('tea-celebration')), findsNothing);
      expect(find.byKey(const Key('steam')), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('with motion on, the current glass steams and breathes', (tester) async {
      await _pumpKit(
        tester,
        Center(
          child: TeaNode(type: NodeType.lesson, state: NodeState.active, color: Colors.orange, onTap: () {}),
        ),
        reduced: false,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('steam')), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('"Animasyonları azalt" in Profil turns on reduced motion app-wide', (tester) async {
      await pumpApp(tester, {
        'progress_v1': _progress(),
        AppSettingsNotifier.key: '{"mode":"adult","theme":"light","reduceMotion":true}',
      });
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pump();
      final ctx = tester.element(find.byType(Scaffold).first);
      expect(MediaQuery.disableAnimationsOf(ctx), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppSettingsNotifier.key), contains('"reduceMotion":true'));
    });

    testWidgets('full-screen flows rise from the bottom unless motion is reduced', (tester) async {
      const builder = DilbazPageTransitionsBuilder();
      final route = MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const SizedBox());
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      const anim = AlwaysStoppedAnimation(0.5);
      expect(builder.buildTransitions(route, ctx, anim, anim, const SizedBox()), isA<SlideTransition>());
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pump();
      expect(builder.buildTransitions(route, ctx, anim, anim, const SizedBox()), isA<SizedBox>());
    });
  });

  test('settings keep sound and reduced motion', () {
    const s = AppSettings(sound: false, reduceMotion: true);
    expect(AppSettings.fromJson(s.toJson()), s);
    expect(AppSettings.fromJson(const {'mode': 'kid'}).sound, isTrue);
  });
}
