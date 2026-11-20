import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/speech.dart';
import 'turn_taking.dart';

/// The phone's speech recognizer as a [TurnListener]: the app's
/// [SpeechService] (English locale, segment joining, error texts) plus the
/// microphone level from [speechLevel].
class SpeechTurnListener implements TurnListener {
  SpeechTurnListener(this._speech);
  final SpeechService _speech;
  VoidCallback? _levelHook;

  @override
  Future<void> start({
    required void Function(String words) onWords,
    required void Function(double level) onLevel,
    required void Function() onEnd,
  }) async {
    _unhook();
    void hook() => onLevel(speechLevel.value);
    _levelHook = hook;
    speechLevel.addListener(hook);
    await _speech.listen(
      onWords: onWords,
      onDone: () {
        _unhook();
        onEnd();
      },
    );
  }

  void _unhook() {
    final h = _levelHook;
    if (h != null) speechLevel.removeListener(h);
    _levelHook = null;
  }

  @override
  Future<void> stop() async {
    _unhook();
    await _speech.stopListening();
  }
}

/// Plays the partner: neural MP3s with the app's own player, the phone's
/// voice ([LinePlayer]) for text-only sentences.
///
/// Routing: speaker by default; [earpiece] for phone-call mode held to the
/// ear. With [communication] (barge-in on) playback runs as a voice call so
/// the phone's echo canceller knows what is being played and removes it from
/// the barge-in microphone.
class AudioVoiceOut implements VoiceOut {
  AudioVoiceOut(this._lines, {this._earpiece = false, this._communication = true, this.phoneVoiceFile});

  final LinePlayer _lines;

  /// Writes the phone voice's audio for a text-only sentence (free users get
  /// no neural audio), so it plays on this player too: in phone-call mode
  /// that is the earpiece, and the speaker switch works.
  final Future<String?> Function(String text, double rate)? phoneVoiceFile;
  bool _callUser = false;
  bool _earpiece;
  bool _communication;
  AudioPlayer? _player;
  Directory? _dir;
  int _file = 0;
  Completer<void>? _playing;

  bool get earpiece => _earpiece;
  bool get _callMode => _communication || _earpiece;

  /// Switches between the earpiece and the loudspeaker (phone-call mode).
  Future<void> setRoute({required bool earpiece, bool? communication}) async {
    _earpiece = earpiece;
    _communication = communication ?? _communication;
    final p = _player;
    if (p != null) await _apply(p);
  }

  /// Sets the player's audio context; a call context changes Android's
  /// global audio mode, which [dispose] puts back.
  Future<void> _apply(AudioPlayer p) async {
    if (_callMode) {
      callAudioModeSet = true;
      if (!_callUser) {
        _callUser = true;
        callAudioUsers++;
      }
    }
    await p.setAudioContext(_context());
  }

  AudioContext _context() => AudioContext(
    android: AudioContextAndroid(
      isSpeakerphoneOn: !_earpiece,
      audioMode: _communication || _earpiece ? AndroidAudioMode.inCommunication : AndroidAudioMode.normal,
      stayAwake: true,
      contentType: AndroidContentType.speech,
      usageType: _communication || _earpiece ? AndroidUsageType.voiceCommunication : AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: {if (!_earpiece) AVAudioSessionOptions.defaultToSpeaker, AVAudioSessionOptions.allowBluetooth},
    ),
  );

  Future<AudioPlayer> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) return existing;
    final p = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    await _apply(p);
    return _player = p;
  }

  @override
  Future<void> play(SpokenSentence s) async {
    final audio = s.audio;
    if (kIsWeb) {
      await _lines.sayLine(s.text, rate: s.rate);
      return;
    }
    if (audio == null) {
      final file = _callMode ? await phoneVoiceFile?.call(s.text, s.rate) : null;
      if (file == null) {
        await _lines.sayLine(s.text, rate: s.rate);
      } else {
        await _playFile(DeviceFileSource(file), s);
      }
      return;
    }
    try {
      final p = await _ensurePlayer();
      final dir = _dir ??= Directory('${(await getTemporaryDirectory()).path}/talk')
        ..createSync(recursive: true);
      // A few rotating files: the player reads one while the next is written.
      final file = File('${dir.path}/s${_file++ % 6}.mp3');
      await file.writeAsBytes(audio, flush: true);
      await _playFile(DeviceFileSource(file.path), s, player: p);
    } catch (e) {
      debugPrint('Neural voice failed, phone voice instead: $e');
      await _lines.sayLine(s.text, rate: s.rate);
    }
  }

  Future<void> _playFile(Source source, SpokenSentence s, {AudioPlayer? player}) async {
    try {
      final p = player ?? await _ensurePlayer();
      final done = _playing = Completer<void>();
      final sub = p.onPlayerStateChanged.listen((st) {
        if ((st == PlayerState.completed || st == PlayerState.stopped) && !done.isCompleted) done.complete();
      });
      await p.play(source);
      await done.future.timeout(const Duration(seconds: 40), onTimeout: () {});
      await sub.cancel();
    } catch (e) {
      debugPrint('Voice chat playback failed, phone voice instead: $e');
      await _lines.sayLine(s.text, rate: s.rate);
    }
  }

  @override
  Future<void> stop() async {
    final done = _playing;
    if (done != null && !done.isCompleted) done.complete();
    try {
      await _player?.stop();
    } catch (_) {}
    await _lines.stopLine();
  }

  /// Ends the chat's audio: the player goes and Android's audio mode goes
  /// back to normal (a call context is global and would otherwise stay).
  Future<void> dispose() async {
    await stop();
    final p = _player;
    _player = null;
    if (p != null) {
      try {
        if (_callMode) await p.setAudioContext(AudioContext());
      } catch (_) {}
      await p.dispose();
    }
    if (_callUser) {
      _callUser = false;
      callAudioUsers--;
    }
    if (callAudioUsers == 0) await restoreNormalAudioMode();
  }
}

