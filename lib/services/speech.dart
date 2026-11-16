import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'voice_pack.dart';

/// The last speech problem worth telling the learner about (no English voice,
/// no microphone permission, nothing heard…), or null. Screens show it next
/// to the speaker / microphone buttons.
final speechIssue = ValueNotifier<String?>(null);

/// Turkish texts for [speechIssue].
abstract final class SpeechIssues {
  static const noEngine =
      'Telefonunda metin okuma motoru yok. Play Store\'dan "Google Konuşma Hizmetleri"ni kurup tekrar dene.';
  static const noEnglishVoice =
      'Telefonunda İngilizce ses paketi yok. Ayarlar > Erişilebilirlik > Metin okuma çıktısı bölümünden '
      'İngilizce ses verilerini indir.';
  static const noMicPermission =
      'Mikrofon izni verilmedi. Ayarlar > Uygulamalar > Dilmaç > İzinler bölümünden mikrofonu aç.';
  static const noRecognizer = 'Bu cihazda ses tanıma kullanılamıyor.';
  static const notHeard = 'Seni duyamadım. Mikrofona dokunup biraz daha yüksek sesle tekrar dene.';
  static const network = 'Ses tanıma için internet bağlantısı gerekiyor.';
  static const noEnglishRecognizer =
      'Telefonunda İngilizce ses tanıma yok. Ayarlar > Sistem > Diller > Konuşma tanıma bölümünden '
      'İngilizceyi indir ya da Google uygulamasını güncelle.';
  static const busy = 'Ses tanıma şu an meşgul. Birkaç saniye sonra tekrar dene.';

  /// Turkish text for a speech_to_text error code; unknown codes stay
  /// visible so a failure on a real phone can be reported.
  static String forError(String code, {required bool heardSomething}) => switch (code) {
    'error_no_match' || 'error_speech_timeout' => heardSomething ? notHeardClearly : notHeard,
    'error_network' || 'error_network_timeout' || 'error_server_disconnected' => network,
    'error_permission' || 'error_insufficient_permissions' => noMicPermission,
    'error_language_not_supported' || 'error_language_unavailable' => noEnglishRecognizer,
    'error_busy' || 'error_recognizer_busy' || 'error_too_many_requests' => busy,
    _ => 'Ses tanıma çalışmadı ($code). Tekrar dene.',
  };
  static const notHeardClearly = 'Tam anlayamadım. Biraz daha yavaş ve net söyleyip tekrar dene.';
}

/// Text-to-speech for prompts and speech recognition for speaking exercises.
///
/// On Android the sentence is first written to a small audio file and then
/// played by the app itself: newer Android versions may mute the speech
/// engine's own playback when it runs as a separate background process
/// ("AudioHardening"), which left lessons silent on some phones.
class SpeechService {
  /// Locale of the English voice (en-US or en-GB); set by the app root from
  /// the accent setting.
  static String englishLocale = 'en-US';

  final _tts = FlutterTts();
  final _stt = SpeechToText();
  final _pack = VoicePack();
  bool _sttReady = false;
  AudioPlayer? _player;
  Directory? _cacheDir;
  int _request = 0;
  final _voiceChecked = <String, bool>{};

  bool get _android => !kIsWeb && Platform.isAndroid;

  /// Reads [text] aloud. [rate] scales the normal speed (0.75 for the
  /// slower listening of stories and shadowing).
  Future<void> say(String text, {String lang = 'en', bool slow = false, double rate = 1}) =>
      _speak(text, lang: lang, slow: slow, rate: rate);

