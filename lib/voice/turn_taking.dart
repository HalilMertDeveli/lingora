import 'dart:async';

import 'package:flutter/foundation.dart';

/// Who has the floor in a voice conversation.
enum TalkPhase {
  /// Nobody: between turns, after an error, or after a long silence (then
  /// the learner may type, or hear the partner's last line again).
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
  const SpokenSentence(this.text, {this.audio, this.rate = 1, this.ack = false});
  final String text;

  /// MP3 bytes (Premium neural voice), or null for the phone's own voice.
  final Uint8List? audio;

  /// Speed for the phone voice (slower for A1-A2).
  final double rate;

  /// A short backchannel ("Mm-hm.") played while the real reply is on its way.
  final bool ack;
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

/// How long "Şunu mu dedin?" shows a recognised utterance before it is sent
/// by itself in the free voice conversation. Far-field room speech (other
/// people talking) is recognised as loud and confident as the learner
/// (Galaxy M22: rmsdB 7-10, confidence 0.92), so the learner gets a moment
/// to cancel it. Lesson speaking exercises do not use it.
const utteranceConfirmDelay = Duration(seconds: 2);

/// Settings of the turn-taker (tunable in the voice settings).
class TurnConfig {
  const TurnConfig({
    this.bargeIn = true,
    this.endOfTurn = const Duration(milliseconds: 700),
    this.unfinishedExtra = const Duration(milliseconds: 500),
    this.ackDelay = const Duration(milliseconds: 300),
    this.speechLevel = 0.35,
    this.echoTail = const Duration(milliseconds: 100),
    this.idleRestarts = 2,
    this.confirmDelay = Duration.zero,
  });

  /// The learner may interrupt the partner by speaking.
  final bool bargeIn;

  /// Silence after the last heard word that ends the learner's turn.
  final Duration endOfTurn;

  /// Extra wait when the learner stopped on a word that needs more after it
  /// ("and", "because", "the", "um"…): they are probably still thinking.
  final Duration unfinishedExtra;

  /// A backchannel plays this long after the learner's turn if the reply has
  /// not started yet.
  final Duration ackDelay;

  /// Loudness (0..1) that counts as the learner still speaking.
  final double speechLevel;

  /// Wait after the partner stops before the microphone opens, so the room's
  /// echo of the last word is not heard as the learner. The player reports
  /// the end only after the recording's own closing silence, so a short wait
  /// is enough: 250 ms here plus the barge-in microphone's stop made the
  /// learner's turn start about 0.6 s after the partner (QA, Galaxy M22).
  final Duration echoTail;

  /// How often listening restarts by itself when nothing at all is said.
  final int idleRestarts;

  /// A spoken turn waits this long as [TurnTaker.pending] ("Şunu mu
  /// dedin?") before it is sent; zero sends at once. Typed turns never wait.
  final Duration confirmDelay;
}

const _unfinishedWords = {
  'and',
  'but',
  'or',
  'so',
  'because',
  'the',
  'a',
  'an',
  'to',
  'of',
  'with',
  'my',
  'your',
  'i',
  'um',
  'uh',
  'er',
  'erm',
  'if',
  'when',
  'that',
  'is',
  'are',
  'was',
  'were',
  'in',
  'on',
  'at',
  'for',
  'about',
  'then',
  'very',
  'like',
  'want',
  'think',
  'will',
  'can',
  'some',
};

/// True when [words] stop on a word that usually has more after it.
bool soundsUnfinished(String words) {
  final last = RegExp(r"[a-z']+").allMatches(words.toLowerCase()).lastOrNull?[0];
  return last != null && _unfinishedWords.contains(last);
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
    this.onFirstSentence,
    this.pickAck,
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

  /// Time from the end of the learner's speech to the first sentence of the
  /// real reply (not counting a backchannel).
  final void Function(Duration latency)? onFirstSentence;

  /// A backchannel in the partner's voice ("Mm-hm."), or null for none.
  final SpokenSentence? Function()? pickAck;

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
  bool _gotReal = false;
  Timer? _ack;
  String? _pending;
  Timer? _confirm;
  int _pendingSerial = 0;
  String _lastPartner = '';
  final _queue = <SpokenSentence>[];

  TalkPhase get phase => _phase;

  /// What the learner has said so far in this turn.
  String get words => _words;
  TurnConfig get config => _config;

  /// A spoken turn waiting for "Şunu mu dedin?": sent by itself after
  /// [TurnConfig.confirmDelay] ([confirmPending] sends it now, [cancelPending]
  /// drops it). The microphone stays open meanwhile; a new utterance
  /// replaces it and starts the countdown again.
  String? get pending => _pending;

  /// Changes whenever [pending] gets a new text (restarts the countdown).
  int get pendingSerial => _pendingSerial;

  /// The countdown runs (it pauses while new words come in).
  bool get pendingCounting => _confirm?.isActive ?? false;

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
    // Someone speaks again while "Şunu mu dedin?" waits: nothing is sent
    // until this new utterance ends (then it replaces the waiting one).
    if (_pending != null && text.isNotEmpty) _confirm?.cancel();
    _activity();
    notifyListeners();
  }