/// Decides from microphone loudness (dBFS, echo-cancelled) whether the
/// learner started talking over the partner. The first [calibration] learns
/// the room plus what the echo canceller leaves of the partner's voice; then
/// speech must be [margin] dB above that (and above [floor]) for [hold].
class BargeInVad {
  BargeInVad({
    this.calibration = const Duration(milliseconds: 400),
    this.hold = const Duration(milliseconds: 250),
    this.margin = 12,
    this.floor = -42,
  });
  final Duration calibration;
  final Duration hold;
  final double margin;
  final double floor;

  DateTime? _start;
  final _baseline = <double>[];
  DateTime? _loudSince;

  /// Takes one loudness reading at [at]; true once the learner is talking.
  bool feed(double dbfs, DateTime at) {
    final start = _start ??= at;
    if (at.difference(start) < calibration) {
      _baseline.add(dbfs);
      return false;
    }
    final sorted = [..._baseline]..sort();
    final base = sorted.isEmpty ? -60.0 : sorted[sorted.length ~/ 2];
    final threshold = math.max(base + margin, floor);
    if (dbfs < threshold) {
      _loudSince = null;
      return false;
    }
    final since = _loudSince ??= at;
    return at.difference(since) >= hold;
  }
}

/// Loudness of 16-bit little-endian PCM in dBFS (-100 for silence).
double pcmDbfs(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  if (n == 0) return -100;
  final data = ByteData.sublistView(bytes);
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final v = data.getInt16(i * 2, Endian.little) / 32768.0;
    sum += v * v;
  }
  final rms = math.sqrt(sum / n);
  return rms <= 0 ? -100 : 20 * math.log(rms) / math.ln10;
}

/// Barge-in on Android/iOS: an echo-cancelled, noise-suppressed microphone
/// stream (voice-communication source) runs only while the partner speaks.
/// The barge-in microphone: echo-cancelled voice-call input, and no audio
/// focus (see [RecordBargeIn]).
const bargeInRecordConfig = RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: 16000,
  numChannels: 1,
  echoCancel: true,
  noiseSuppress: true,
  // No audio focus: taking it paused the partner's voice a quarter
  // second in, and the turn waited for an end that never came (QA,
  // Galaxy M22: the greeting stopped, "Konuşuyor…" for 28 s).
  audioInterruption: AudioInterruptionMode.none,
  androidConfig: AndroidRecordConfig(
    audioSource: AndroidAudioSource.voiceCommunication,
    manageBluetooth: false,
  ),
);

class RecordBargeIn implements BargeInDetector {
  AudioRecorder? _rec;
  StreamSubscription<Uint8List>? _sub;
  bool _fired = false;

  @override
  Future<void> start(void Function() onSpeech) async {
    await stop();
    final rec = _rec = AudioRecorder();
    try {
      if (!await rec.hasPermission(request: false)) return;
      final stream = await rec.startStream(bargeInRecordConfig);
      final vad = BargeInVad();
      _fired = false;
      _sub = stream.listen((chunk) {
        if (_fired) return;
        if (vad.feed(pcmDbfs(chunk), DateTime.now())) {
          _fired = true;
          onSpeech();
        }
      });
    } catch (e) {
      debugPrint('Barge-in microphone unavailable: $e');
      await stop();
    }
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    final rec = _rec;
    _rec = null;
    if (rec == null) return;
    try {
      await rec.stop();
    } catch (_) {}
    await rec.dispose();
  }
}
