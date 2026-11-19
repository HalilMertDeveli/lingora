import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart' show prefsProvider;
import '../services/speech.dart';
import '../theme.dart';

/// Eller serbest konuşma: in lesson speaking exercises and the Telaffuz
/// koçu the learner does not have to press the microphone. Once the prompt
/// has finished playing (never while app audio plays, so the phone does not
/// hear itself), listening starts; the turn ends by itself shortly after
/// the learner stops talking, and the answer is checked. When nothing is
/// said for [noSpeechTimeout] a gentle hint and one retry button appear.
/// Without a microphone (or permission) the exercise keeps the button flow.

/// Silence after the last recognized word that ends the turn. Tunable: the
/// recognizer's final result still arrives after it (see `stopListening`).
const endOfSpeechSilence = Duration(milliseconds: 1000);

/// How long to wait for the first word before giving up.
const noSpeechTimeout = Duration(seconds: 7);

/// "Konuşma alıştırmalarında otomatik dinle" (Profil > Görünüm), default on.
class HandsFreeSetting extends Notifier<bool> {
  static const key = 'hands_free_listen_v1';

  @override
  bool build() {
    try {
      return ref.read(prefsProvider).getBool(key) ?? true;
    } catch (_) {
      return false; // no settings store (some tests): keep the button flow
    }
  }

  void set(bool on) {
    ref.read(prefsProvider).setBool(key, on);
    state = on;
  }
}

final handsFreeProvider = NotifierProvider<HandsFreeSetting, bool>(HandsFreeSetting.new);

/// The microphone was refused once this run: later exercises keep the
/// button flow instead of asking again and again.
bool handsFreeMicRefused = false;

enum HandsFreePhase { idle, prompting, listening, noSpeech }

/// One hands-free turn for [SpeechService]. The owner calls [run] and
/// [cancel] (on dispose or when the learner taps the microphone).
class HandsFreeTurn {
  HandsFreeTurn({
    required this.speech,
    required this.player,
    this.silence = endOfSpeechSilence,
    this.noSpeech = noSpeechTimeout,
  });

  final SpeechService speech;
  final LinePlayer player;
  final Duration silence;
  final Duration noSpeech;

  Timer? _silenceTimer;
  Timer? _noSpeechTimer;
  int _run = 0;
  bool _heard = false;
  bool _listening = false;

  bool get listening => _listening;

  /// Plays [prompt] (if any) to its end, then listens for [target].
  /// [onListening] fires when the microphone opens; [onDone] once when the
  /// turn ends, with `noSpeech` true when not a word was heard. Returns
  /// false when listening could not start (no microphone, cancelled): the
  /// caller then stays in the button flow.
  Future<bool> run({
    required String target,
    String? prompt,
    double promptRate = 1,
    required VoidCallback onListening,
    required void Function(String words) onWords,
    required void Function({required bool noSpeech}) onDone,
  }) async {
    final id = ++_run;
    if (prompt != null) {
      await player.sayLine(prompt, rate: promptRate);
      if (id != _run) return false;
    }
    if (handsFreeMicRefused) return false;
    if (!await speech.canListen) {
      handsFreeMicRefused = true;
      return false;
    }
    if (id != _run) return false;
    _heard = false;
    _listening = true;
    onListening();
    _noSpeechTimer = Timer(noSpeech, () {
      if (!_heard && id == _run) speech.stopListening();
    });
    await speech.listenTo(
      target,
      onWords: (w) {
        if (id != _run) return;
        if (w.trim().isNotEmpty) {
          _heard = true;
          _noSpeechTimer?.cancel();
          _silenceTimer?.cancel();
          _silenceTimer = Timer(silence, () {
            if (id == _run) speech.stopListening();
          });
        }
        onWords(w);
      },
      onDone: () {
        _timersOff();
        _listening = false;
        if (id == _run) onDone(noSpeech: !_heard);
      },
    );
    return true;
  }

  void _timersOff() {
    _silenceTimer?.cancel();
    _noSpeechTimer?.cancel();
  }

  /// Stops a pending prompt wait or listening; a later [onDone] is ignored.
  void cancel() {
    _run++;
    _timersOff();
    if (_listening) speech.stopListening();
    _listening = false;
  }
}

/// The animated "Dinliyorum" pill shown while hands-free listening runs.
class ListeningIndicator extends StatefulWidget {
  const ListeningIndicator({super.key, this.label = 'Dinliyorum'});
  final String label;

  @override
  State<ListeningIndicator> createState() => _ListeningIndicatorState();
}

class _ListeningIndicatorState extends State<ListeningIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Brand.error;
    return Semantics(
      liveRegion: true,
      label: widget.label,
      child: ExcludeSemantics(
        child: Center(
          child: Container(
            key: const Key('hands-free-listening'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
                  child: Icon(Icons.graphic_eq_rounded, color: color, size: 20),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// After [noSpeechTimeout] with no words: a gentle hint and one retry.
class NoSpeechHint extends StatelessWidget {
  const NoSpeechHint({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('hands-free-no-speech'),
    children: [
      Text(
        'Bir şey duyamadım. Hazır olduğunda tekrar dene; acele yok.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Brand.muted),
      ),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        key: const Key('hands-free-retry'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(140, 44)),
        icon: const Icon(Icons.mic_rounded),
        label: const Text('Tekrar dene'),
        onPressed: onRetry,
      ),
    ],
  );
}
