import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Text-to-speech for prompts and speech recognition for speaking exercises.
class SpeechService {
  final _tts = FlutterTts();
  final _stt = SpeechToText();
  bool? _sttReady;

  Future<void> say(String text, {String lang = 'en', bool slow = false}) async {
    try {
      await _tts.stop();
      await _tts.setLanguage(lang == 'tr' ? 'tr-TR' : 'en-US');
      await _tts.setSpeechRate(slow ? 0.22 : 0.45);
      await _tts.speak(text);
    } catch (_) {
      // No TTS engine on the device: exercises still work without audio.
    }
  }

  Future<bool> get canListen async {
    try {
      return _sttReady ??= await _stt.initialize();
    } catch (_) {
      return _sttReady = false;
    }
  }

  /// Listens in English, reporting partial text, and calls [onDone] when
  /// recognition stops.
  Future<void> listen({
    required void Function(String words) onWords,
    required void Function() onDone,
  }) async {
    if (!await canListen) {
      onDone();
      return;
    }
    await _stt.listen(
      onResult: (r) {
        onWords(r.recognizedWords);
        if (r.finalResult) onDone();
      },
      listenOptions: SpeechListenOptions(
        localeId: 'en_US',
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
      ),
    );
  }

  Future<void> stopListening() => _stt.stop();
}

final speechProvider = Provider<SpeechService>((ref) => SpeechService());
