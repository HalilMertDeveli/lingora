import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/exercises/speak_exercise.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:lingora/ui/motion.dart';

/// Recognition that fails without a single word, like a timeout or an error.
class _SilentSpeech implements SpeechService {
  _SilentSpeech({this.ready = true, this.issue});
  final bool ready;
  final String? issue;
  int listens = 0;
  @override
  Future<void> say(String text, {String lang = 'en', bool slow = false, double rate = 1}) async {}
  @override
  Future<bool> get canListen async {
    if (!ready) speechIssue.value = issue;
    return ready;
  }

  @override
  Future<void> listen({required void Function(String) onWords, required void Function() onDone}) async {
    listens++;
    speechIssue.value = issue;
    onDone();
  }

  @override
  Future<void> stopListening() async {}
}

Future<void> _pump(WidgetTester tester, SpeechService speech, {void Function(Object?)? onReady}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [speechProvider.overrideWithValue(speech)],
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SpeakExercise(
            ex: const Exercise(type: ExerciseType.speak, text: 'Good morning.'),
            locked: false,
            onReady: (check) => onReady?.call(check),
            onSkip: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => speechIssue.value = null);

  group('sound effects', () {
    test('the three chimes are bundled, small and real WAV files', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/sfx/'));
      for (final name in ['dogru', 'yanlis', 'kutlama']) {
        final f = File('assets/sfx/$name.wav');
        expect(f.existsSync(), isTrue, reason: f.path);
        final bytes = f.readAsBytesSync();
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
        expect(bytes.length, inInclusiveRange(4000, 60000));
      }
    });

    test('effects stay silent in tests and when sounds are off', () {
      expect(SessionFx.playback, isFalse);
      SessionFx.correct();
      SessionFx.wrong();
      SessionFx.celebrate();
    });
  });

  group('speaking', () {
    testWidgets('nothing heard: the button comes back and says why', (tester) async {
      Object? ready = 'unset';
      final speech = _SilentSpeech(issue: SpeechIssues.notHeard);
      await _pump(tester, speech, onReady: (c) => ready = c);
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      expect(speech.listens, 1);
      expect(find.text(SpeechIssues.notHeard), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget, reason: 'not stuck in "Dinliyorum…"');
      expect(ready, isNull, reason: 'no answer to check yet');

      // A second try works the same way.
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      expect(speech.listens, 2);
    });

    testWidgets('no microphone permission: tells where to turn it on, and retries on tap', (tester) async {
      final speech = _SilentSpeech(ready: false, issue: SpeechIssues.noMicPermission);
      await _pump(tester, speech);
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      expect(find.text(SpeechIssues.noMicPermission), findsOneWidget);
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      expect(find.text(SpeechIssues.noMicPermission), findsOneWidget);
    });

    testWidgets('idle: invites to speak', (tester) async {
      await _pump(tester, _SilentSpeech());
      expect(find.text('Mikrofona dokun ve konuş'), findsOneWidget);
    });
  });

  group('reminder notification sound', () {
    test('Dilmaç has its own reminder sound, kept in release builds', () {
      final name = NotificationService.reminderSound;
      expect(name, matches(RegExp(r'^[a-z0-9_]+$')), reason: 'Android raw resource names');
      final f = File('android/app/src/main/res/raw/$name.wav');
      expect(f.existsSync(), isTrue);
      final bytes = f.readAsBytesSync();
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(bytes.length, inInclusiveRange(10000, 120000));
      final keep = File('android/app/src/main/res/raw/keep.xml').readAsStringSync();
      expect(keep, contains('@raw/$name'));
    });

    test('a new channel carries the sound (Android fixes a channel sound once created)', () {
      expect(NotificationService.reminderChannelId, isNot('reminders'));
    });
  });

  test('speech recognition errors say what to do, unknown codes stay visible', () {
    String f(String c) => SpeechIssues.forError(c, heardSomething: false);
    expect(f('error_speech_timeout'), SpeechIssues.notHeard);
    expect(f('error_network'), SpeechIssues.network);
    expect(f('error_language_unavailable'), SpeechIssues.noEnglishRecognizer);
    expect(f('error_recognizer_busy'), SpeechIssues.busy);
    expect(f('error_client'), contains('(error_client)'));
    expect(SpeechIssues.forError('error_no_match', heardSomething: true), SpeechIssues.notHeardClearly);
  });
}
