import 'dart:async';

import 'package:flutter/material.dart';

import '../services/mic_access.dart';
import '../services/speech.dart';
import '../theme.dart';

/// Eller serbest konuşma, the only way to speak in the app (free and
/// Premium): there is no microphone button. When it is the learner's turn
/// (after the prompt has finished playing, so the phone does not hear
/// itself) the microphone opens by itself; the turn ends shortly after the
/// learner stops talking and the answer is checked. When nothing is heard
/// (or the recognizer fails) it listens again by itself a few times with a
/// short hint, then offers "Yazarak cevapla" and the skip.

/// Silence after the last recognized word that ends the turn. Tunable: the
/// recognizer's final result still arrives after it (see `stopListening`).
const endOfSpeechSilence = Duration(milliseconds: 1000);

/// How long to wait for the first word before giving up on this try.
const noSpeechTimeout = Duration(seconds: 7);

/// Automatic new tries after nothing was heard, before the fallbacks.
const autoRetries = 2;

/// Pause before an automatic new try, long enough to read the hint.
const autoRetryPause = Duration(milliseconds: 1200);

enum ListenPhase {
  /// Not listening (before the first turn, after an answer, or stopped).
  idle,

  /// The system permission dialog is open.
  asking,

  /// The permission was refused; asking again is still possible.
  denied,

  /// The permission was refused for good: only the settings can help.
  blocked,

  /// The prompt plays; the microphone opens when it ends.
  prompting,

  /// The microphone is open.
  listening,

  /// Nothing was heard: a hint, then listening again by itself.
  retrying,

  /// Nothing was heard after the new tries: type or skip.
  gaveUp,

  /// No recognizer on this phone (or no English pack).
  unavailable,
}

/// One speaking screen's hands-free microphone. The owner calls [start]
/// whenever it is the learner's turn, [cancel] when leaving or typing, and
/// [dispose] at the end.
class AutoListen extends ChangeNotifier {
  AutoListen({
    required this.speech,
    required this.player,
    required this.mic,
    this.silence = endOfSpeechSilence,
    this.noSpeech = noSpeechTimeout,
    this.retries = autoRetries,
    this.retryPause = autoRetryPause,
  }) {
    // Back from the phone's settings (or the permission dialog): try again.
    _life = AppLifecycleListener(onResume: _resumed);
  }

  final SpeechService speech;
  final LinePlayer player;
  final MicAccess mic;
  final Duration silence;
  final Duration noSpeech;
  final int retries;
  final Duration retryPause;
  late final AppLifecycleListener _life;

  ListenPhase _phase = ListenPhase.idle;
  ListenPhase get phase => _phase;

  /// What was heard in this try so far.
  String words = '';

  /// Automatic new tries used for this turn.
  int tries = 0;

  /// The recognizer problem behind the last missed try, if any.
  String? issue;

  bool get listening => _phase == ListenPhase.listening;

  String? _target;
  String? _prompt;
  double _rate = 1;
  void Function(String words)? _onHeard;
  int _run = 0;
  bool _heard = false;
  bool _open = false;
  bool _disposed = false;
  Timer? _silenceTimer;
  Timer? _noSpeechTimer;
  Timer? _retryTimer;

  void _set(ListenPhase p) {
    if (_disposed) return;
    _phase = p;
    notifyListeners();
  }

  /// The learner's turn: plays [prompt] (if any) to its end, then listens
  /// for [target] (null = free speech) and hands what was heard to
  /// [onHeard]. Asks for the microphone permission first when needed.
  Future<void> start({
    String? target,
    String? prompt,
    double promptRate = 1,
    required void Function(String words) onHeard,
  }) {
    _target = target;
    _prompt = prompt;
    _rate = promptRate;
    _onHeard = onHeard;
    tries = 0;
    return _go(withPrompt: true);
  }

  /// The same turn again (after "Tekrar dinle", or a try that missed words).
  Future<void> again({bool withPrompt = true}) {
    if (_onHeard == null) return Future.value();
    tries = 0;
    return _go(withPrompt: withPrompt);
  }

  /// Asks for the microphone permission now (a screen that listens later),
  /// so the dialog does not interrupt the learner's turn.
  Future<void> prepare() async {
    final id = ++_run;
    if (await _permitted(id) && id == _run) _set(ListenPhase.idle);
  }

