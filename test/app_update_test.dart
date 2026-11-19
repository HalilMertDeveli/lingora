import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/app_resume.dart';
import 'package:lingora/core/app_update.dart';
import 'package:lingora/data/progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeConfig implements AppConfigSource {
  FakeConfig(this.data);
  Map<String, dynamic>? data;
  Object? error;
  bool hang = false;
  int calls = 0;

  @override
  Future<Map<String, dynamic>?> fetch() {
    calls++;
    if (hang) return Completer<Map<String, dynamic>?>().future;
    if (error != null) return Future.error(error!);
    return Future.value(data);
  }
}

void main() {
  group('policy', () {
    test('parses config/app and tolerates junk', () {
      final p = AppVersionPolicy.fromMap({
        'minVersionCode': 5,
        'recommendedVersionCode': 7.0,
        'message': ' Güncelle ',
      });
      expect(p.minVersionCode, 5);
      expect(p.recommendedVersionCode, 7);
      expect(p.message, 'Güncelle');
      final junk = AppVersionPolicy.fromMap({
        'minVersionCode': '99',
        'recommendedVersionCode': -3,
        'message': 4,
      });
      expect(junk.minVersionCode, 0);
      expect(junk.recommendedVersionCode, 0);
      expect(junk.message, '');
    });

    test('need by build number', () {
      const p = AppVersionPolicy(minVersionCode: 5, recommendedVersionCode: 7);
      expect(updateNeedFor(4, p), UpdateNeed.required);
      expect(updateNeedFor(5, p), UpdateNeed.recommended);
      expect(updateNeedFor(6, p), UpdateNeed.recommended);
      expect(updateNeedFor(7, p), UpdateNeed.none);
      expect(updateNeedFor(0, p), UpdateNeed.none, reason: 'unknown build never blocks');
      expect(updateNeedFor(1, const AppVersionPolicy()), UpdateNeed.none);
    });
  });

  group('gate', () {
    late SharedPreferences prefs;
    late DateTime now;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      now = DateTime(2026, 11, 19, 10);
    });

    Future<ProviderContainer> pump(WidgetTester tester, AppConfigSource? source, {int? build = 5}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prefsProvider.overrideWithValue(prefs),
            clockProvider.overrideWithValue(() => now),
            appConfigSourceProvider.overrideWithValue(source),
            buildNumberProvider.overrideWith((ref) async => build),
          ],
          child: MaterialApp(
            builder: (context, child) => UpdateGate(child: child!),
            home: const Scaffold(body: Text('ana sayfa')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(UpdateGate)));
    }

    testWidgets('below the minimum: blocking screen with a store button', (tester) async {
      await pump(tester, FakeConfig({'minVersionCode': 6, 'message': 'Yeni sürüm şart.'}));
      expect(find.byKey(const ValueKey('force-update')), findsOneWidget);
      expect(find.text('Lütfen güncelle'), findsOneWidget);
      expect(find.text('Yeni sürüm şart.'), findsOneWidget);
      expect(find.byKey(const ValueKey('force-update-store')), findsOneWidget);
      expect(find.text('ana sayfa'), findsNothing);
    });

    testWidgets('empty message falls back to the default text', (tester) async {
      await pump(tester, FakeConfig({'minVersionCode': 6}));
      expect(find.text(defaultUpdateMessage), findsOneWidget);
    });

    testWidgets('below the recommended version: banner that stays closed', (tester) async {
      await pump(tester, FakeConfig({'minVersionCode': 3, 'recommendedVersionCode': 6}));
      expect(find.text('ana sayfa'), findsOneWidget);
      expect(find.byKey(const ValueKey('update-banner')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('update-banner-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update-banner')), findsNothing);
      expect(prefs.getInt('update.dismissedVersion'), 6);

      // A newer recommended version shows the banner again.
      await tester.pumpWidget(const SizedBox());
      await pump(tester, FakeConfig({'recommendedVersionCode': 7}));
      expect(find.byKey(const ValueKey('update-banner')), findsOneWidget);
    });

    testWidgets('up to date: nothing shown', (tester) async {
      await pump(tester, FakeConfig({'minVersionCode': 5, 'recommendedVersionCode': 5}));
      expect(find.text('ana sayfa'), findsOneWidget);
      expect(find.byKey(const ValueKey('update-banner')), findsNothing);
      expect(find.byKey(const ValueKey('force-update')), findsNothing);
    });

    testWidgets('offline, missing document, no Firebase or unknown build never block', (tester) async {
      final offline = FakeConfig({'minVersionCode': 99})..error = Exception('unavailable');
      await pump(tester, offline);
      expect(find.text('ana sayfa'), findsOneWidget);
      expect(offline.calls, 1);

      await tester.pumpWidget(const SizedBox());
      await pump(tester, FakeConfig(null));
      expect(find.text('ana sayfa'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pump(tester, null);
      expect(find.text('ana sayfa'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      final unknownBuild = FakeConfig({'minVersionCode': 99});
      await pump(tester, unknownBuild, build: null);
      expect(find.text('ana sayfa'), findsOneWidget);
      expect(unknownBuild.calls, 0);
    });

    testWidgets('a hanging request times out without blocking', (tester) async {
      final slow = FakeConfig({'minVersionCode': 99})..hang = true;
      await pump(tester, slow);
      await tester.pump(updateFetchTimeout + const Duration(seconds: 1));
      expect(find.text('ana sayfa'), findsOneWidget);
    });

    testWidgets('resume re-checks, but at most every few hours', (tester) async {
      final config = FakeConfig({'minVersionCode': 1});
      final c = await pump(tester, config);
      expect(config.calls, 1);

      config.data = {'minVersionCode': 6};
      c.read(appResumeProvider.notifier).bump();
      await tester.pumpAndSettle();
      expect(config.calls, 1, reason: 'throttled');
      expect(find.text('ana sayfa'), findsOneWidget);

      now = now.add(updateRecheckInterval);
      c.read(appResumeProvider.notifier).bump();
      await tester.pumpAndSettle();
      expect(config.calls, 2);
      expect(find.byKey(const ValueKey('force-update')), findsOneWidget);

      // Going offline afterwards keeps the last answer from the server.
      config.error = Exception('offline');
      now = now.add(updateRecheckInterval);
      c.read(appResumeProvider.notifier).bump();
      await tester.pumpAndSettle();
      expect(config.calls, 3);
      expect(find.byKey(const ValueKey('force-update')), findsOneWidget);
    });
  });
}
