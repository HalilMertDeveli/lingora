// Regressions found in the full emulator test (feature/tam-test):
// - the result screen of a lesson that is never saved for resuming (the
//   first lesson) showed "Süre 0:00": the start time was a lazy field, read
//   for the first time at the end;
// - the speaking exercise said "not heard" twice (the hands-free hint and
//   the recogniser status line);
// - on Android a server error in the streamed voice chat (`talk`) ended the
//   stream quietly: no free-quota paywall, no message, the chat just waited;
// - Mülakat provası opened with "Seni duyamadım" left over from another screen;
// - the share card said "İngilizce'ye" (TDK: no apostrophe after a language name);
// - the home shell's idle pause was not lifted when a full-screen flow
//   closed, so a paused path kept its loading spinner until a touch.
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/share_card.dart';
import 'package:lingora/exercises/hands_free.dart';
import 'package:lingora/exercises/speak_exercise.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/nav/on_reveal.dart';
import 'package:lingora/screens/rehearsal/rehearsal_screen.dart';
import 'package:lingora/services/rehearsal_service.dart';
import 'package:lingora/services/voice_recorder.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/conversation.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/voice/talk_service.dart';
import 'package:lingora/voice/voice_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'premium_test.dart' show FakeBilling;
import 'widget_test.dart' show FakeNotifications, FakeSpeech;

const _choice = Exercise(
  type: ExerciseType.choice,
  question: 'She ---- to school every day.',
  options: ['go', 'goes', 'going', 'gone'],
  answerIndex: 1,
);

class _HandsFree extends HandsFreeSetting {
  @override
  bool build() => true;
}

/// A microphone that never hears anything.
class _SilentMic implements SpeechService {
  void Function()? _onDone;

  @override
  Future<void> say(String text, {String lang = 'en', bool slow = false, double rate = 1}) async {}
  @override
  Future<bool> get canListen async => true;
  @override
  Future<void> listen({required void Function(String) onWords, required void Function() onDone}) async =>
      _onDone = onDone;
  @override
  Future<void> stopListening() async {
    final d = _onDone;
    _onDone = null;
    d?.call();
  }
}

class _Watcher extends StatefulWidget {
  const _Watcher({required this.onReveal});
  final VoidCallback onReveal;

  @override
  State<_Watcher> createState() => _WatcherState();
}

class _WatcherState extends State<_Watcher> {
  final _watch = RevealWatch();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_watch.revealed(context)) widget.onReveal();
  }

  @override
  Widget build(BuildContext context) => const Text('home');
}

void main() {
  testWidgets('a lesson that is not saved for resuming still times itself', (tester) async {
    SharedPreferences.setMockInitialValues({
      'progress_v1': jsonEncode(const Progress(onboarded: true, remindersEnabled: false).toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final c = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        speechProvider.overrideWithValue(FakeSpeech()),
        notificationServiceProvider.overrideWithValue(FakeNotifications()),
        billingServiceProvider.overrideWithValue(FakeBilling()),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildTheme(),
          home: LessonScreen(
            nodeId: 'l1',
            title: 'Test',
            items: const [(key: 'l1#0', ex: _choice)],
            color: Brand.primary,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // DateTime.now() is the real clock: spend a real second on the question.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1100)));
    await tester.tap(find.byKey(const Key('choice-option-1')));
    await tester.pump();
    await tester.tap(find.textContaining(RegExp(r'^kontrol et$', caseSensitive: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(RegExp(r'^devam$', caseSensitive: false)));
    await tester.pumpAndSettle();
    expect(find.text('Süre'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^0:0[1-9]$')), findsOneWidget, reason: 'not 0:00');
  });

  testWidgets('RevealWatch fires when a covering route closes, not before', (tester) async {
    var reveals = 0;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: _Watcher(onReveal: () => reveals++),
      ),
    );
    expect(reveals, 0, reason: 'first build is not a reveal');
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('lesson')));
    await tester.pumpAndSettle();
    expect(reveals, 0);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(reveals, 1);
  });

  testWidgets('no speech: "not heard" is said once, by the hint', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    addTearDown(() => speechIssue.value = null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          speechProvider.overrideWithValue(_SilentMic()),
          handsFreeProvider.overrideWith(_HandsFree.new),
          premiumProvider.overrideWithValue(false),
          prefsProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SpeakExercise(
                ex: const Exercise(type: ExerciseType.speak, text: 'Good morning'),
                locked: false,
                onReady: (_) {},
                onSkip: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(noSpeechTimeout);
    // The recogniser reports "no match" as the turn ends.
    speechIssue.value = SpeechIssues.notHeard;
    await tester.pump();
    expect(find.byKey(const Key('hands-free-no-speech')), findsOneWidget);
    expect(find.text(SpeechIssues.notHeard), findsNothing);
    expect(find.text('Şu an konuşamıyorum'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('talk stream that ends without a result (Android plugin)', () {
    final req = TalkRequest(
      scenario: freeTalkScenario(''),
      history: const [ChatMessage(fromUser: true, text: 'x')],
    );

    test('asks again without streaming: the free-quota stop comes through', () async {
      var invoked = 0;
      final service = CallableTalkService((name, data) => const Stream.empty(), (name, data) async {
        invoked++;
        throw FirebaseFunctionsException(code: 'resource-exhausted', message: 'free_quota');
      });
      await expectLater(
        service.talk(req).toList(),
        throwsA(isA<ConversationException>().having((e) => e.freeQuotaUsed, 'freeQuotaUsed', isTrue)),
      );
      expect(invoked, 1);
    });

    test('asks again without streaming: a reply still arrives', () async {
      final service = CallableTalkService(
        (name, data) => const Stream.empty(),
        (name, data) async => {
          'reply': 'Nice! Which team?',
          'sentences': [
            {'text': 'Nice!'},
            {'text': 'Which team?'},
          ],
          'free': true,
          'remaining': 1,
        },
      );
      final events = await service.talk(req).toList();
      expect(events.whereType<TalkSentenceEvent>().map((e) => e.text), ['Nice!', 'Which team?']);
      expect((events.last as TalkDoneEvent).turn.remaining, 1);
    });

    test('cut after a sentence: an error, not a second call', () async {
      var invoked = 0;
      final service = CallableTalkService((name, data) async* {
        yield (done: false, data: {'text': 'Nice!'});
      }, (name, data) async => invoked++);
      await expectLater(service.talk(req).toList(), throwsA(isA<ConversationException>()));
      expect(invoked, 0);
    });
  });

  testWidgets('Mülakat provası does not open with an old "not heard"', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    speechIssue.value = SpeechIssues.notHeard; // left by a lesson's speaking question
    addTearDown(() => speechIssue.value = null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          speechProvider.overrideWithValue(FakeSpeech()),
          voiceRecorderProvider.overrideWithValue(NoVoiceRecorder()),
          rehearsalServiceProvider.overrideWithValue(DemoRehearsalService()),
          billingServiceProvider.overrideWithValue(FakeBilling()),
        ],
        child: MaterialApp(theme: buildTheme(), home: const RehearsalHomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prova-start')));
    await tester.pumpAndSettle();
    expect(find.text(SpeechIssues.notHeard), findsNothing);
  });

  test('share card for a beginner: "İngilizceye başladım!"', () {
    final card = buildShareCard(const Progress(onboarded: true), DateTime(2026, 11, 19));
    expect(card.headline, 'İngilizceye başladım!');
  });
}