  Future<void> _go({required bool withPrompt}) async {
    final id = ++_run;
    _stopNow();
    words = '';
    issue = null;
    if (!await _permitted(id)) return;
    final prompt = _prompt;
    if (withPrompt && prompt != null) {
      _set(ListenPhase.prompting);
      await player.sayBeforeListening(prompt, rate: _rate);
      if (id != _run) return;
    }
    await _listen(id);
  }

  Future<bool> _permitted(int id) async {
    var s = await mic.status();
    if (id != _run) return false;
    if (s == MicStatus.denied) {
      _set(ListenPhase.asking);
      s = await mic.request();
      if (id != _run) return false;
    }
    if (s == MicStatus.granted) return true;
    _set(s == MicStatus.blocked ? ListenPhase.blocked : ListenPhase.denied);
    return false;
  }

  Future<void> _listen(int id) async {
    if (!await speech.canListen) {
      if (id != _run) return;
      issue = speechIssue.value;
      _set(issue == SpeechIssues.noMicPermission ? ListenPhase.denied : ListenPhase.unavailable);
      return;
    }
    if (id != _run) return;
    _heard = false;
    words = '';
    _open = true;
    _set(ListenPhase.listening);
    _noSpeechTimer = Timer(noSpeech, () {
      if (!_heard && id == _run) speech.stopListening();
    });
    void onWords(String w) {
      if (id != _run) return;
      words = w;
      if (w.trim().isNotEmpty) {
        _heard = true;
        _noSpeechTimer?.cancel();
        _silenceTimer?.cancel();
        _silenceTimer = Timer(silence, () {
          if (id == _run) speech.stopListening();
        });
      }
      if (!_disposed) notifyListeners();
    }

    void onDone() {
      _timersOff();
      _open = false;
      if (id != _run) return;
      if (_heard && words.trim().isNotEmpty) {
        _set(ListenPhase.idle);
        _onHeard?.call(words);
      } else {
        _missed(id);
      }
    }

    final target = _target;
    if (target == null) {
      await speech.listen(onWords: onWords, onDone: onDone);
    } else {
      await speech.listenTo(target, onWords: onWords, onDone: onDone);
    }
  }

  /// Nothing heard (silence, or a recognizer error): listen again by itself
  /// a few times; a missing permission or recognizer stops at once.
  void _missed(int id) {
    issue = speechIssue.value;
    if (issue == SpeechIssues.noMicPermission) {
      _set(ListenPhase.denied);
      return;
    }
    if (issue == SpeechIssues.noRecognizer || issue == SpeechIssues.noEnglishRecognizer) {
      _set(ListenPhase.unavailable);
      return;
    }
    if (tries >= retries) {
      _set(ListenPhase.gaveUp);
      return;
    }
    tries++;
    _set(ListenPhase.retrying);
    _retryTimer = Timer(retryPause, () {
      if (id == _run) _listen(id);
    });
  }

  void _resumed() {
    if (_phase == ListenPhase.blocked || _phase == ListenPhase.denied) {
      if (_onHeard == null) {
        prepare();
      } else {
        again(withPrompt: false);
      }
    }
  }

  void _timersOff() {
    _silenceTimer?.cancel();
    _noSpeechTimer?.cancel();
    _retryTimer?.cancel();
  }

  void _stopNow() {
    _timersOff();
    if (_open) {
      _open = false;
      speech.stopListening();
    }
  }

  /// Stops a pending prompt wait, a retry or listening; a later result is
  /// ignored.
  void cancel() {
    _run++;
    _stopNow();
    if (_phase != ListenPhase.idle) _set(ListenPhase.idle);
  }

  @override
  void dispose() {
    _run++;
    _stopNow();
    _disposed = true;
    _life.dispose();
    super.dispose();
  }
}

/// What the hands-free microphone is doing, under the prompt: the animated
/// "Dinliyorum" pill with the voice level while it listens, a short hint
/// while it tries again, the permission notice, and after the new tries a
/// way to hear the sentence again. Never a button that starts listening.
class AutoListenStatus extends StatelessWidget {
  const AutoListenStatus({super.key, required this.listen, this.showWords = true, this.again = true});
  final AutoListen listen;

  /// Show the words heard so far under the pill.
  final bool showWords;

