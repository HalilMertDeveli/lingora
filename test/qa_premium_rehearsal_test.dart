// QA Premium regressions in Mülakat Provası: leaving halfway and double taps.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/rehearsal.dart';
import 'package:lingora/screens/rehearsal/rehearsal_answer_screen.dart';
import 'package:lingora/screens/rehearsal/rehearsal_screen.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/firebase/firebase_providers.dart';
import 'package:lingora/services/rehearsal_cloud.dart';
import 'package:lingora/services/rehearsal_service.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/services/voice_recorder.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'premium_test.dart' show FakeBilling;
import 'ses_kocu_test.dart' show VoiceSpeech;
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

  test('rehearsal history comes back from the account on a new phone', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('rehearsals/u1/items/r1').set({
      'kind': 'first',
      'items': [
        {'question': firstRehearsalQuestions.first.text, 'answer': 'I am Mert, a backend developer.'},
      ],
      'analysis': {'summary_tr': 'Özet', 'content_gaps': [], 'grammar_errors': [], 'exercises': []},
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 17, 9)),
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        firestoreProvider.overrideWithValue(db),
        authStateProvider.overrideWith(
          (ref) => Stream.value(const AppUser(uid: 'u1', isAnonymous: false, providers: ['password'])),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(rehearsalCloudSyncProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await c.read(rehearsalCloudSyncProvider.future), 1);
    final s = c.read(rehearsalProvider).sessions.single;
    expect(s.id, 'r1');
    expect(s.answers.single.questionId, firstRehearsalQuestions.first.id);
    expect(s.answers.single.audioPath, isNull);
    expect(s.analysis!.summaryTr, 'Özet');
    // A second run adds nothing.
    expect(c.read(rehearsalProvider.notifier).mergeFromCloud([s]), 0);
  });

  testWidgets('a recognizer that stops at once is not restarted in a tight loop', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // Ready, but every listen ends at once with nothing heard (Samsung "busy").
    final speech = VoiceSpeech();
    final c = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => _now),
        speechProvider.overrideWithValue(speech),
        voiceRecorderProvider.overrideWithValue(NoVoiceRecorder()),
        rehearsalServiceProvider.overrideWithValue(CountingRehearsal()),
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
    await tester.tap(find.byKey(const Key('prova-mic')));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(speech.listens, maxSilentRestarts + 1);
    expect(find.text('Soru 1 / 2 · Motivasyon'), findsOneWidget, reason: 'still on the first question');
  });

  test('a recording with a few frames for many seconds counts as empty', () {
    expect(recordingLooksEmpty(3174, const Duration(seconds: 12)), isTrue); // Galaxy M22
    expect(recordingLooksEmpty(96000, const Duration(seconds: 12)), isFalse);
    expect(
      recordingLooksEmpty(900, const Duration(milliseconds: 800)),
      isFalse,
      reason: 'too short to judge',
    );
  });

  testWidgets('a phone that records only silence stops recording, the recognizer keeps the mic', (
    tester,
  ) async {
    final recorder = _StarvedRecorder();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => _now),
        speechProvider.overrideWithValue(
          VoiceSpeech(heard: [(words: 'I am a backend developer in Ankara', confidence: 0.9)]),
        ),
        voiceRecorderProvider.overrideWithValue(recorder),
        rehearsalServiceProvider.overrideWithValue(CountingRehearsal()),
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
    await tester.tap(find.byKey(const Key('prova-mic'))); // start
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('prova-mic'))); // stop: silence came back
    await tester.pumpAndSettle();
    expect(prefs.getBool(recordingOffKey), isTrue);
    expect(find.textContaining('ses kaydına izin vermiyor'), findsOneWidget);

    await tester.tap(find.byKey(const Key('prova-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prova-mic')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(recorder.starts, 1, reason: 'the second answer is not recorded');
    await tester.tap(find.byKey(const Key('prova-mic')));
    await tester.pumpAndSettle();
  });
}

class _StarvedRecorder implements VoiceRecorder {
  int starts = 0;
  @override
  Future<bool> start(String name) async {
    starts++;
    return true;
  }

  @override
  Future<String?> stop() async => null; // only silence was captured

  @override
  Future<void> cancel() async {}
}
