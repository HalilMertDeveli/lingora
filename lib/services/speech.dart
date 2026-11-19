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

import '../core/spoken_match.dart';
import 'voice_pack.dart';

/// The last speech problem worth telling the learner about (no English voice,
/// no microphone permission, nothing heard…), or null. Screens show it next
/// to the speaker / microphone buttons.
final speechIssue = ValueNotifier<String?>(null);

/// Microphone loudness while listening, from 0 (silence) to 1 (loud), so the
/// learner sees that they are being heard.
final speechLevel = ValueNotifier<double>(0);

/// One recognizer guess and how sure it was (0..1; null when not reported).
typedef SpeechGuess = ({String words, double? confidence});

/// The recognizer's guesses for the last finished utterance, its favourite
/// first (empty while listening). The voice coach turns them into
/// pronunciation evidence (lib/core/speech_evidence.dart). Fake speech
/// services in tests may set it themselves.
final lastRecognition = ValueNotifier<List<SpeechGuess>>(const []);

/// How long to wait for a sentence of [words] words: the silence after which
/// listening stops, and the longest a whole try may take. Learners pause
/// mid-sentence, so long sentences get more time.
({Duration pause, Duration total}) listenTimes(int words) => (
  pause: Duration(milliseconds: (3500 + 250 * words).clamp(4000, 7000)),
  total: Duration(seconds: (8 + words).clamp(12, 30)),
);

/// Turns a recognizer sound level (Android rmsdB, about -2..10) into 0..1.
double normalizeSoundLevel(double db) => ((db + 2) / 12).clamp(0.0, 1.0);

/// Picks the recognizer locale for [wanted] ("en-US") among [available]
/// locale ids: the wanted one, then US or British English, then any English.
/// Null when the list names languages but no English at all.
String? pickEnglishLocale(String wanted, List<String> available) {
  String id(String s) => s.replaceAll('-', '_').toLowerCase();
  final byId = {for (final a in available) id(a): a};
  if (byId.isEmpty) return wanted.replaceAll('-', '_');
  for (final c in [wanted, 'en_US', 'en_GB']) {
    final hit = byId[id(c)];
    if (hit != null) return hit;
  }
  for (final e in byId.entries) {
    if (e.key == 'en' || e.key.startsWith('en_')) return e.value;
  }
  return null;
}