  /// [pitch] only changes the phone's engine (recordings keep their voice);
  /// with [wait] the future completes when the sentence has been heard or
  /// was cut off by another one.
  Future<void> _speak(
    String text, {
    String lang = 'en',
    bool slow = false,
    double rate = 1,
    double pitch = 1,
    bool wait = false,
  }) async {
    final id = ++_request;
    final locale = lang == 'tr' ? 'tr-TR' : englishLocale;
    final speed = (slow ? 0.22 : 0.45) * rate;
    try {
      await _stopVoice();
      // A studio recording of this sentence, when there is one.
      if (lang != 'tr' && !kIsWeb) {
        final asset = await _pack.assetFor(text);
        if (id != _request) return;
        if (asset != null) {
          final p = _player ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
          await p.setSource(AssetSource(asset));
          await p.setPlaybackRate(slow ? 0.7 : rate.clamp(0.5, 1.5));
          final heard = wait ? _ended(p) : null;
          await p.resume();
          await heard;
          return;
        }
      }
      if (!await _hasVoice(locale)) return;
      if (_android) {
        final path = await _synthesize(text, locale, speed, pitch);
        if (id != _request) return; // a newer sentence was asked for meanwhile
        if (path != null) {
          final p = _player ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
          final heard = wait ? _ended(p) : null;
          await p.play(DeviceFileSource(path));
          await heard;
          return;
        }
      }
      await _tts.setLanguage(locale);
      await _tts.setSpeechRate(speed);
      await _tts.setPitch(pitch);
      await _tts.awaitSpeakCompletion(wait);
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS failed: $e');
    }
  }

  /// Completes when [p] finishes or is stopped (at most a minute later).
  Future<void> _ended(AudioPlayer p) => p.onPlayerStateChanged
      .firstWhere((s) => s == PlayerState.completed || s == PlayerState.stopped)
      .timeout(const Duration(minutes: 1), onTimeout: () => PlayerState.stopped)
      .then((_) {}, onError: (Object _) {});

  Future<void> _stopVoice() async {
    try {
      await _player?.stop();
      await _tts.stop();
    } catch (_) {}
  }

  /// Whether a voice for [locale] exists; sets [speechIssue] when not.
  Future<bool> _hasVoice(String locale) async {
    final known = _voiceChecked[locale];
    if (known != null) return known;
    var ok = true;
    try {
      if (_android) {
        final engines = await _tts.getEngines;
        if (engines is List && engines.isEmpty) {
          speechIssue.value = SpeechIssues.noEngine;
          return _voiceChecked[locale] = false;
        }
      }
      final available = await _tts.isLanguageAvailable(locale);
      ok = available != false;
      if (!ok && locale.startsWith('en')) {
        // Try the other English accent before giving up.
        final other = locale == 'en-US' ? 'en-GB' : 'en-US';
        if (await _tts.isLanguageAvailable(other) == true) {
          englishLocale = other;
          ok = true;
        }
      }
    } catch (_) {
      ok = true; // cannot tell: try anyway
    }
    if (!ok) speechIssue.value = SpeechIssues.noEnglishVoice;
    return _voiceChecked[locale] = ok;
  }