  void _onLevel(double level) {
    if (_phase == TalkPhase.listening && level >= _config.speechLevel && _words.isNotEmpty) _activity();
  }

  void _activity() {
    _lastActivity = _now();
    _silence?.cancel();
    final extra = soundsUnfinished(_words) ? _config.unfinishedExtra : Duration.zero;
    _silence = Timer(_config.endOfTurn + extra, _endTurn);
  }

  void _onListenerEnd() {
    if (_phase != TalkPhase.listening) return;
    if (_words.isNotEmpty) {
      _endTurn();
      return;
    }
    if (_pending != null) {
      // The recognizer stopped by itself while "Şunu mu dedin?" waits: keep
      // listening hands-free (a new utterance may replace the waiting one).
      _restart?.cancel();
      _restart = Timer(const Duration(milliseconds: 300), _reopen);
      return;
    }
    // Nothing said: keep the line open a little longer, then offer typing.
    if (_emptyRestarts < _config.idleRestarts) {
      _emptyRestarts++;
      _set(TalkPhase.idle);
      _restart = Timer(const Duration(milliseconds: 300), listen);
    } else {
      _set(TalkPhase.idle);
    }
  }

  /// The learner's turn is over: hand it to [onUserTurn] (a spoken one
  /// waits as [pending] first when [TurnConfig.confirmDelay] is set).
  void _endTurn({bool typed = false}) {
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
    if (!typed && _config.confirmDelay > Duration.zero) {
      _hold(text);
      return;
    }
    _endOfSpeech = _lastActivity ?? _now();
    _send(text);
  }

  /// "Şunu mu dedin?": [text] waits, the microphone listens on.
  void _hold(String text) {
    _pending = text;
    _pendingSerial++;
    _words = '';
    _lastActivity = null;
    _emptyRestarts = 0;
    _restart?.cancel();
    _confirm?.cancel();
    _confirm = Timer(_config.confirmDelay, confirmPending);
    notifyListeners();
    // The recognizer usually stops after a final result: open it again.
    unawaited(listener.stop().then((_) => _reopen()));
  }

  /// Starts the recognizer again inside the same listening phase.
  Future<void> _reopen() async {
    if (_closed || _phase != TalkPhase.listening || _pending == null) return;
    await listener.start(onWords: _onWords, onLevel: _onLevel, onEnd: _onListenerEnd);
  }

  /// Sends the waiting utterance now (the learner tapped it, or the
  /// countdown ran out). Words heard since then replace it: the strip
  /// shows them, and a tap sends what is shown.
  void confirmPending() {
    if (_pending == null || _closed || _phase != TalkPhase.listening) return;
    final text = _words.isNotEmpty ? _words : _pending!;
    _clearPending();
    _restart?.cancel();
    _silence?.cancel();
    _words = '';
    _endOfSpeech = _now();
    _send(text);
  }

  /// "İptal": the waiting utterance is dropped and listening goes on.
  Future<void> cancelPending() async {
    if (_pending == null) return;
    _clearPending();
    notifyListeners();
    if (_phase == TalkPhase.idle) await resume();
  }

  void _clearPending() {
    _confirm?.cancel();
    _confirm = null;
    _pending = null;
  }

  void _send(String text) {
    _emptyRestarts = 0;
    _turn++;
    _replyTurn = _turn;
    _replyDone = false;
    _played = 0;
    _queue.clear();
    _set(TalkPhase.thinking);
    unawaited(listener.stop());
    _gotReal = false;
    onUserTurn(_turn, text);
    _ack?.cancel();
    if (pickAck != null) _ack = Timer(_config.ackDelay, _playAck);
  }

  /// A typed turn (the text fallback): sent like a spoken one, no echo check.
  /// While the partner speaks it is cut off first (like barge-in). False
  /// when nothing was sent (empty, closed, or the reply is still on its
  /// way): the screen keeps the text then.
  Future<bool> submitText(String text) async {
    final t = text.trim();
    if (t.isEmpty || _closed || _phase == TalkPhase.thinking) return false;
    // Only a backchannel plays: the real reply is still on its way.
    if (_phase == TalkPhase.speaking && !_gotReal) return false;
    if (_phase == TalkPhase.speaking) await _interrupt(listenAfter: false);
    if (_closed || _phase == TalkPhase.thinking) return false;
    _restart?.cancel();
    _clearPending(); // the typed text answers instead
    if (_phase == TalkPhase.listening) await listener.stop();
    _speechEndedAt = null;
    _phase = TalkPhase.listening;
    _words = t;
    _lastActivity = _now();
    _endTurn(typed: true);
    return true;
  }

