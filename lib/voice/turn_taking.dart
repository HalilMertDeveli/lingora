import 'dart:async';

import 'package:flutter/foundation.dart';

/// Who has the floor in a voice conversation.
enum TalkPhase {
  /// Nobody: waiting for a tap (push-to-talk, an error, or a long silence).
  idle,

  /// "Dinliyorum": the learner speaks.
  listening,

  /// "Düşünüyor": the learner's turn went out, the reply is on its way.
  thinking,

  /// "Konuşuyor": the partner's reply is playing.
  speaking,

  /// The learner muted the microphone (phone-call mode).
  muted,
}

/// One sentence of the partner's reply: neural audio when the server sent
/// it, otherwise the phone reads [text] aloud.
class SpokenSentence {
  const SpokenSentence(this.text, {this.audio, this.rate = 1});
  final String text;

  /// MP3 bytes (Premium neural voice), or null for the phone's own voice.
  final Uint8List? audio;

  /// Speed for the phone voice (slower for A1-A2).
  final double rate;
}

/// The speech recognizer, as the turn-taker sees it.
abstract interface class TurnListener {
  /// Starts listening. [onWords] gets the whole text heard so far, [onLevel]
  /// the loudness 0..1, and [onEnd] fires when the recognizer stops by itself
  /// (its own timeout, an error, or a final result).
  Future<void> start({
    required void Function(String words) onWords,
    required void Function(double level) onLevel,
    required void Function() onEnd,
  });

  /// Stops listening (what was heard so far is kept by the caller).
  Future<void> stop();
}

/// Plays the partner's sentences.
abstract interface class VoiceOut {
  /// Completes when [sentence] has been heard, or when [stop] cut it off.
  Future<void> play(SpokenSentence sentence);
  Future<void> stop();
}

/// Hears the learner start talking while the partner speaks (barge-in),
/// on an echo-cancelled microphone so the partner's own voice does not count.
abstract interface class BargeInDetector {
  Future<void> start(void Function() onSpeech);
  Future<void> stop();
}

/// Settings of the turn-taker (tunable in the voice settings).
class TurnConfig {
  const TurnConfig({
    this.handsFree = true,
    this.bargeIn = true,
    this.endOfTurn = const Duration(milliseconds: 1000),
    this.speechLevel = 0.35,
    this.echoTail = const Duration(milliseconds: 250),
    this.idleRestarts = 2,
  });

  /// Listen again by itself after each reply, and end the learner's turn
  /// after a pause. Off = push-to-talk: tap to speak, tap to send.
  final bool handsFree;

  /// The learner may interrupt the partner by speaking.
  final bool bargeIn;

  /// Silence after the last heard word that ends the learner's turn.
  final Duration endOfTurn;

  /// Loudness (0..1) that counts as the learner still speaking.
  final double speechLevel;

  /// Wait after the partner stops before the microphone opens, so the room's
  /// echo of the last word is not heard as the learner.
  final Duration echoTail;

  /// How often listening restarts by itself when nothing at all is said.
  final int idleRestarts;
}

/// True when [heard] is most likely the partner's own voice ([spoken])
/// picked up by the microphone: two or more words, nearly all of them from
/// what the partner just said.
bool looksLikeEcho(String heard, String spoken) {
  List<String> words(String s) =>
      RegExp(r"[a-z0-9']+").allMatches(s.toLowerCase()).map((m) => m[0]!).toList();
  final h = words(heard);
  if (h.length < 2) return false;
  final s = words(spoken).toSet();
  if (s.isEmpty) return false;
  final inside = h.where(s.contains).length;
  return inside / h.length >= 0.8;
}