  /// Writes the sentence to a cached WAV file and returns its path, or null
  /// when the engine cannot write files.
  Future<String?> _synthesize(String text, String locale, double speed, double pitch) async {
    try {
      final dir = _cacheDir ??= Directory('${(await getTemporaryDirectory()).path}/tts')
        ..createSync(recursive: true);
      // The pitch is part of the key only when it differs from the default,
      // so files cached by earlier versions are still found.
      final tone = pitch == 1 ? '' : '|p${pitch.toStringAsFixed(2)}';
      final key = base64Url.encode(utf8.encode('$locale|${speed.toStringAsFixed(3)}$tone|$text')).hashCode;
      final file = File('${dir.path}/${key.toUnsigned(32).toRadixString(16)}_${text.length}.wav');
      if (file.existsSync() && file.lengthSync() > 1000) return file.path;
      await _tts.setLanguage(locale);
      await _tts.setSpeechRate(speed);
      await _tts.setPitch(pitch);
      await _tts.awaitSynthCompletion(true);
      final result = await _tts.synthesizeToFile(text, file.path, true);
      if (result != 1) return null;
      // Some engines report success a moment before the file is complete.
      for (var i = 0; i < 20 && (!file.existsSync() || file.lengthSync() <= 1000); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return file.existsSync() && file.lengthSync() > 1000 ? file.path : null;
    } catch (e) {
      debugPrint('TTS to file failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------- listening

  void Function()? _onDone;
  bool _heardSomething = false;

  Future<bool> get canListen async {
    if (_sttReady) return true;
    try {
      _sttReady = await _stt.initialize(onStatus: _status, onError: _error);
    } catch (_) {
      _sttReady = false;
    }
    if (!_sttReady) {
      bool permitted;
      try {
        permitted = await _stt.hasPermission;
      } catch (_) {
        permitted = true;
      }
      speechIssue.value = permitted ? SpeechIssues.noRecognizer : SpeechIssues.noMicPermission;
    }
    // Not cached when false: the learner may grant the permission later.
    return _sttReady;
  }

  void _status(String status) {
    if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) _finish();
  }

  void _error(SpeechRecognitionError e) {
    debugPrint('Speech recognition error: ${e.errorMsg}');
    speechIssue.value = SpeechIssues.forError(e.errorMsg, heardSomething: _heardSomething);
    _finish();
  }

  /// Calls the pending onDone exactly once, however recognition ended
  /// (final result, silence timeout, error or the stop button).
  void _finish() {
    final done = _onDone;
    _onDone = null;
    done?.call();
  }

  /// Listens in English, reporting partial text, and calls [onDone] when
  /// recognition stops, also after an error or when nothing was heard.
  Future<void> listen({required void Function(String words) onWords, required void Function() onDone}) async {
    if (!await canListen) {
      onDone();
      return;
    }
    await _stopVoice(); // the microphone must not hear the app's own voice
    speechIssue.value = null;
    _heardSomething = false;
    _finish(); // a previous session that never reported back
    _onDone = onDone;
    try {
      await _stt.listen(
        onResult: (r) {
          if (r.recognizedWords.isNotEmpty) _heardSomething = true;
          onWords(r.recognizedWords);
          if (r.finalResult) _finish();
        },
        listenOptions: SpeechListenOptions(
          localeId: englishLocale.replaceAll('-', '_'),
          listenFor: const Duration(seconds: 10),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      debugPrint('Speech listen failed: $e');
      speechIssue.value = SpeechIssues.noRecognizer;
      _finish();
    }
  }

  Future<void> stopListening() async {
    try {
      await _stt.stop();
    } catch (_) {}
    // Some recognizers never send "done" after a manual stop.
    Future<void>.delayed(const Duration(milliseconds: 600), _finish);
  }
}

final speechProvider = Provider<SpeechService>((ref) => SpeechService());

/// Plays the lines of a listening dialogue one after another: each call
/// completes when the line has been heard.
abstract interface class LinePlayer {
  Future<void> sayLine(String text, {double rate = 1, double pitch = 1});
  Future<void> stopLine();
}

/// Engine pitch of a dialogue speaker, so two voices differ even without
/// recordings.
double pitchFor({required bool female}) => female ? 1.18 : 0.82;

/// Plays lines with the app's speech service; a stand-in speech service
/// (tests) reads them with [SpeechService.say].
final linePlayerProvider = Provider<LinePlayer>((ref) {
  final speech = ref.watch(speechProvider);
  return speech.runtimeType == SpeechService ? _SpeechLines(speech) : _SayLines(speech);
});

class _SpeechLines implements LinePlayer {
  _SpeechLines(this._speech);
  final SpeechService _speech;
  @override
  Future<void> sayLine(String text, {double rate = 1, double pitch = 1}) =>
      _speech._speak(text, rate: rate, pitch: pitch, wait: true);
  @override
  Future<void> stopLine() async {
    _speech._request++;
    await _speech._stopVoice();
  }
}

class _SayLines implements LinePlayer {
  _SayLines(this._speech);
  final SpeechService _speech;
  @override
  Future<void> sayLine(String text, {double rate = 1, double pitch = 1}) => _speech.say(text, rate: rate);
  @override
  Future<void> stopLine() async {}
}