/// Turkish texts for [speechIssue].
abstract final class SpeechIssues {
  static const noEngine =
      'Telefonunda metin okuma motoru yok. Play Store\'dan "Google Konuşma Hizmetleri"ni kurup tekrar dene.';
  static const noEnglishVoice =
      'Telefonunda İngilizce ses paketi yok. Ayarlar > Erişilebilirlik > Metin okuma çıktısı bölümünden '
      'İngilizce ses verilerini indir.';
  static const noMicPermission =
      'Mikrofon izni verilmedi. Ayarlar > Uygulamalar > Çenebaz > İzinler bölümünden mikrofonu aç.';
  static const noRecognizer = 'Bu cihazda ses tanıma kullanılamıyor.';
  static const notHeard = 'Seni duyamadım. Telefonu biraz daha yakına al ve daha yüksek sesle söyle.';
  static const network = 'Ses tanıma için internet bağlantısı gerekiyor.';
  static const noEnglishRecognizer =
      'Telefonunda İngilizce ses tanıma paketi yok gibi görünüyor. Google uygulamasını aç: profil resmin > '
      'Ayarlar > Google Asistan ya da Ses > Çevrimdışı konuşma tanıma bölümünden "English (US)" paketini indir.';
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
    final speed = (slow ? slowSpeechRate : 0.45) * rate;
    try {
      await _stopVoice();
      // A studio recording of this sentence, when there is one.
      if (lang != 'tr' && !kIsWeb) {
        final source = await _pack.sourceFor(text);
        if (id != _request) return;
        if (source != null) {
          final p = _player ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
          await p.setSource(source);
          await p.setPlaybackRate(slow ? slowRecordingRate : rate.clamp(0.5, 1.5));
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
  Timer? _doneFallback;
  String? _localeId;

  /// The sentence the next [listen] expects (see [SpeakingTarget.listenTo]):
  /// sets how long to listen and picks the best of the recognizer's guesses.
  static String? _target;

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

  /// The English locale the phone's recognizer offers, looked up once: a
  /// Turkish phone may only have en-GB, or "en" alone.
  Future<String> _englishLocaleId() async {
    final known = _localeId;
    if (known != null) return known;
    var pick = englishLocale.replaceAll('-', '_');
    try {
      final locales = await _stt.locales().timeout(const Duration(seconds: 3));
      final found = pickEnglishLocale(englishLocale, [for (final l in locales) l.localeId]);
      if (found == null) {
        // Languages are listed but no English: tell where to get it, then try anyway.
        speechIssue.value = SpeechIssues.noEnglishRecognizer;
      } else {
        pick = found;
      }
      debugPrint('Speech locale $pick of ${locales.length}');
    } catch (_) {}
    return _localeId = pick;
  }

  void _status(String status) {
    if (status == SpeechToText.doneStatus) {
      _finish();
    } else if (status == SpeechToText.notListeningStatus && _onDone != null) {
      // The microphone closed; the final result (with all the recognizer's
      // guesses) usually follows a moment later with "done". Finishing here
      // would judge a half-heard partial result.
      _doneFallback?.cancel();
      _doneFallback = Timer(const Duration(milliseconds: 1500), _finish);
    }
  }

  void _error(SpeechRecognitionError e) {
    debugPrint('Speech recognition error: ${e.errorMsg}');
    final issue = SpeechIssues.forError(e.errorMsg, heardSomething: _heardSomething);
    // Words were heard before the error: judge them instead of hiding them.
    if (!(_heardSomething && e.errorMsg == 'error_no_match')) speechIssue.value = issue;
    _finish();
  }

  /// Calls the pending onDone exactly once, however recognition ended
  /// (final result, silence timeout, error or the stop button).
  void _finish() {
    _doneFallback?.cancel();
    _doneFallback = null;
    speechLevel.value = 0;
    final done = _onDone;
    _onDone = null;
    done?.call();
  }

  /// Listens in English, reporting partial text, and calls [onDone] when
  /// recognition stops, also after an error or when nothing was heard.
  Future<void> listen({required void Function(String words) onWords, required void Function() onDone}) async {
    final target = _target;
    _target = null;
    if (!await canListen) {
      onDone();
      return;
    }
    await _stopVoice(); // the microphone must not hear the app's own voice
    speechIssue.value = null;
    _heardSomething = false;
    lastRecognition.value = const [];
    _finish(); // a previous session that never reported back
    _onDone = onDone;
    final times = target == null
        ? (pause: const Duration(seconds: 4), total: const Duration(seconds: 20))
        : listenTimes(target.split(RegExp(r'\s+')).length);
    try {
      final locale = await _englishLocaleId();
      final joiner = TranscriptJoiner();
      await _stt.listen(
        onResult: (r) {
          final guesses = [for (final a in r.alternates) a.recognizedWords];
          final words = joiner.add(
            bestTranscription(target, guesses.isEmpty ? [r.recognizedWords] : guesses),
          );
          if (words.isNotEmpty) _heardSomething = true;
          onWords(words);
          if (r.finalResult) {
            lastRecognition.value = r.alternates.isEmpty
                ? [(words: r.recognizedWords, confidence: r.hasConfidenceRating ? r.confidence : null)]
                : [
                    for (final a in r.alternates)
                      (words: a.recognizedWords, confidence: a.hasConfidenceRating ? a.confidence : null),
                  ];
            _finish();
          }
        },
        onSoundLevelChange: (db) => speechLevel.value = normalizeSoundLevel(db),
        listenOptions: SpeechListenOptions(
          localeId: locale,
          listenFor: times.total,
          pauseFor: times.pause,
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
    Future<void>.delayed(const Duration(milliseconds: 1000), _finish);
  }
}

/// Listening for a known sentence.
extension SpeakingTarget on SpeechService {
  /// [SpeechService.listen] for the learner saying [target]: longer
  /// sentences get more time, and of the recognizer's guesses the one
  /// closest to [target] is reported.
  Future<void> listenTo(
    String target, {
    required void Function(String words) onWords,
    required void Function() onDone,
  }) {
    SpeechService._target = target;
    return listen(onWords: onWords, onDone: onDone);
  }
}

final speechProvider = Provider<SpeechService>((ref) => SpeechService());

/// Joins a dictation session's partial results into one text. Some
/// recognizers (Galaxy M22, Android 13) start a new segment after each pause
/// and report only that segment, first as empty: without joining, every
/// pause erased what was said before it.
class TranscriptJoiner {
  final _done = <String>[];
  String _current = '';

  /// Takes the next partial (or final) result; returns the whole text so far.
  String add(String words) {
    final w = words.trim();
    if (w.isEmpty) {
      _close();
    } else if (_current.isNotEmpty && !_continues(w)) {
      _close();
      _current = w;
    } else {
      _current = w;
    }
    return [..._done, if (_current.isNotEmpty) _current].join(' ');
  }

  /// [w] grows or revises the current segment: same first word, or the
  /// segment is still too short to tell a revision from a new one.
  bool _continues(String w) =>
      _firstWord(w) == _firstWord(_current) || _current.split(RegExp(r'\s+')).length < 3;

  static String _firstWord(String s) => s.split(RegExp(r'\s+')).first.toLowerCase();

  void _close() {
    if (_current.isNotEmpty) _done.add(_current);
    _current = '';
  }
}

/// Plays the lines of a listening dialogue one after another: each call
/// completes when the line has been heard.
abstract interface class LinePlayer {
  Future<void> sayLine(String text, {double rate = 1, double pitch = 1});
  Future<void> stopLine();
}

/// Slow reading (the turtle button) on the phone's speech engine: about a
/// third of normal speed, so each word can be heard on its own.
const slowSpeechRate = 0.15;

/// Slow playback of a studio recording. Lower than this the voice starts to
/// smear, so recordings slow down less than the speech engine.
const slowRecordingRate = 0.6;

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
