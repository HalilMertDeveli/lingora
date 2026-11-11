import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/vocab_practice.dart';
import 'package:lingora/main.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/models/vocab.dart';
import 'package:lingora/nav/flow.dart';
import 'package:lingora/nav/nav_target.dart';
import 'package:lingora/screens/path_screen.dart';
import 'package:lingora/screens/practice_hub_screen.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeNotifications, FakeSpeech;

final _course = Course.fromJson(
  jsonDecode(File('assets/courses/tr_en.json').readAsStringSync()) as Map<String, dynamic>,
);
final _vocab = VocabBundle.fromJson(
  jsonDecode(File('assets/vocab/software.json').readAsStringSync()) as Map<String, dynamic>,
);
final _now = DateTime(2026, 11, 11, 9);

/// Pumps the whole app (already onboarded) and returns its container.
Future<ProviderContainer> _pumpShell(WidgetTester tester, [Progress? progress]) async {
  final p = progress ?? const Progress(onboarded: true, remindersEnabled: false);
  SharedPreferences.setMockInitialValues({'progress_v1': jsonEncode(p.toJson())});
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(420, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final container = ProviderContainer(
    overrides: [
      courseProvider.overrideWith((ref) async => _course),
      vocabProvider.overrideWith((ref) async => _vocab),
      prefsProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => _now),
      speechProvider.overrideWithValue(FakeSpeech()),
      notificationServiceProvider.overrideWithValue(FakeNotifications()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const LingoraApp()));
  await tester.pumpAndSettle();
  return container;
}

final _bar = find.byKey(const Key('bottom-nav'));

NavigationBar _navBar(WidgetTester tester) => tester.widget<NavigationBar>(_bar);

List<String> _labels(WidgetTester tester) => [
  for (final d in _navBar(tester).destinations) (d as NavigationDestination).label,
];

int _selected(WidgetTester tester) => _navBar(tester).selectedIndex;

Future<void> _tapTab(WidgetTester tester, AppTab tab) async {
  await tester.tap(find.byKey(Key('tab-${tab.name}')));
  await tester.pumpAndSettle();
}

/// Android back button.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

bool _rootCanPop(WidgetTester tester) => Navigator.of(tester.element(_bar), rootNavigator: true).canPop();

Progress _withDone(int count, {List<String> mistakes = const []}) => Progress(
  onboarded: true,
  remindersEnabled: false,
  mistakes: mistakes,
  completed: {for (final n in _course.allNodes.take(count)) n.id: 1},
);

void main() {
  group('tab sets', () {
    testWidgets('general tracks: Öğren · Pratik · Lig · Görevler · Profil', (tester) async {
      await _pumpShell(tester);
      expect(_labels(tester), ['Öğren', 'Pratik', 'Lig', 'Görevler', 'Profil']);
      expect(_selected(tester), 0);
      await _tapTab(tester, AppTab.practice);
      // Everything that used to be buried is one tap away.
      for (final k in ['conversation', 'pronunciation', 'mistakes', 'speed', 'errors', 'reading', 'notes']) {
        await tester.scrollUntilVisible(
          find.byKey(Key('hub-$k')),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.byKey(Key('hub-$k')), findsOneWidget);
      }
    });

    testWidgets('Yazılımcı İngilizcesi: Keşfet · Tekrar · Harita · Senaryolar · Profil, Tekrar has a badge', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        const Progress(
          onboarded: true,
          remindersEnabled: false,
          trackId: 'pro_software',
          wordBox: {'sw_variable': 1},
          wordDue: {'sw_variable': '2026-11-10'},
        ),
      );
      expect(_labels(tester), ['Keşfet', 'Tekrar', 'Harita', 'Senaryolar', 'Profil']);
      expect(find.text('Kelime keşfet'), findsOneWidget);
      expect(find.byKey(const Key('badge-review')), findsOneWidget);
      await _tapTab(tester, AppTab.review);
      expect(find.text('1 kelimenin tekrar zamanı geldi'), findsOneWidget);
      await _tapTab(tester, AppTab.map);
      expect(find.text('Bilgi haritası'), findsOneWidget);
      await _tapTab(tester, AppTab.scenarios);
      expect(find.text('Günlük stand-up'), findsOneWidget);
    });
  });

  testWidgets('inner pages keep the bottom bar and survive tab switches', (tester) async {
    await _pumpShell(tester);
    await _tapTab(tester, AppTab.practice);
    await tester.tap(find.byKey(const Key('hub-conversation')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Konuşma'), findsOneWidget);
    expect(find.text('Konuşarak öğren'), findsOneWidget);
    expect(_bar, findsOneWidget);

    await _tapTab(tester, AppTab.profile);
    expect(find.text('İstatistikler'), findsOneWidget);
    await _tapTab(tester, AppTab.practice);
    expect(find.text('Konuşarak öğren'), findsOneWidget, reason: 'the Pratik stack is kept');
  });

  testWidgets('back: inner page, then first tab, then leave the app', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      calls.add(c);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _pumpShell(tester);
    await _tapTab(tester, AppTab.practice);
    await tester.tap(find.byKey(const Key('hub-conversation')));
    await tester.pumpAndSettle();

    await _back(tester);
    expect(find.text('Konuşarak öğren'), findsNothing);
    expect(find.byKey(const Key('hub-conversation')), findsOneWidget);
    expect(_selected(tester), 1);

    await _back(tester);
    expect(_selected(tester), 0, reason: 'a tab root goes back to the first tab');
    expect(calls.where((c) => c.method == 'SystemNavigator.pop'), isEmpty);

    await _back(tester);
    expect(calls.where((c) => c.method == 'SystemNavigator.pop'), hasLength(1));
  });

  testWidgets('tapping the selected tab pops to its root, then scrolls to the top', (tester) async {
    await _pumpShell(tester);
    await _tapTab(tester, AppTab.practice);
    await tester.tap(find.byKey(const Key('hub-conversation')));
    await tester.pumpAndSettle();
    await _tapTab(tester, AppTab.practice);
    expect(find.text('Konuşarak öğren'), findsNothing);
    expect(find.byKey(const Key('hub-conversation')), findsOneWidget);

    final list = find.descendant(of: find.byType(PracticeHubScreen), matching: find.byType(Scrollable)).first;
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
    ScrollPosition pos() => tester.state<ScrollableState>(list).position;
    expect(pos().pixels, greaterThan(0));
    await _tapTab(tester, AppTab.practice);
    expect(pos().pixels, 0);
  });

  testWidgets('a lesson covers the bottom bar; back asks, without penalty', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.text('Başla'));
    await tester.pumpAndSettle();
    expect(find.text('“merhaba” hangisi?'), findsOneWidget);
    expect(_bar, findsNothing);

    await _back(tester);
    expect(find.byKey(const Key('quit-sheet')), findsOneWidget);
    expect(find.text('Dersten çıkılsın mı?'), findsOneWidget);
    expect(find.textContaining('ilerleme kaydedilmez'), findsOneWidget);
    expect(find.textContaining('Ceza yok'), findsOneWidget);
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();
    expect(find.text('“merhaba” hangisi?'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Çık'));
    await tester.pumpAndSettle();
    expect(_bar, findsOneWidget);
    expect(_rootCanPop(tester), isFalse);
  });

  testWidgets('end of a lesson: result, quests, streak, then one tap back with nothing left over', (
    tester,
  ) async {
    await _pumpShell(tester, _withDone(0, mistakes: ['u1l1#0']));
    await _tapTab(tester, AppTab.practice);
    await tester.tap(find.byKey(const Key('hub-mistakes')));
    await tester.pumpAndSettle();
    expect(_bar, findsNothing);
    await tester.tap(find.text('hello'));
    await tester.pump();
    await tester.tap(find.text('Kontrol et'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();

    expect(find.text('Tekrar tamamlandı!'), findsOneWidget);
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quest-progress')), findsOneWidget);
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('streak-celebration')), findsOneWidget);
    expect(find.text('Seri başladı!'), findsOneWidget);
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();

    expect(_bar, findsOneWidget);
    expect(_selected(tester), 1);
    expect(_rootCanPop(tester), isFalse, reason: 'no lesson or result screen left on the stack');
  });

  testWidgets('end sequence: each step replaces the last, one pop returns', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: key, home: const Text('home')));
    key.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('lesson')));
    await tester.pumpAndSettle();
    showEndSequence(key.currentState!, [
      (next) => TextButton(onPressed: next, child: const Text('one')),
      (next) => TextButton(onPressed: next, child: const Text('two')),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('one'), findsOneWidget);
    await tester.tap(find.text('one'));
    await tester.tap(find.text('one'), warnIfMissed: false); // double tap is ignored
    await tester.pumpAndSettle();
    expect(find.text('two'), findsOneWidget);
    await tester.tap(find.text('two'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(key.currentState!.canPop(), isFalse);
  });

  testWidgets('path: next node is scrolled to and highlighted; "Bulunduğun yere dön"', (tester) async {
    final c = await _pumpShell(tester, _withDone(12));
    final active = _course.allNodes[12];
    final next = _course.allNodes[13];
    expect(find.text(active.title).hitTestable(), findsOneWidget, reason: 'opens at the current node');
    final jump = find.byKey(const Key('back-to-current'));
    expect(jump, findsNothing);

    final scroller = find.descendant(of: find.byType(PathScreen), matching: find.byType(Scrollable)).first;
    await tester.drag(scroller, const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(jump, findsOneWidget);
    expect(find.text('Bulunduğun yere dön'), findsOneWidget);
    await tester.tap(jump);
    await tester.pumpAndSettle();
    expect(jump, findsNothing);
    expect(find.text(active.title).hitTestable(), findsOneWidget);

    // Re-tapping Öğren at its root also brings the current node back.
    await tester.drag(scroller, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await _tapTab(tester, AppTab.learn);
    expect(jump, findsNothing);

    c.read(progressProvider.notifier).completeNode(active.id, xp: 10);
    await tester.pumpAndSettle();
    bool lit(String title) => tester
        .widget<NodeHighlight>(find.ancestor(of: find.text(title), matching: find.byType(NodeHighlight)))
        .on;
    expect(find.text(next.title).hitTestable(), findsOneWidget);
    expect(lit(next.title), isTrue);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(lit(next.title), isFalse);
  });

  testWidgets('changing the track resets the tabs and their pages', (tester) async {
    await _pumpShell(tester);
    await _tapTab(tester, AppTab.practice);
    await tester.tap(find.byKey(const Key('hub-conversation')));
    await tester.pumpAndSettle();
    await _tapTab(tester, AppTab.profile);

    Future<void> pick(String title) async {
      await tester.tap(find.byKey(const Key('topbar-track')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('track-drawer')), findsOneWidget);
      final tile = find.descendant(of: find.byKey(const Key('track-drawer')), matching: find.text(title));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }

    await pick('Yazılımcı İngilizcesi');
    expect(_labels(tester).first, 'Keşfet');
    expect(_selected(tester), 0);
    expect(find.text('Kelime keşfet'), findsOneWidget);

    await pick('Genel İngilizce');
    expect(_labels(tester).first, 'Öğren');
    expect(_selected(tester), 0);
    await _tapTab(tester, AppTab.practice);
    expect(find.text('Konuşarak öğren'), findsNothing, reason: 'the old Pratik stack is gone');
    expect(find.byKey(const Key('hub-conversation')), findsOneWidget);
  });

  testWidgets('streak and XP open their own panels', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const Key('topbar-streak')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('streak-panel')), findsOneWidget);
    expect(find.text('Kasım 2026'), findsOneWidget);
    await _back(tester);
    expect(find.byKey(const Key('streak-panel')), findsNothing);
    expect(_selected(tester), 0, reason: 'back only closed the panel');

    await tester.tap(find.byKey(const Key('topbar-xp')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('xp-panel')), findsOneWidget);
    await tester.tap(find.text('Ligdeki sırana bak'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('xp-panel')), findsNothing);
    expect(_selected(tester), 2);
  });

  group('notifications', () {
    test('payloads round-trip and reminders point to the right tab', () {
      expect(NavTarget.parse('tab:quests'), const NavTarget(AppTab.quests));
      expect(NavTarget.parse('tab:nope'), isNull);
      expect(NavTarget.parse(null), isNull);
      const base = Progress(onboarded: true, remindersEnabled: true);
      expect(planNotifications(base, _now).first.payload, 'tab:learn');
      final vocab = Progress.fromJson({...base.toJson(), 'trackId': 'pro_software'});
      expect(planNotifications(vocab, _now).first.payload, 'tab:review');
    });

    testWidgets('a tapped notification opens its tab, closing a lesson', (tester) async {
      final c = await _pumpShell(tester);
      await tester.tap(find.text('Başla'));
      await tester.pumpAndSettle();
      expect(_bar, findsNothing);
      c.read(pendingNavTargetProvider.notifier).open(NavTarget.parse('tab:quests'));
      await tester.pumpAndSettle();
      expect(_bar, findsOneWidget);
      expect(_selected(tester), 3);
      expect(c.read(pendingNavTargetProvider), isNull);

      // A tab the track lacks falls back to the first tab.
      c.read(pendingNavTargetProvider.notifier).open(const NavTarget(AppTab.review));
      await tester.pumpAndSettle();
      expect(_selected(tester), 0);
    });
  });
}
