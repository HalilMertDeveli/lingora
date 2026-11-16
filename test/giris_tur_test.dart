import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/catalog.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/nav/nav_target.dart';
import 'package:lingora/screens/account_nudge.dart';
import 'package:lingora/screens/auth_screen.dart';
import 'package:lingora/services/firebase/account_service.dart';
import 'package:lingora/services/firebase/firebase_providers.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/ui/first_tour.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 11, 16, 12);

Future<SharedPreferences> _pumpNudge(WidgetTester tester, List<Override> overrides) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => _now),
        ...overrides,
      ],
      child: MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(body: SingleChildScrollView(child: AccountNudgeCard())),
      ),
    ),
  );
  await tester.pump();
  return prefs;
}

List<Override> _guest() => [
  authStateProvider.overrideWithValue(const AsyncData(AppUser(uid: 'g1'))),
  accountServiceProvider.overrideWithValue(AccountService(MockFirebaseAuth())),
];

void main() {
  group('sign-in reminder', () {
    testWidgets('a guest is told progress may be lost, and can sign in', (tester) async {
      await _pumpNudge(tester, _guest());
      expect(find.text('İlerlemen kaybolmasın'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('account-nudge-sign-in')));
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsOneWidget);
    });

    testWidgets('"Sonra" hides it for three days', (tester) async {
      final prefs = await _pumpNudge(tester, _guest());
      await tester.tap(find.byKey(const ValueKey('account-nudge-later')));
      await tester.pump();
      expect(find.byKey(const ValueKey('account-nudge')), findsNothing);
      expect(prefs.getInt(accountNudgeUntilKey), _now.add(accountNudgeSnooze).millisecondsSinceEpoch);
    });

    testWidgets('signed-in learners and builds without Firebase never see it', (tester) async {
      await _pumpNudge(tester, []);
      expect(find.byKey(const ValueKey('account-nudge')), findsNothing);
    });

    testWidgets('not for a signed-in account', (tester) async {
      await _pumpNudge(tester, [
        authStateProvider.overrideWithValue(const AsyncData(AppUser(uid: 'u1', isAnonymous: false))),
        accountServiceProvider.overrideWithValue(AccountService(MockFirebaseAuth())),
      ]);
      expect(find.byKey(const ValueKey('account-nudge')), findsNothing);
    });
  });

  group('first tour', () {
    test('at most four short stops over the tabs', () {
      final general = tourSteps(tabsFor(TrackKind.course));
      expect(general.map((s) => s.tab), [0, 1, 2, 4], reason: 'learn, practice, league, profile');
      for (final s in general) {
        expect(s.text.length, lessThan(70), reason: 'one short sentence: ${s.text}');
      }
      final vocab = tourSteps(tabsFor(TrackKind.vocab));
      expect(vocab.map((s) => s.title), ['Keşfet', 'Tekrar', 'Profilin']);
    });

    testWidgets('a tap moves on, the last step says "Başla", "Geç" ends it', (tester) async {
      final barKey = GlobalKey();
      var done = 0;
      final steps = tourSteps(tabsFor(TrackKind.course));
      Widget app() => MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: SizedBox(key: barKey, height: 80),
        ),
      );
      await tester.pumpWidget(app());
      final overlay = OverlayEntry(
        builder: (_) => TourOverlay(barKey: barKey, tabCount: 5, steps: steps, onDone: () => done++),
      );
      tester.state<OverlayState>(find.byType(Overlay).first).insert(overlay);
      await tester.pumpAndSettle();
      expect(find.text('Yolun burada'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tour-scrim')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Pratik'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tour-next')));
      await tester.tap(find.byKey(const ValueKey('tour-next')));
      await tester.pumpAndSettle();
      expect(find.text('Başla'), findsOneWidget);
      expect(find.byKey(const ValueKey('tour-skip')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tour-next')));
      expect(done, 1);
      overlay.remove();

      // Skipping from the first stop ends it at once.
      await tester.pumpWidget(app());
      final again = OverlayEntry(
        builder: (_) => TourOverlay(barKey: barKey, tabCount: 5, steps: steps, onDone: () => done++),
      );
      tester.state<OverlayState>(find.byType(Overlay).first).insert(again);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tour-skip')));
      expect(done, 2);
      again.remove();
    });

    test('off in tests unless turned on', () => expect(FirstTour.enabled, isFalse));
  });
}