/// The turn-taking state machine of the voice conversation: listening with
/// end-of-turn detection, thinking, speaking sentence by sentence, barge-in
/// and echo protection. All I/O goes through [TurnListener], [VoiceOut] and
/// [BargeInDetector]; time through [now] and [Timer], so tests drive it with
/// fake ones.
class TurnTaker extends ChangeNotifier {
  TurnTaker({
    required this.listener,
    required this.out,
    this.bargeInDetector,
    required this.onUserTurn,
    this.onBargeIn,
    this.onLatency,
    this._config = const TurnConfig(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final TurnListener listener;
  final VoiceOut out;
  final BargeInDetector? bargeInDetector;
  TurnConfig _config;

  /// The learner finished a turn: send [text] and call [addSentence] /
  /// [replyComplete] (or [replyFailed]) with the returned turn number.
  final void Function(int turn, String text) onUserTurn;

  /// The learner interrupted the reply of [turn]; [heardSentences] of it were played.
  final void Function(int turn, int heardSentences)? onBargeIn;

  /// Time from the end of the learner's speech to the first sound of the reply.
  final void Function(Duration latency)? onLatency;

  final DateTime Function() _now;

  TalkPhase _phase = TalkPhase.idle;
  String _words = '';
  Timer? _silence;
  Timer? _restart;
  DateTime? _lastActivity;
  DateTime? _endOfSpeech;
  DateTime? _speechEndedAt;
  int _emptyRestarts = 0;
  int _turn = 0;
  int? _replyTurn;
  bool _replyDone = false;
  bool _playing = false;
  int _played = 0;
  bool _detecting = false;
  bool _closed = false;
  String _lastPartner = '';
  final _queue = <SpokenSentence>[];

  TalkPhase get phase => _phase;

  /// What the learner has said so far in this turn.
  String get words => _words;
  TurnConfig get config => _config;

  set config(TurnConfig c) {
    _config = c;
    notifyListeners();
  }

  void _set(TalkPhase p) {
    if (_phase == p) return;
    _phase = p;
    notifyListeners();
  }

  // ------------------------------------------------------------ listening

  /// Opens the microphone for the learner's turn.
  Future<void> listen() async {
    if (_closed || _phase == TalkPhase.listening || _phase == TalkPhase.muted) return;
    _restart?.cancel();
    _silence?.cancel();
    _words = '';
    _lastActivity = null;
    _set(TalkPhase.listening);
    await listener.start(onWords: _onWords, onLevel: _onLevel, onEnd: _onListenerEnd);
  }

  void _onWords(String w) {
    if (_phase != TalkPhase.listening) return;
    final text = w.trim();
    if (text == _words) return;
    _words = text;
    _activity();
    notifyListeners();
  }

  void _onLevel(double level) {
    if (_phase == TalkPhase.listening && level >= _config.speechLevel && _words.isNotEmpty) _activity();
  }

  void _activity() {
    _lastActivity = _now();
    if (!_config.handsFree) return; // push-to-talk: the learner taps to send
    _silence?.cancel();
    _silence = Timer(_config.endOfTurn, _endTurn);
  }

  void _onListenerEnd() {
    if (_phase != TalkPhase.listening) return;
    if (_words.isNotEmpty) {
      _endTurn();
      return;
    }
    // Nothing said: keep the line open a little longer, then wait for a tap.
    if (_config.handsFree && _emptyRestarts < _config.idleRestarts) {
      _emptyRestarts++;
      _set(TalkPhase.idle);
      _restart = Timer(const Duration(milliseconds: 300), listen);
    } else {
      _set(TalkPhase.idle);
    }
  }

  /// The learner's turn is over: hand it to [onUserTurn].
  void _endTurn() {
    _silence?.cancel();
    if (_phase != TalkPhase.listening || _words.isEmpty) return;
    final text = _words;
    // The partner's voice coming back through the speaker is not the learner.
    final sinceSpeech = _speechEndedAt == null ? null : _now().difference(_speechEndedAt!);
    if (sinceSpeech != null &&
        sinceSpeech < const Duration(seconds: 3) &&
        looksLikeEcho(text, _lastPartner)) {
      _words = '';
      _phase = TalkPhase.idle;
      unawaited(listener.stop());
      _restart = Timer(_config.echoTail, listen);
      notifyListeners();
      return;
    }
    _endOfSpeech = _lastActivity ?? _now();
    _emptyRestarts = 0;
    _turn++;
    _replyTurn = _turn;
    _replyDone = false;
    _played = 0;
    _queue.clear();
    _set(TalkPhase.thinking);
    unawaited(listener.stop());
    onUserTurn(_turn, text);
  }

  /// A typed turn (the text fallback): sent like a spoken one, no echo check.
  Future<void> submitText(String text) async {
    final t = text.trim();
    if (t.isEmpty || _closed || _phase == TalkPhase.thinking || _phase == TalkPhase.speaking) return;
    _restart?.cancel();
    if (_phase == TalkPhase.listening) await listener.stop();
    _speechEndedAt = null;
    _phase = TalkPhase.listening;
    _words = t;
    _lastActivity = _now();
    _endTurn();
  }

  /// Mic button: start listening, or (while listening) send what was said;
  /// while the partner speaks, interrupt.
  Future<void> tapMic() async {
    switch (_phase) {
      case TalkPhase.idle:
        _emptyRestarts = 0;
        await listen();
      case TalkPhase.listening:
        if (_words.isEmpty) {
          _silence?.cancel();
          _set(TalkPhase.idle);
          await listener.stop();
        } else {
          _endTurn();
        }
      case TalkPhase.speaking:
        await _interrupt();
      case TalkPhase.thinking || TalkPhase.muted:
        break;
    }
  }

  // ------------------------------------------------------------- speaking

  /// One sentence of the reply to [turn]; stale or interrupted replies are dropped.
  void addSentence(int turn, SpokenSentence s) {
    if (_closed || turn != _replyTurn) return;
    _lastPartner = '$_lastPartner ${s.text}'.trim();
    if (_phase == TalkPhase.thinking) {
      _lastPartner = s.text;
      final end = _endOfSpeech;
      if (end != null) onLatency?.call(_now().difference(end));
      _set(TalkPhase.speaking);
    }
    _queue.add(s);
    unawaited(_pump());
  }

  /// The reply to [turn] is complete.
  void replyComplete(int turn) {
    if (turn != _replyTurn) return;
    _replyDone = true;
    if (!_playing && _queue.isEmpty) _afterSpeaking();
  }

  /// The reply to [turn] failed: back to idle (the screen shows the error).
  void replyFailed(int turn) {
    if (turn != _replyTurn) return;
    _replyTurn = null;
    _queue.clear();
    unawaited(_stopDetector());
    _set(_mutedPending ? TalkPhase.muted : TalkPhase.idle);
    _mutedPending = false;
  }

  /// Plays an opening line (or a replayed sentence) outside a reply.
  void say(SpokenSentence s) {
    _turn++;
    _replyTurn = _turn;
    _replyDone = false;
    _played = 0;
    _endOfSpeech = null;
    _set(TalkPhase.thinking);
    addSentence(_turn, s);
    replyComplete(_turn);
  }

  Future<void> _pump() async {
    if (_playing || _queue.isEmpty) return;
    final turn = _replyTurn;
    _playing = true;
    if (_config.bargeIn && !_detecting && bargeInDetector != null) {
      _detecting = true;
      unawaited(bargeInDetector!.start(_onBargeIn));
    }
    final s = _queue.removeAt(0);
    await out.play(s);
    _playing = false;
    if (turn != _replyTurn || _closed) return; // interrupted meanwhile
    _played++;
    if (_queue.isNotEmpty) {
      unawaited(_pump());
    } else if (_replyDone) {
      _afterSpeaking();
    }
  }

  void _afterSpeaking() {
    unawaited(_stopDetector());
    _speechEndedAt = _now();
    _replyTurn = null;
    if (_mutedPending) {
      _mutedPending = false;
      _set(TalkPhase.muted);
      return;
    }
    _set(TalkPhase.idle);
    if (_config.handsFree && !_closed) _restart = Timer(_config.echoTail, listen);
  }

  void _onBargeIn() {
    if (_phase == TalkPhase.speaking) unawaited(_interrupt());
  }

  Future<void> _interrupt() async {
    final turn = _replyTurn;
    _replyTurn = null; // the rest of this reply is not played
    _queue.clear();
    await _stopDetector();
    await out.stop();
    _speechEndedAt = _now();
    if (turn != null) onBargeIn?.call(turn, _played);
    _set(TalkPhase.idle);
    await listen();
  }

  Future<void> _stopDetector() async {
    if (!_detecting) return;
    _detecting = false;
    await bargeInDetector?.stop();
  }

  // ---------------------------------------------------------------- mute

  /// Phone-call mute: the microphone stays closed until unmuted.
  Future<void> setMuted(bool muted) async {
    if (muted) {
      if (_phase == TalkPhase.muted) return;
      _silence?.cancel();
      _restart?.cancel();
      final wasListening = _phase == TalkPhase.listening;
      if (_phase == TalkPhase.listening || _phase == TalkPhase.idle) _set(TalkPhase.muted);
      _mutedPending = !wasListening && _phase != TalkPhase.muted;
      if (wasListening) await listener.stop();
    } else {
      _mutedPending = false;
      if (_phase != TalkPhase.muted) return;
      _set(TalkPhase.idle);
      if (_config.handsFree) await listen();
    }
  }

  bool _mutedPending = false;
  bool get muted => _phase == TalkPhase.muted || _mutedPending;

  /// Stops everything (leaving the screen, hanging up).
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _silence?.cancel();
    _restart?.cancel();
    _queue.clear();
    _replyTurn = null;
    await _stopDetector();
    await out.stop();
    if (_phase == TalkPhase.listening) await listener.stop();
    _phase = TalkPhase.idle;
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
