// QA Premium regressions in Mülakat Provası: leaving halfway and double taps.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/rehearsal.dart';
import 'package:lingora/screens/rehearsal/rehearsal_screen.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/rehearsal_service.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/services/voice_recorder.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'premium_test.dart' show FakeBilling;
import 'widget_test.dart' show FakeSpeech;

/// The demo analysis, counting the calls.
class CountingRehearsal extends DemoRehearsalService {
  CountingRehearsal() : super(delay: const Duration(milliseconds: 50));
  int calls = 0;

  @override
  Future<RehearsalAnalysis> analyze(RehearsalRequest request) {
    calls++;
    return super.analyze(request);
  }
}

final _now = DateTime(2026, 11, 18, 10);

Future<ProviderContainer> _pump(WidgetTester tester, RehearsalService service) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => _now),
      speechProvider.overrideWithValue(FakeSpeech()),
      voiceRecorderProvider.overrideWithValue(NoVoiceRecorder()),
      rehearsalServiceProvider.overrideWithValue(service),
      billingServiceProvider.overrideWithValue(FakeBilling()),
      premiumDevOverrideProvider.overrideWithValue(true),
    ],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildTheme(), home: const RehearsalHomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('prova-start')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('prova-mic'))); // no mic in tests: typing
  await tester.pumpAndSettle();
  return c;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('prova-answer-field')), text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('leaving halfway asks first and keeps nothing', (tester) async {
    final c = await _pump(tester, CountingRehearsal());
    await _type(tester, 'I am Mert, I am a backend developer in Ankara.');
    await tester.tap(find.byKey(const Key('prova-next')));
    await tester.pumpAndSettle();

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    await nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Provadan çıkılsın mı?'), findsOneWidget);
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prova-answer-field')), findsOneWidget);

    await nav.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prova-leave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prova-start')), findsOneWidget);
    expect(c.read(rehearsalProvider).sessions, isEmpty);
  });

  testWidgets('a double tap on "Bitir ve analiz et" analyses once', (tester) async {
    final service = CountingRehearsal();
    final c = await _pump(tester, service);
    await _type(tester, 'I am Mert, I am a backend developer in Ankara.');
    await tester.tap(find.byKey(const Key('prova-next')));
    await tester.pumpAndSettle();
    await _type(tester, 'Last year we make a payment app. It was very big project and we use Kotlin.');
    await tester.tap(find.byKey(const Key('prova-next')));
    await tester.tap(find.byKey(const Key('prova-next')), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(service.calls, 1);
    expect(c.read(rehearsalProvider).sessions.single.answers, hasLength(2));
  });
}