  /// After the new tries, offer to hear the prompt again (which then
  /// listens by itself).
  final bool again;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: listen,
    builder: (context, _) {
      final muted = TextStyle(color: Brand.muted);
      Widget note(String key, String text, {Widget? action}) => Column(
        key: Key(key),
        children: [
          Text(text, textAlign: TextAlign.center, style: muted),
          if (action != null) ...[const SizedBox(height: 6), action],
        ],
      );
      return switch (listen.phase) {
        ListenPhase.idle => const SizedBox.shrink(),
        ListenPhase.asking => note(
          'mic-asking',
          'Seni duyabilmem için mikrofon izni gerekiyor. Açılan pencerede izin ver.',
        ),
        ListenPhase.denied => note(
          'mic-denied',
          'Konuşma alıştırmaları için mikrofon izni gerekiyor. İzin verince kendiliğinden dinlerim.',
          action: FilledButton.tonal(
            key: const Key('mic-allow'),
            onPressed: () => listen._onHeard == null ? listen.prepare() : listen.again(withPrompt: false),
            child: const Text('Mikrofona izin ver'),
          ),
        ),
        ListenPhase.blocked => note(
          'mic-blocked',
          'Mikrofon izni kapalı. Ayarlar > İzinler > Mikrofon bölümünden aç; dönünce kendiliğinden '
              'dinlemeye başlarım. İstersen yazarak da devam edebilirsin.',
          action: FilledButton.tonal(
            key: const Key('mic-settings'),
            onPressed: listen.mic.openSettings,
            child: const Text('Ayarları aç'),
          ),
        ),
        ListenPhase.prompting => note(
          'auto-listen-prompting',
          'Önce dinle; bitince mikrofon kendiliğinden açılır.',
        ),
        ListenPhase.listening => Column(
          children: [
            const ListeningIndicator(),
            if (showWords && listen.words.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '“${listen.words.trim()}”',
                key: const Key('auto-listen-words'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Brand.ink, fontSize: 16),
              ),
            ],
          ],
        ),
        ListenPhase.retrying => note(
          'hands-free-no-speech',
          '${_missedText(listen.issue)} Tekrar dinliyorum, şimdi söyle.',
        ),
        ListenPhase.gaveUp => note(
          'auto-listen-gave-up',
          'Şu an seni duyamıyorum. Yazarak cevap verebilir ya da bu soruyu geçebilirsin.',
          action: again
              ? TextButton.icon(
                  key: const Key('auto-listen-again'),
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Tekrar dinle ve söyle'),
                  onPressed: listen.again,
                )
              : null,
        ),
        ListenPhase.unavailable => note('auto-listen-unavailable', listen.issue ?? SpeechIssues.noRecognizer),
      };
    },
  );

  static String _missedText(String? issue) =>
      issue == null || issue == SpeechIssues.notHeard ? 'Bir şey duyamadım.' : issue;
}

/// The animated "Dinliyorum" pill shown while the microphone is open; it
/// grows with the voice, so the learner sees they are being heard.
class ListeningIndicator extends StatefulWidget {
  const ListeningIndicator({super.key, this.label = 'Dinliyorum', this.color});
  final String label;
  final Color? color;

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
    final color = widget.color ?? Brand.error;
    return Semantics(
      liveRegion: true,
      label: widget.label,
      child: ExcludeSemantics(
        child: Center(
          child: ValueListenableBuilder<double>(
            valueListenable: speechLevel,
            builder: (context, level, child) => AnimatedContainer(
              key: const Key('hands-free-listening'),
              duration: const Duration(milliseconds: 120),
              padding: EdgeInsets.symmetric(horizontal: 14 + 6 * level, vertical: 8 + 3 * level),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1 + 0.15 * level),
                borderRadius: BorderRadius.circular(24),
              ),
              child: child,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  key: const Key('mic-level'),
                  opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
                  child: Icon(Icons.graphic_eq_rounded, color: color, size: 22),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.label,
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// After a try: hear the prompt again; the microphone then opens by itself.
class SayAgainButton extends StatelessWidget {
  const SayAgainButton({super.key, required this.onPressed, this.label = 'Tekrar dinle ve söyle'});
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton.icon(
      key: const Key('say-again'),
      icon: const Icon(Icons.replay_rounded),
      label: Text(label),
      onPressed: onPressed,
    ),
  );
}
