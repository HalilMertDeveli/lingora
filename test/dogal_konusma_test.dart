// Doğal konuşma: the turn-taking state machine (hands-free,
// barge-in, echo), the streamed talk client, voice settings and the screens.
// Nothing here touches a real microphone, speaker or server.
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/app_settings.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/scenarios.dart';
import 'package:lingora/goals/learn_goal.dart';
import 'package:lingora/screens/conversation_report_screen.dart';
import 'package:lingora/screens/conversation_screen.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/conversation.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/voice/ack_picker.dart';
import 'package:lingora/voice/talk_screen.dart';
import 'package:lingora/voice/talk_service.dart';
import 'package:lingora/voice/turn_taking.dart';
import 'package:lingora/voice/voice_catalog.dart';
import 'package:lingora/voice/voice_io.dart';
import 'package:lingora/voice/voice_settings.dart';

import 'premium_test.dart' show FakeBilling, now, prefsWith;
import 'ses_kocu_test.dart' show FakeChat, FakeReport, VoiceSpeech;

/// A recognizer the test speaks into.
class FakeListener implements TurnListener {
  int starts = 0;
  int stops = 0;
  void Function(String)? _words;
  void Function(double)? _level;
  void Function()? _end;
  bool get active => _words != null;

  @override
  Future<void> start({
    required void Function(String words) onWords,
    required void Function(double level) onLevel,
    required void Function() onEnd,
  }) async {
    starts++;
    _words = onWords;
    _level = onLevel;
    _end = onEnd;
  }

  @override
  Future<void> stop() async {
    stops++;
    _words = _level = null;
    _end = null;
  }

  void say(String w) => _words?.call(w);
  void level(double l) => _level?.call(l);
  void end() {
    final e = _end;
    _words = _level = null;
    _end = null;
    e?.call();
  }
}

/// A speaker: each sentence plays until the test finishes it.
class FakeOut implements VoiceOut {
  final played = <String>[];
  Completer<void>? _current;
  int stops = 0;

  @override
  Future<void> play(SpokenSentence s) {
    played.add(s.text);
    return (_current = Completer<void>()).future;
  }

  void finish() => _current?.complete();

  @override
  Future<void> stop() async {
    stops++;
    if (_current case final c? when !c.isCompleted) c.complete();
  }
}

class FakeBargeIn implements BargeInDetector {
  void Function()? _onSpeech;
  int starts = 0;
  int stops = 0;
  bool get on => _onSpeech != null;

  /// A slow release of the microphone (a real recorder takes a moment).
  Completer<void>? release;

  @override
  Future<void> start(void Function() onSpeech) async {
    starts++;
    _onSpeech = onSpeech;
  }

  @override
  Future<void> stop() async {
    stops++;
    _onSpeech = null;
    await release?.future;
  }

  void speak() => _onSpeech?.call();
}

/// A partner whose reply arrives only when the test says so.
class _SlowChat implements ConversationService {
  final reply = Completer<ChatTurn>();
  final sent = <List<ChatMessage>>[];
  @override
  bool get isLive => true;
  @override
  Future<ChatTurn> send(Scenario scenario, List<ChatMessage> history) {
    sent.add(List.of(history));
    return reply.future;
  }
}

/// Eller serbest: no press-to-talk anywhere in the voice chat.
void _expectNoMicButton() {
  for (final icon in [Icons.mic, Icons.mic_rounded, Icons.mic_none_rounded, Icons.mic_off_rounded]) {
    expect(find.byIcon(icon), findsNothing);
  }
  expect(find.byKey(const Key('talk-mic')), findsNothing);
  expect(find.byKey(const Key('call-talk')), findsNothing);
}

class Rig {
  Rig(
    FakeAsync async, {
    TurnConfig config = const TurnConfig(endOfTurn: Duration(milliseconds: 1000)),
    this.acks,
  }) {
    turns = TurnTaker(
      listener: listener,
      out: out,
      bargeInDetector: bargeIn,
      config: config,
      onUserTurn: (turn, text) => sent.add((turn, text)),
      onBargeIn: (turn, heard) => barged.add((turn, heard)),
      onLatency: latencies.add,
      onFirstSentence: firstReal.add,
      pickAck: acks?.pick,
      now: () => DateTime(2026).add(async.elapsed),
    );
  }
  final listener = FakeListener();
  final out = FakeOut();
  final bargeIn = FakeBargeIn();
  late final TurnTaker turns;
  final sent = <(int, String)>[];
  final barged = <(int, int)>[];
  final latencies = <Duration>[];
  final firstReal = <Duration>[];
  final AckPicker? acks;
}

