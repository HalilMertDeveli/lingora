import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/exercises/hands_free.dart';
import 'package:lingora/services/conversation.dart';
import 'package:lingora/services/mic_access.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/voice/talk_service.dart';
import 'package:lingora/voice/voice_io.dart';
import 'package:record/record.dart';

import 'widget_test.dart' show FakeSpeech;

class _Lines implements LinePlayer {
  final calls = <String>[];
  @override
  Future<void> sayLine(String text, {double rate = 1, double pitch = 1}) async => calls.add('line:$text');
  @override
  Future<void> sayBeforeListening(String text, {double rate = 1}) async => calls.add('prompt:$text');
  @override
  Future<void> stopLine() async {}
}

class _Mic implements MicAccess {
  @override
  Future<MicStatus> status() async => MicStatus.granted;
  @override
  Future<MicStatus> request() async => MicStatus.granted;
  @override
  Future<void> openSettings() async {}
}

void main() {
  group('prompt end → microphone (QA, Galaxy M22)', () {
    test('the listening turn starts the lead before the recording ends', () {
      const lead = Duration(milliseconds: 250);
      // A 997 ms recording first heard at 200 ms: stop waiting 547 ms later.
      expect(
        earlyEnd(const Duration(milliseconds: 997), const Duration(milliseconds: 200), lead: lead),
        const Duration(milliseconds: 547),
      );
      // Played slower, the rest lasts longer.
      expect(
        earlyEnd(const Duration(milliseconds: 1000), Duration.zero, rate: 0.5, lead: lead),
        const Duration(milliseconds: 1750),
      );
      // Already inside the lead: at once.
      expect(
        earlyEnd(const Duration(milliseconds: 1000), const Duration(milliseconds: 900), lead: lead),
        Duration.zero,
      );
      expect(promptListenLead, lessThanOrEqualTo(const Duration(milliseconds: 250)));
    });

    testWidgets('a spoken turn plays its prompt as a prompt, not as a dialogue line', (tester) async {
      final lines = _Lines();
      final auto = AutoListen(speech: FakeSpeech(), player: lines, mic: _Mic());
      addTearDown(auto.dispose);
      await auto.start(target: 'wine', prompt: 'wine', onHeard: (_) {});
      expect(lines.calls, ['prompt:wine']);
    });

    test('the barge-in microphone does not take audio focus', () {
      // Taking it paused the partner's greeting a quarter second in.
      expect(bargeInRecordConfig.audioInterruption, AudioInterruptionMode.none);
    });
  });

  test('the app may switch speaker / earpiece (MODIFY_AUDIO_SETTINGS)', () {
    // Galaxy M22: 'Audio Settings Permission Denial: setMode() / setSpeakerphoneOn()',
    // and the voice chat partner played from the earpiece.
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.MODIFY_AUDIO_SETTINGS'));
  });

  test('a failed turn does not poison the chat: same-role neighbours are joined', () {
    // Galaxy QA: 'Medical… I have a medical issue' failed, the next turn was a
    // second user message in a row, and every later turn got invalid_request.
    final msgs = apiMessages(const [
      ChatMessage(fromUser: false, text: 'Hi! Let us talk about music.'),
      ChatMessage(fromUser: true, text: 'I like pop'),
      ChatMessage(fromUser: true, text: ' every day '),
      ChatMessage(fromUser: true, text: '  '),
    ]);
    expect(msgs, [
      {'role': 'assistant', 'content': 'Hi! Let us talk about music.'},
      {'role': 'user', 'content': 'I like pop every day'},
    ]);
    expect(
      apiMessages([for (var i = 0; i < 30; i++) ChatMessage(fromUser: i.isOdd, text: 'm$i')]).length,
      20,
    );
  });

  test('the fair-use stop does not send the learner to typing, which hits the same limit', () {
    expect(fairUseMessage, isNot(contains('yazarak')));
  });
}