  /// Nothing was heard after the automatic restarts: the screen offers
  /// typing (or hearing the partner's last line again).
  bool get gaveUp => _phase == TalkPhase.idle && _emptyRestarts >= _config.idleRestarts && _replyTurn == null;

  /// Listening again after a pause (back from typing, the permission was
  /// granted, the app came back): no button needed.
  Future<void> resume() async {
    if (_closed || _phase != TalkPhase.idle) return;
    _emptyRestarts = 0;
    await listen();
  }

  /// "Sözünü kes": stops the partner and listens.
  Future<void> interrupt() async {
    if (_phase == TalkPhase.speaking) await _interrupt();
  }

  // ------------------------------------------------------------- speaking

  /// One sentence of the reply to [turn]; stale or interrupted replies are dropped.
  void addSentence(int turn, SpokenSentence s) {
    if (_closed || turn != _replyTurn) return;
    _lastPartner = '$_lastPartner ${s.text}'.trim();
    if (!_gotReal) {
      _gotReal = true;
      _ack?.cancel();
      final end = _endOfSpeech;
      if (end != null) onFirstSentence?.call(_now().difference(end));
    }
    if (_phase == TalkPhase.thinking) {
      _lastPartner = s.text;
      final end = _endOfSpeech;
      if (end != null) onLatency?.call(_now().difference(end));
      _set(TalkPhase.speaking);
    }
    _queue.add(s);
    unawaited(_pump());
  }

  /// The reply is late: a short backchannel fills the gap, as people do.
  void _playAck() {
    if (_closed || _phase != TalkPhase.thinking || _gotReal || _queue.isNotEmpty || _playing) return;
    final s = pickAck?.call();
    if (s == null) return;
    final end = _endOfSpeech;
    if (end != null) onLatency?.call(_now().difference(end));
    _set(TalkPhase.speaking);
    _queue.add(SpokenSentence(s.text, audio: s.audio, rate: s.rate, ack: true));
    unawaited(_pump());
  }

  /// The reply to [turn] is complete.
  void replyComplete(int turn) {
    if (turn != _replyTurn) return;
    _replyDone = true;
    if (!_playing && _queue.isEmpty) unawaited(_afterSpeaking());
  }

  /// The reply to [turn] failed: back to idle (the screen shows the error).
  void replyFailed(int turn) {
    if (turn != _replyTurn) return;
    _ack?.cancel();
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
    _gotReal = true; // nothing to acknowledge
    _ack?.cancel();
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
    if (!s.ack) _played++;
    if (_queue.isNotEmpty) {
      unawaited(_pump());
    } else if (_replyDone) {
      unawaited(_afterSpeaking());
    }
  }

  Future<void> _afterSpeaking() async {
    _speechEndedAt = _now();
    _replyTurn = null;
    _emptyRestarts = 0;
    if (_mutedPending) {
      _mutedPending = false;
      unawaited(_stopDetector());
      _set(TalkPhase.muted);
      return;
    }
    _set(TalkPhase.idle);
    // The barge-in recorder must have let go of the microphone before the
    // phone's recognizer starts (Samsung: error_audio / error_client). It
    // stops during the echo tail instead of before it.
    final released = _stopDetector();
    final tail = Completer<void>();
    _restart = Timer(_config.echoTail, tail.complete);
    await Future.wait([released, tail.future]);
    if (!_closed && _phase == TalkPhase.idle && _replyTurn == null) unawaited(listen());
  }

  void _onBargeIn() {
    if (_phase == TalkPhase.speaking) unawaited(_interrupt());
  }

  Future<void> _interrupt({bool listenAfter = true}) async {
    _ack?.cancel();
    final turn = _replyTurn;
    _replyTurn = null; // the rest of this reply is not played
    _queue.clear();
    await _stopDetector();
    await out.stop();
    _speechEndedAt = _now();
    if (turn != null) onBargeIn?.call(turn, _played);
    _set(TalkPhase.idle);
    if (listenAfter) await listen();
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
      _clearPending();
      final wasListening = _phase == TalkPhase.listening;
      if (_phase == TalkPhase.listening || _phase == TalkPhase.idle) _set(TalkPhase.muted);
      _mutedPending = !wasListening && _phase != TalkPhase.muted;
      if (wasListening) await listener.stop();
    } else {
      _mutedPending = false;
      if (_phase != TalkPhase.muted) return;
      _set(TalkPhase.idle);
      _emptyRestarts = 0;
      await listen();
    }
  }

  bool _mutedPending = false;
  bool get muted => _phase == TalkPhase.muted || _mutedPending;

  /// Stops everything (leaving the screen, hanging up).
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _ack?.cancel();
    _clearPending();
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
