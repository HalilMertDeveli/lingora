import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/exercises/hands_free.dart';
import 'package:lingora/services/mic_access.dart';
import 'package:lingora/services/speech.dart';
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
}