void main() {
  group('TurnTaker (hands-free)', () {
    test('a pause ends the turn; the reply plays sentence by sentence; then it listens again', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.turns.listen();
        async.flushMicrotasks();
        expect(r.turns.phase, TalkPhase.listening);
        r.listener.say('I like');
        async.elapse(const Duration(milliseconds: 700));
        r.listener.say('I like football');
        async.elapse(const Duration(milliseconds: 900));
        expect(r.sent, isEmpty, reason: 'still inside the pause after the last word');
        async.elapse(const Duration(milliseconds: 150));
        expect(r.sent, [(1, 'I like football')]);
        expect(r.turns.phase, TalkPhase.thinking);
        expect(r.listener.stops, 1);

        async.elapse(const Duration(milliseconds: 600));
        r.turns.addSentence(1, const SpokenSentence('Oh, nice!'));
        async.flushMicrotasks();
        expect(r.turns.phase, TalkPhase.speaking);
        // Latency: from the last word heard to the first sound.
        expect(r.latencies.single, const Duration(milliseconds: 1650));
        r.turns.addSentence(1, const SpokenSentence('Which team?'));
        r.turns.replyComplete(1);
        expect(r.out.played, ['Oh, nice!']);
        r.out.finish();
        async.flushMicrotasks();
        expect(r.out.played, ['Oh, nice!', 'Which team?']);
        r.out.finish();
        async.flushMicrotasks();
        expect(r.turns.phase, TalkPhase.idle);
        // The microphone opens after the echo tail, not at once.
        expect(r.listener.starts, 1);
        async.elapse(const Duration(milliseconds: 300));
        expect(r.turns.phase, TalkPhase.listening);
        expect(r.listener.starts, 2);
      });
    });

    test('the voice level keeps the turn open while the recognizer lags', () {
      fakeAsync((async) {
        final r = Rig(async, config: const TurnConfig(endOfTurn: Duration(milliseconds: 800)));
        r.turns.listen();
        async.flushMicrotasks();
        r.listener.say('Yesterday we went');
        async.elapse(const Duration(milliseconds: 600));
        r.listener.level(0.6); // still talking
        async.elapse(const Duration(milliseconds: 600));
        r.listener.level(0.1); // quiet: does not count
        async.elapse(const Duration(milliseconds: 100));
        expect(r.sent, isEmpty);
        async.elapse(const Duration(milliseconds: 150));
        expect(r.sent.single.$2, 'Yesterday we went');
      });
    });

    test('silence without words restarts listening a few times, then gives up (typing offered)', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.turns.listen();
        async.flushMicrotasks();
        for (var i = 0; i < 2; i++) {
          r.listener.end();
          expect(r.turns.phase, TalkPhase.idle);
          async.elapse(const Duration(milliseconds: 350));
          expect(r.turns.phase, TalkPhase.listening);
        }
        r.listener.end();
        async.elapse(const Duration(seconds: 2));
        expect(r.turns.phase, TalkPhase.idle);
        expect(r.listener.starts, 3);
        expect(r.turns.gaveUp, isTrue);
        // Back from typing (or the settings): listening again without a tap.
        r.turns.resume();
        async.flushMicrotasks();
        expect(r.turns.phase, TalkPhase.listening);
        expect(r.turns.gaveUp, isFalse);
      });
    });

    test('the recognizer stopping with words sends them at once', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.turns.listen();
        async.flushMicrotasks();
        r.listener.say('Hello there');
        r.listener.end();
        expect(r.sent.single.$2, 'Hello there');
      });
    });

    test("the partner's own voice heard back is ignored (echo)", () {
      fakeAsync((async) {
        final r = Rig(async);
        r.turns.say(const SpokenSentence('Where are we heading today?'));
        async.flushMicrotasks();
        r.out.finish();
        async.elapse(const Duration(milliseconds: 300));
        expect(r.turns.phase, TalkPhase.listening);
        r.listener.say('we heading today');
        async.elapse(const Duration(seconds: 1));
        expect(r.sent, isEmpty);
        async.elapse(const Duration(milliseconds: 300));
        expect(r.turns.phase, TalkPhase.listening);
        r.listener.say('To the airport please');
        async.elapse(const Duration(seconds: 1));
        expect(r.sent.single.$2, 'To the airport please');
      });
    });

    test('a typed turn is sent without the echo check', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.turns.say(const SpokenSentence('How are you?'));
        async.flushMicrotasks();
        r.out.finish();
        async.flushMicrotasks();
        r.turns.submitText('how are you');
        expect(r.sent.single.$2, 'how are you');
      });
    });
  });

  group('TurnTaker "Şunu mu dedin?"', () {
    const confirm = TurnConfig(endOfTurn: Duration(milliseconds: 1000), confirmDelay: utteranceConfirmDelay);

    Rig heard(FakeAsync async, String text) {
      final r = Rig(async, config: confirm);
      r.turns.listen();
      async.flushMicrotasks();
      r.listener.say(text);
      async.elapse(const Duration(milliseconds: 1050));
      return r;
    }

    test('the free voice conversation waits 2 seconds by default', () {
      expect(utteranceConfirmDelay, const Duration(seconds: 2));
      expect(const VoiceSettings().turnConfig.confirmDelay, utteranceConfirmDelay);
      expect(const TurnConfig().confirmDelay, Duration.zero, reason: 'nothing else waits');
    });

    test('a recognised utterance waits, then goes by itself after 2 s', () {
      fakeAsync((async) {
        final r = heard(async, 'I am glad giving you your time');
        expect(r.sent, isEmpty);
        expect(r.turns.pending, 'I am glad giving you your time');
        expect(r.turns.pendingCounting, isTrue);
        expect(r.turns.phase, TalkPhase.listening);
        expect(r.listener.active, isTrue, reason: 'still listening hands-free');
        async.elapse(const Duration(milliseconds: 1900));
        expect(r.sent, isEmpty);
        async.elapse(const Duration(milliseconds: 150));
        expect(r.sent, [(1, 'I am glad giving you your time')]);
        expect(r.turns.pending, isNull);
        expect(r.turns.phase, TalkPhase.thinking);
      });
    });

    test('İptal drops it and keeps listening; nothing is sent', () {
      fakeAsync((async) {
        final r = heard(async, 'Minneapolis');
        final starts = r.listener.starts;
        r.turns.cancelPending();
        async.elapse(const Duration(seconds: 5));
        expect(r.sent, isEmpty);
        expect(r.turns.pending, isNull);
        expect(r.turns.phase, TalkPhase.listening);
        expect(r.listener.active, isTrue);
        expect(r.listener.starts, starts, reason: 'the microphone stayed open');
        // The learner's own answer still goes.
        r.listener.say('I would like a coffee');
        async.elapse(const Duration(milliseconds: 1050));
        async.elapse(utteranceConfirmDelay);
        expect(r.sent, [(1, 'I would like a coffee')]);
      });
    });

    test('tapping the text sends it at once', () {
      fakeAsync((async) {
        final r = heard(async, 'A table for two');
        r.turns.confirmPending();
        expect(r.sent, [(1, 'A table for two')]);
        expect(r.turns.phase, TalkPhase.thinking);
        async.elapse(const Duration(seconds: 3));
        expect(r.sent, hasLength(1), reason: 'the countdown does not send it again');
      });
    });

    test('a new utterance while waiting replaces the text and restarts the countdown', () {
      fakeAsync((async) {
        final r = heard(async, 'metal glass');
        final first = r.turns.pendingSerial;
        async.elapse(const Duration(milliseconds: 1500));
        r.listener.say('Can I get');
        expect(r.turns.pendingCounting, isFalse, reason: 'nothing goes while someone speaks');
        async.elapse(const Duration(milliseconds: 700));
        r.listener.say('Can I get the bill');
        async.elapse(const Duration(milliseconds: 1050));
        expect(r.sent, isEmpty);
        expect(r.turns.pending, 'Can I get the bill');
        expect(r.turns.pendingSerial, greaterThan(first));
        async.elapse(const Duration(milliseconds: 1900));
        expect(r.sent, isEmpty, reason: 'the countdown started again');
        async.elapse(const Duration(milliseconds: 150));
        expect(r.sent, [(1, 'Can I get the bill')]);
      });
    });

    test('the recognizer stopping by itself while waiting opens again', () {
      fakeAsync((async) {
        final r = heard(async, 'Hello');
        final starts = r.listener.starts;
        r.listener.end();
        async.elapse(const Duration(milliseconds: 350));
        expect(r.listener.starts, starts + 1);
        expect(r.turns.phase, TalkPhase.listening);
        expect(r.turns.pending, 'Hello');
      });
    });

    test('typed turns and mute never wait', () {
      fakeAsync((async) {
        final r = heard(async, 'room noise');
        r.turns.submitText('Typed answer');
        async.flushMicrotasks();
        expect(r.sent, [(1, 'Typed answer')]);
        expect(r.turns.pending, isNull);
        async.elapse(const Duration(seconds: 3));
        expect(r.sent, hasLength(1));

        final m = heard(async, 'room noise');
        m.turns.setMuted(true);
        async.elapse(const Duration(seconds: 3));
        expect(m.sent, isEmpty);
        expect(m.turns.pending, isNull);
      });
    });
  });

  group('TurnTaker barge-in', () {
    test('speaking over the partner stops the voice and listens; the rest of the reply is dropped', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.turns.submitText('Tell me about London');
        r.turns.addSentence(1, const SpokenSentence('London is huge.'));
        r.turns.addSentence(1, const SpokenSentence('It has many parks.'));
        async.flushMicrotasks();
        expect(r.bargeIn.on, isTrue, reason: 'listens for barge-in only while speaking');
        r.out.finish();
        async.flushMicrotasks();
        r.bargeIn.speak();
        async.flushMicrotasks();
        expect(r.out.stops, 1);
        expect(r.bargeIn.on, isFalse);
        expect(r.barged.single, (1, 1));
        expect(r.turns.phase, TalkPhase.listening);
        r.turns.addSentence(1, const SpokenSentence('And museums.'));
        r.turns.replyComplete(1);
        async.flushMicrotasks();
        expect(r.out.played, ['London is huge.', 'It has many parks.']);
        expect(r.turns.phase, TalkPhase.listening);
      });
    });

    test('"Sözünü kes" while the partner speaks interrupts and listens', () {
      fakeAsync((async) {
        final r = Rig(async, config: const TurnConfig(bargeIn: false));
        r.turns.submitText('Hi');
        r.turns.addSentence(1, const SpokenSentence('Hello! How are you today?'));
        async.flushMicrotasks();
        expect(r.bargeIn.starts, 0);
        r.turns.interrupt();
        async.flushMicrotasks();
        expect(r.turns.phase, TalkPhase.listening);
        expect(r.barged.single, (1, 0));
      });
    });
  });

  group('TurnTaker microphone hand-over', () {
    test('the recognizer starts only after the barge-in recorder let go of the microphone', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.bargeIn.release = Completer<void>();
        r.turns.say(const SpokenSentence('Hi! How was your day?'));
        async.flushMicrotasks();
        expect(r.bargeIn.starts, 1);
        r.out.finish();
        async.elapse(const Duration(seconds: 2));
        expect(r.bargeIn.stops, 1);
        expect(r.listener.starts, 0, reason: 'the recorder still holds the microphone');
        r.bargeIn.release!.complete();
        async.elapse(const Duration(milliseconds: 300));
        expect(r.listener.starts, 1);
        expect(r.turns.phase, TalkPhase.listening);
      });
    });

    test('the recorder lets go during the echo tail, not before it (QA, Galaxy M22)', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.bargeIn.release = Completer<void>();
        r.turns.say(const SpokenSentence('Hi! How was your day?'));
        async.flushMicrotasks();
        r.out.finish();
        // The recorder takes 150 ms to stop, the echo tail is 100 ms: the
        // microphone opens after 150 ms, not 250.
        async.elapse(const Duration(milliseconds: 150));
        r.bargeIn.release!.complete();
        async.flushMicrotasks();
        expect(r.listener.starts, 1);
        expect(const TurnConfig().echoTail, lessThanOrEqualTo(const Duration(milliseconds: 100)));
      });
    });
  });

  group('TurnTaker typed turns', () {
    test('typing while the partner speaks cuts the partner off and sends', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.turns.say(const SpokenSentence('Hi! What would you like?'));
        async.flushMicrotasks();
        expect(r.turns.phase, TalkPhase.speaking);
        bool? sent;
        r.turns.submitText('A latte please').then((v) => sent = v);
        async.flushMicrotasks();
        expect(sent, isTrue);
        expect(r.sent.single.$2, 'A latte please');
        expect(r.out.stops, greaterThan(0), reason: 'the partner stopped talking');
        expect(r.turns.phase, TalkPhase.thinking);
      });
    });

    test('while the reply is on its way a typed turn is refused (the screen keeps the text)', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.turns.submitText('Hello');
        async.flushMicrotasks();
        expect(r.turns.phase, TalkPhase.thinking);
        bool? sent;
        r.turns.submitText('Are you there?').then((v) => sent = v);
        async.flushMicrotasks();
        expect(sent, isFalse);
        expect(r.sent, hasLength(1));
      });
    });
  });

  group('TurnTaker mute', () {
    test('mute closes the microphone until unmuted, also when muted mid-reply', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.turns.listen();
        async.flushMicrotasks();
        r.turns.setMuted(true);
        async.flushMicrotasks();
        expect(r.turns.phase, TalkPhase.muted);
        expect(r.listener.active, isFalse);
        r.turns.setMuted(false);
        async.flushMicrotasks();
        expect(r.turns.phase, TalkPhase.listening);

        r.listener.say('Hello');
        async.elapse(const Duration(seconds: 1));
        r.turns.addSentence(1, const SpokenSentence('Hi there, friend.'));
        r.turns.replyComplete(1);
        async.flushMicrotasks();
        r.turns.setMuted(true);
        r.out.finish();
        async.elapse(const Duration(seconds: 1));
        expect(r.turns.phase, TalkPhase.muted);
        expect(r.listener.starts, 2, reason: "no new listening while muted");
      });
    });

    test('a failed reply goes back to idle; stale replies are ignored', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.turns.submitText('Hi');
        r.turns.replyFailed(1);
        expect(r.turns.phase, TalkPhase.idle);
        r.turns.addSentence(1, const SpokenSentence('Too late.'));
        async.flushMicrotasks();
        expect(r.out.played, isEmpty);
      });
    });
  });

  group('faster replies', () {
    test('a late reply gets an instant backchannel; the real reply follows it', () {
      fakeAsync((async) {
        final r = Rig(async, config: const TurnConfig(), acks: AckPicker(['Mm-hm.']));
        r.turns.listen();
        async.flushMicrotasks();
        r.listener.say('I went to Izmir');
        async.elapse(const Duration(milliseconds: 700)); // default pause
        expect(r.sent.single.$2, 'I went to Izmir');
        async.elapse(const Duration(milliseconds: 299));
        expect(r.out.played, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(r.out.played, ['Mm-hm.']);
        expect(r.turns.phase, TalkPhase.speaking);
        expect(r.latencies.single, const Duration(milliseconds: 1000)); // 700 pause + 300
        async.elapse(const Duration(milliseconds: 500));
        r.turns.addSentence(1, const SpokenSentence('Oh, nice!'));
        r.turns.replyComplete(1);
        expect(r.firstReal.single, const Duration(milliseconds: 1500));
        r.out.finish(); // the backchannel ends
        async.flushMicrotasks();
        expect(r.out.played, ['Mm-hm.', 'Oh, nice!']);
        // A barge-in now counts only real sentences as heard.
        r.bargeIn.speak();
        async.flushMicrotasks();
        expect(r.barged.single, (1, 0));
      });
    });

    test('no backchannel when the reply is already there', () {
      fakeAsync((async) {
        final r = Rig(async, config: const TurnConfig(), acks: AckPicker(['Mm-hm.']));
        r.turns.submitText('Hi');
        async.elapse(const Duration(milliseconds: 200));
        r.turns.addSentence(1, const SpokenSentence('Hello!'));
        async.elapse(const Duration(seconds: 1));
        expect(r.out.played, ['Hello!']);
        expect(r.latencies.single, const Duration(milliseconds: 200));
      });
    });

    test('a turn ending on "and", "because", "um"… waits a bit longer', () {
      fakeAsync((async) {
        final r = Rig(async, config: const TurnConfig());
        r.turns.listen();
        async.flushMicrotasks();
        r.listener.say('I like football because');
        async.elapse(const Duration(milliseconds: 900));
        expect(r.sent, isEmpty);
        r.listener.say('I like football because it is fun');
        async.elapse(const Duration(milliseconds: 700));
        expect(r.sent.single.$2, 'I like football because it is fun');
      });
      expect(soundsUnfinished('I want to go to the'), isTrue);
      expect(soundsUnfinished('um'), isTrue);
      expect(soundsUnfinished('I went to London.'), isFalse);
    });

    test('AckPicker never repeats the last one and carries the neural audio', () {
      final picker = AckPicker(['Mm-hm.', 'Right…', 'Okay.'], random: Random(1));
      picker.setAudio('Okay.', Uint8List.fromList([1, 2]));
      String? last;
      for (var i = 0; i < 50; i++) {
        final s = picker.pick()!;
        expect(s.text, isNot(last));
        expect(s.ack, isTrue);
        if (s.text == 'Okay.') expect(s.audio, [1, 2]);
        last = s.text;
      }
      expect(AckPicker(['Only.']).pick(), isNotNull);
      final one = AckPicker(['Only.'])..pick();
      expect(one.pick(), isNull, reason: 'never twice in a row');
      expect(backchannelsFor(characterById('taxi_london')), contains('Right, mate.'));
    });

    test('latencyStats: median and p90', () {
      expect(latencyStats([]), isNull);
      final st = latencyStats([900, 100, 500, 300, 700, 200, 400, 800, 600, 1000])!;
      expect(st.median, 600);
      expect(st.p90, 900);
    });
  });

  test('looksLikeEcho', () {
    expect(looksLikeEcho('heading today', 'Where are we heading today?'), isTrue);
    expect(looksLikeEcho('to the airport', 'Where are we heading today?'), isFalse);
    expect(looksLikeEcho('yes', 'Yes or no?'), isFalse, reason: 'one word is too little to tell');
    expect(looksLikeEcho('anything', ''), isFalse);
  });

  test('BargeInVad: calibrates on the echo residue, then needs a held loud voice', () {
    final vad = BargeInVad();
    final t0 = DateTime(2026);
    var t = Duration.zero;
    bool feed(double db) {
      t += const Duration(milliseconds: 50);
      return vad.feed(db, t0.add(t));
    }

    for (var i = 0; i < 8; i++) {
      expect(feed(-50), isFalse);
    }
    expect(feed(-45), isFalse, reason: 'echo residue below the margin');
    expect(feed(-30), isFalse); // loud starts
    expect(feed(-30), isFalse);
    expect(feed(-50), isFalse); // a click, not speech
    for (var i = 0; i < 5; i++) {
      feed(-28);
    }
    expect(feed(-28), isTrue);
  });

  test('pcmDbfs', () {
    expect(pcmDbfs(Uint8List(0)), -100);
    expect(pcmDbfs(Uint8List(320)), -100);
    final full = ByteData(4)
      ..setInt16(0, 32767, Endian.little)
      ..setInt16(2, -32768, Endian.little);
    expect(pcmDbfs(full.buffer.asUint8List()), closeTo(0, 0.01));
  });

  group('talk client', () {
    test('TalkRequest names the chat, level, goal and voice', () {
      final r = TalkRequest(
        scenario: characterScenario(characterById('taxi_london')!),
        history: const [ChatMessage(fromUser: true, text: 'Hi')],
        level: 'A2',
        goal: 'interview',
        voice: 'gb_orus',
      );
      expect(r.toApi(), {
        'characterId': 'taxi_london',
        'level': 'A2',
        'goal': 'interview',
        'voice': 'gb_orus',
        'messages': [
          {'role': 'user', 'content': 'Hi'},
        ],
      });
      expect(scenarioById('cafe').api, {'scenarioId': 'cafe'});
      expect(freeTalkScenario('Futbol').api, {'mode': 'free', 'topic': 'football'});
      expect(freeTalkScenario('Japonya gezisi').api['topic'], 'Japonya gezisi');
    });

    test('streams sentences with audio, then the final turn', () async {
      Map<String, Object?>? got;
      final service = CallableTalkService((name, data) async* {
        got = data;
        yield (done: false, data: {'type': 'sentence', 'i': 0, 'text': 'Oh, nice!', 'audio': 'AAEC'});
        yield (done: false, data: {'type': 'sentence', 'i': 1, 'text': 'Which team?', 'audio': null});
        yield (
          done: true,
          data: {
            'reply': 'Oh, nice! Which team?',
            'correction': 'I like football.',
            'tip_tr': 'Nokta',
            'done': false,
            'remaining': 299,
            'free': false,
            'voice': 'neural',
            'talkSecondsLeft': 2600,
            'timing': {'firstAudioMs': 840},
          },
        );
      }, (name, data) async => null);
      final events = await service
          .talk(
            TalkRequest(
              scenario: freeTalkScenario(''),
              history: const [ChatMessage(fromUser: true, text: 'x')],
            ),
          )
          .toList();
      expect(got?['mode'], 'free');
      final s0 = events[0] as TalkSentenceEvent;
      expect(s0.text, 'Oh, nice!');
      expect(s0.audio, [0, 1, 2]);
      expect((events[1] as TalkSentenceEvent).audio, isNull);
      final done = events[2] as TalkDoneEvent;
      expect(done.turn.correction, 'I like football.');
      expect(done.neural, isTrue);
      expect(done.talkSecondsLeft, 2600);
      expect(done.serverFirstAudioMs, 840);
    });

    test('maps the fair-use and free-quota stops to Turkish messages', () async {
      Future<ConversationException> fail(String code, String message) async {
        final service = CallableTalkService(
          (name, data) => Stream.error(FirebaseFunctionsException(code: code, message: message)),
          (name, data) async => null,
        );
        try {
          await service.talk(TalkRequest(scenario: freeTalkScenario(''), history: const [])).toList();
        } on ConversationException catch (e) {
          return e;
        }
        throw StateError('no error');
      }

      final fair = await fail('resource-exhausted', 'fair_use');
      expect(fair.code, fairUseCode);
      expect(fair.message, contains('45 dakika'));
      expect((await fail('resource-exhausted', 'free_quota')).freeQuotaUsed, isTrue);
      expect((await fail('unavailable', 'upstream_busy')).message, contains('yoğun'));
    });

    test('splitSentences and the demo service', () async {
      expect(splitSentences('Hi! How are you? Fine.'), ['Hi!', 'How are you?', 'Fine.']);
      final events = await DemoTalkService()
          .talk(
            TalkRequest(
              scenario: scenarioById('cafe'),
              history: const [ChatMessage(fromUser: true, text: 'A coffee please')],
            ),
          )
          .toList();
      expect(events.whereType<TalkSentenceEvent>(), isNotEmpty);
      expect(events.last, isA<TalkDoneEvent>());
    });
  });

  test('VoiceSettings: json round trip, unknown voices fall back', () {
    const s = VoiceSettings(
      voice: 'gb_leda',
      characterVoices: {'emma': 'us_puck'},
      bargeIn: false,
      pauseMs: 1200,
      level: 'A2',
    );
    final back = VoiceSettings.fromJson(s.toJson());
    expect(back.voice, 'gb_leda');
    expect(back.voiceFor(characterById('emma')), 'us_puck');
    expect(back.voiceFor(characterById('taxi_london')), 'gb_fenrir');
    expect(back.turnConfig.endOfTurn, const Duration(milliseconds: 1200));
    expect(back.level, 'A2');
    expect(VoiceSettings.fromJson({'voice': 'eleven_x', 'level': 'Z'}).voice, defaultVoiceId);
    expect(deviceRateFor('A1'), lessThan(deviceRateFor('B1')));
  });

  test('catalog: goal-linked topics and characters', () {
    expect(topicsFor(null).first.tr, 'Futbol');
    expect(topicsFor(GoalKind.exam).first.en, 'climate change');
    expect(topicsFor(GoalKind.interview).first.en, contains('interview'));
    expect(charactersFor(GoalKind.interview).first.id, 'hr_manager');
    expect(charactersFor(GoalKind.exam).first.id, 'lecturer');
    expect(characters.map((c) => c.id).toSet().length, characters.length);
    for (final c in characters) {
      expect(neuralVoices.any((v) => v.id == c.voice), isTrue, reason: c.id);
    }
    expect(characterById(dailyCaller)?.name, 'Emma');
  });

  group('screens', () {
    Future<List<Override>> overrides(
      WidgetTester tester, {
      bool premium = true,
      bool kid = false,
      TalkService? talk,
      required FakeListener listener,
      required FakeOut out,
    }) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      return [
        prefsProvider.overrideWithValue(
          await prefsWith({if (kid) AppSettingsNotifier.key: '{"mode":"kid"}'}),
        ),
        clockProvider.overrideWithValue(() => now),
        billingServiceProvider.overrideWithValue(FakeBilling()),
        premiumDevOverrideProvider.overrideWithValue(premium),
        speechProvider.overrideWithValue(VoiceSpeech()),
        conversationServiceProvider.overrideWithValue(FakeChat()),
        conversationReportServiceProvider.overrideWithValue(FakeReport()),
        talkServiceProvider.overrideWithValue(talk ?? DemoTalkService(FakeChat())),
        talkIoProvider.overrideWithValue(({required bool call, required bool bargeIn}) {
          return TalkIo(listener: listener, out: out);
        }),
      ];
    }

    testWidgets('chat: opening line, a spoken turn, the reply, then the karne with the silent correction', (
      tester,
    ) async {
      final listener = FakeListener();
      final out = FakeOut();
      final chat = FakeChat(
        turn: const ChatTurn(
          reply: 'Oh, you went to Izmir? What did you do?',
          correction: 'I went to Izmir.',
        ),
      );
      final o = await overrides(tester, listener: listener, out: out, talk: DemoTalkService(chat));
      await tester.pumpWidget(
        ProviderScope(
          overrides: o,
          child: MaterialApp(home: TalkScreen(scenario: characterScenario(characterById('emma')!))),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(out.played, [characterById('emma')!.opening]);
      expect(find.textContaining('Konuşuyor'), findsOneWidget);
      out.finish();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Dinliyorum…'), findsOneWidget);
      expect(listener.starts, 1, reason: 'listening opened by itself');
      _expectNoMicButton();
      listener.say('I go to Izmir');
      await tester.pump(const Duration(milliseconds: 1100));
      // "Şunu mu dedin?" first: it goes by itself after the countdown.
      expect(find.text('Şunu mu dedin?'), findsOneWidget);
      expect(find.text('“I go to Izmir”'), findsOneWidget);
      expect(chat.sent, isEmpty);
      _expectNoMicButton();
      await tester.pump(utteranceConfirmDelay);
      expect(chat.sent.single.last.text, 'I go to Izmir');
      expect(find.text('Şunu mu dedin?'), findsNothing);
      await tester.pump(const Duration(milliseconds: 800)); // demo delay
      expect(find.text('Oh, you went to Izmir? What did you do?'), findsOneWidget);
      // No lecture in the chat: the correction waits for the karne.
      expect(find.textContaining('I went to Izmir.'), findsNothing);
      expect(out.played.last, 'Oh, you went to Izmir?');

      await tester.tap(find.text('Bitir'));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationReportScreen), findsOneWidget);
    });

    testWidgets('typing while the partner speaks sends the text; it is never lost', (tester) async {
      final listener = FakeListener();
      final out = FakeOut();
      final chat = _SlowChat();
      final o = await overrides(tester, listener: listener, out: out, talk: DemoTalkService(chat));
      await tester.pumpWidget(
        ProviderScope(
          overrides: o,
          child: MaterialApp(home: TalkScreen(scenario: characterScenario(characterById('emma')!))),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Konuşuyor'), findsOneWidget);
      await tester.tap(find.byKey(const Key('talk-to-text')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('talk-input')), 'A latte please');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(chat.sent.single.last.text, 'A latte please', reason: 'sent, not dropped');
      expect(find.text('A latte please'), findsOneWidget, reason: 'shown as the learner message');
      expect(tester.widget<TextField>(find.byKey(const Key('talk-input'))).controller!.text, isEmpty);

      // The reply is on its way: a new text stays in the field.
      await tester.enterText(find.byKey(const Key('talk-input')), 'And a cookie');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(chat.sent, hasLength(1));
      expect(tester.widget<TextField>(find.byKey(const Key('talk-input'))).controller!.text, 'And a cookie');
      chat.reply.complete(const ChatTurn(reply: 'Great, one latte coming up.'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('phone call: no transcript during the call, mute and hang up, then the karne', (
      tester,
    ) async {
      final listener = FakeListener();
      final out = FakeOut();
      final o = await overrides(tester, listener: listener, out: out);
      final c = characterById('emma')!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: o,
          child: MaterialApp(home: TalkScreen(scenario: characterScenario(c, call: true), call: true)),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Emma'), findsOneWidget);
      expect(find.byKey(const Key('call-hangup')), findsOneWidget);
      expect(out.played, [c.callOpening]);
      expect(find.text(c.callOpening), findsNothing, reason: 'audio only during the call');
      out.finish();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Dinliyorum…'), findsOneWidget);
      expect(listener.starts, 1, reason: 'the call listens by itself');
      _expectNoMicButton();
      await tester.tap(find.byKey(const Key('call-mute')));
      await tester.pump();
      expect(find.text('Dinleme duraklatıldı'), findsOneWidget);
      await tester.tap(find.byKey(const Key('call-mute')));
      await tester.pump();
      // Room speech heard as the learner: cancelled, the call listens on.
      listener.say('Minneapolis');
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text('“Minneapolis”'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^İptal')), findsOneWidget);
      await tester.tap(find.byKey(const Key('talk-confirm-cancel')));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('talk-confirm')), findsNothing);
      expect(find.text('Dinliyorum…'), findsOneWidget);
      _expectNoMicButton();
      // Tapping the text sends it at once.
      listener.say('Sure I have time');
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.tap(find.byKey(const Key('talk-confirm-send')));
      await tester.pump();
      expect(find.byKey(const Key('talk-confirm')), findsNothing);
      expect(find.text('Dinliyorum…'), findsNothing, reason: 'sent: the partner answers');
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Sure I have time'), findsNothing);
      await tester.tap(find.byKey(const Key('call-hangup')));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationReportScreen), findsOneWidget);
    });

    testWidgets('Konuş page: natural talk for adults; kid mode has no live AI and no characters', (
      tester,
    ) async {
      final o = await overrides(tester, listener: FakeListener(), out: FakeOut());
      await tester.pumpWidget(
        ProviderScope(
          overrides: o,
          child: const MaterialApp(home: Scaffold(body: ConversationHomeScreen())),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('natural-talk')), findsOneWidget);
      expect(find.byKey(const Key('character-emma')), findsOneWidget);

      final kidO = await overrides(tester, kid: true, listener: FakeListener(), out: FakeOut());
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: kidO,
          child: const MaterialApp(home: Scaffold(body: ConversationHomeScreen())),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('natural-talk')), findsNothing);
      expect(find.byKey(const Key('free-taste-banner')), findsNothing);
      // A scenario opens the scripted demo chat, never the live voice partner.
      await tester.tap(find.text(scenarioById('cafe').title));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(find.byType(TalkScreen), findsNothing);
    });

    testWidgets('Premium scenarios open the natural voice partner', (tester) async {
      final o = await overrides(tester, listener: FakeListener(), out: FakeOut());
      await tester.pumpWidget(
        ProviderScope(
          overrides: o,
          child: const MaterialApp(home: Scaffold(body: ConversationHomeScreen())),
        ),
      );
      await tester.pump();
      await tester.tap(find.text(scenarioById('cafe').title));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(TalkScreen), findsOneWidget);
    });
  });
}
