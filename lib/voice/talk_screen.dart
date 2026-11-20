import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/speech_evidence.dart';
import '../core/tr_errors.dart';
import '../data/app_settings.dart';
import '../data/level_report.dart';
import '../data/progress.dart';
import '../data/scenarios.dart';
import '../goals/learn_goal.dart';
import '../screens/conversation_report_screen.dart';
import '../screens/paywall_screen.dart';
import '../services/billing/premium.dart';
import '../services/conversation.dart';
import '../services/mic_access.dart';
import '../services/speech.dart';
import '../theme.dart';
import '../ui/motion.dart';
import 'ack_picker.dart';
import 'talk_service.dart';
import 'turn_taking.dart';
import 'voice_catalog.dart';
import 'voice_io.dart';
import 'voice_settings.dart';

const talkXp = 15;

/// Paywall line when the free daily taste of the voice chat is used up.
const talkFreeTastePitch =
    "Özel hoca saati 500 TL. Çenebaz Premium'da gerçek bir insan gibi konuşan sesli partnerin her gün yanında.";

/// The parts a voice chat needs from the phone; tests replace them.
class TalkIo {
  const TalkIo({required this.listener, required this.out, this.bargeIn, this.setEarpiece});
  final TurnListener listener;
  final VoiceOut out;
  final BargeInDetector? bargeIn;

  /// Earpiece (true) or loudspeaker (false), phone-call mode.
  final Future<void> Function(bool earpiece)? setEarpiece;
}

/// Builds the phone's speech parts for a chat (overridden in tests).
final talkIoProvider = Provider<TalkIo Function({required bool call, required bool bargeIn})>((ref) {
  final speech = ref.watch(speechProvider);
  final lines = ref.watch(linePlayerProvider);
  return ({required bool call, required bool bargeIn}) {
    final out = AudioVoiceOut(
      lines,
      earpiece: call,
      communication: bargeIn || call,
      phoneVoiceFile: (text, rate) => speech.lineFile(text, rate: rate),
    );
    return TalkIo(
      listener: SpeechTurnListener(speech),
      out: out,
      bargeIn: bargeIn ? RecordBargeIn() : null,
      setEarpiece: (earpiece) => out.setRoute(earpiece: earpiece),
    );
  };
});

/// Opens the natural voice chat for [scenario] (a role-play, free talk or a
/// character, see voice_catalog.dart); [call] opens it as a phone call.
/// Reusable entry point (daily "Emma seni arıyor" call, trial taste).
Future<void> openTalk(BuildContext context, WidgetRef ref, Scenario scenario, {bool call = false}) async {
  if (call && !ref.read(premiumProvider)) {
    final gate = await requirePremium(context, ref, PremiumFeature.aiConversation, pitch: talkFreeTastePitch);
    if (gate != GateResult.premium || !context.mounted) return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => TalkScreen(scenario: scenario, call: call),
    ),
  );
}

/// A character phones the learner (phone-call mode).
Future<void> openCharacterCall(BuildContext context, WidgetRef ref, [String characterId = dailyCaller]) {
  final c = characterById(characterId) ?? characters.first;
  return openTalk(context, ref, characterScenario(c, call: true), call: true);
}

/// The CEFR level the partner should speak at: the learner's choice, else
/// the latest level karne, else unknown (the server picks).
String? talkLevel(WidgetRef ref) {
  final chosen = ref.read(voiceSettingsProvider).level;
  if (chosen != null) return chosen;
  final reports = sortedReports(ref.read(progressProvider).levelReports);
  return reports.lastOrNull?.overall?.code;
}

/// Speed of the phone's voice for a level: slower for beginners.
double deviceRateFor(String? level) => level == 'A1' ? 0.85 : (level == 'A2' ? 0.92 : 1);

/// Doğal konuşma: talk with a partner like on a real call. Hands-free turns
/// (or push-to-talk), sentence-by-sentence neural voice, barge-in, silent
/// corrections collected for the karne. [call] = audio-only phone-call
/// screen; the transcript and the karne come after hanging up.
class TalkScreen extends ConsumerStatefulWidget {
  const TalkScreen({super.key, required this.scenario, this.call = false});
  final Scenario scenario;
  final bool call;

  @override
  ConsumerState<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends ConsumerState<TalkScreen> {
  late final TalkService _service = ref.read(talkServiceProvider);
  late final VoiceSettings _settings = ref.read(voiceSettingsProvider);
  late final bool _premium = ref.read(premiumProvider);
  late final String? _level = talkLevel(ref);
  late final Character? _character = characterById(widget.scenario.apiFields?['characterId'] as String?);
  late final TalkIo _io;
  late final TurnTaker _turns;
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _messages = <ChatMessage>[];
  final _latencies = <int>[];
  final _firstSentence = <int>[];
  late final AckPicker _acks = AckPicker(backchannelsFor(_character));

  /// The partner's reply being streamed (index in [_messages]).
  int? _replyIndex;
  StreamSubscription<TalkEvent>? _stream;
  String? _error;

  /// The microphone permission is missing: the error offers to fix it
  /// (asking again, or the settings when it was refused for good).
  MicStatus? _micProblem;
  late final AppLifecycleListener _life = AppLifecycleListener(onResume: _resumed);
  bool _typing = false;
  bool _done = false;
  bool _finished = false;
  bool _earpiece = true;
  bool _muted = false;
  int? _freeLeft;
  final _callClock = Stopwatch();
  Timer? _tick;

  String? get _voice => _settings.voiceFor(_character);
  double get _rate => deviceRateFor(_level);

  @override
  void initState() {
    super.initState();
    _io = ref.read(talkIoProvider)(call: widget.call, bargeIn: _premium && _settings.bargeIn);
    _turns = TurnTaker(
      listener: _io.listener,
      out: _io.out,
      bargeInDetector: _io.bargeIn,
      config: _settings.turnConfig,
      onUserTurn: _onUserTurn,
      onBargeIn: _onBargeIn,
      onLatency: _onLatency,
      onFirstSentence: (d) {
        _firstSentence.add(d.inMilliseconds);
        debugPrint('[talk-latency] end-of-speech→first-real-sentence ${d.inMilliseconds} ms');
      },
      pickAck: () => _acks.pick(rate: _rate),
    )..addListener(_changed);
    _earpiece = widget.call;
    if (widget.call) {
      _callClock.start();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    _messages.add(
      ChatMessage(fromUser: false, text: widget.scenario.opening, tipTr: widget.scenario.openingTr),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  /// Asks for the microphone (once), then checks the recognizer. False
  /// when the learner cannot be heard: the error says why and what to do.
  Future<bool> _micReady() async {
    final mic = ref.read(micAccessProvider);
    var status = await mic.status();
    if (status == MicStatus.denied) status = await mic.request();
    if (!mounted) return false;
    if (status != MicStatus.granted) {
      setState(() {
        _typing = !widget.call;
        _micProblem = status;
        _error = status == MicStatus.blocked
            ? 'Mikrofon izni kapalı. Ayarlar > İzinler > Mikrofon bölümünden aç; dönünce kendiliğinden dinlerim.'
            : 'Seni duyabilmem için mikrofon izni gerekiyor.';
      });
      return false;
    }
    if (!await ref.read(speechProvider).canListen) {
      if (!mounted) return false;
      final denied = speechIssue.value == SpeechIssues.noMicPermission;
      setState(() {
        _typing = !widget.call;
        _micProblem = denied ? MicStatus.denied : null;
        _error = denied
            ? 'Seni duyabilmem için mikrofon izni gerekiyor.'
            : 'Mikrofon kullanılamıyor; yazarak devam edebilirsin.';
      });
      return false;
    }
    if (_micProblem != null && mounted) {
      setState(() {
        _micProblem = null;
        _error = null;
        _typing = false;
      });
    }
    return true;
  }

  /// Back from the settings (or the dialog): listen if the microphone works now.
  Future<void> _resumed() async {
    if (_micProblem == null || _finished) return;
    if (await _micReady()) unawaited(_turns.resume());
  }

  /// Checks the microphone, then the partner says the opening line; the
  /// microphone opens by itself when it ends.
  Future<void> _open() async {
    _life;
    await _micReady();
    final opening = widget.scenario.opening;
    // Pre-warm while the opening line is fetched: the talk function and its
    // TTS/Claude connections, and the backchannels in the partner's voice
    // (synthesized once, then cached on the server).
    unawaited(_service.warm());
    if (_premium) {
      for (final phrase in _acks.phrases) {
        unawaited(_service.speak(phrase, voice: _voice, rate: _rate).then((a) => _acks.setAudio(phrase, a)));
      }
    }
    final audio = _premium ? await _service.speak(opening, voice: _voice, rate: _rate) : null;
    if (!mounted || _finished) return;
    _turns.say(SpokenSentence(opening, audio: audio, rate: _rate));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _onLatency(Duration d) {
    _latencies.add(d.inMilliseconds);
    debugPrint('[talk-latency] end-of-speech→first-audio ${d.inMilliseconds} ms');
  }

  // ----------------------------------------------------------------- turns

  void _onUserTurn(int turn, String text) {
    final heard = lastRecognition.value;
    final spoken = !_typing;
    setState(() {
      _error = null;
      _messages.add(
        ChatMessage(
          fromUser: true,
          text: text,
          spoken: spoken,
          evidence: spoken
              ? speechEvidence(heard.isEmpty ? [(words: text, confidence: null)] : heard, text)
              : const [],
        ),
      );
      _replyIndex = null;
    });
    _scrollDown();
    ref.read(progressProvider.notifier).recordTrErrors(detectTrErrors(text), text: text);
    final req = TalkRequest(
      scenario: widget.scenario,
      history: List.of(_messages),
      level: _level,
      goal: goalApiName(ref.read(learnGoalProvider)?.kind),
      voice: _premium ? _voice : null,
    );
    unawaited(_stream?.cancel());
    final userIndex = _messages.length - 1;
    _stream = _service
        .talk(req)
        .listen(
          (e) => _onEvent(turn, userIndex, e),
          onError: (Object e) => _onFailed(turn, userIndex, text, e),
          cancelOnError: true,
        );
  }

  void _onEvent(int turn, int userIndex, TalkEvent e) {
    if (!mounted) return;
    switch (e) {
      case TalkSentenceEvent(:final text, :final audio):
        setState(() {
          final i = _replyIndex;
          if (i == null) {
            _messages.add(ChatMessage(fromUser: false, text: text));
            _replyIndex = _messages.length - 1;
          } else {
            _messages[i] = ChatMessage(fromUser: false, text: '${_messages[i].text} $text');
          }
        });
        _scrollDown();
        _turns.addSentence(turn, SpokenSentence(text, audio: audio, rate: _rate));
      case TalkDoneEvent(turn: final t):
        if (e.serverFirstAudioMs case final ms?) debugPrint('[talk-latency] server first audio $ms ms');
        setState(() {
          // Corrections stay silent: they go to the karne, not into the chat.
          if (userIndex < _messages.length) {
            _messages[userIndex] = _messages[userIndex].withFeedback(
              correction: t.correction,
              tipTr: t.tipTr,
            );
          }
          if (_replyIndex == null && t.reply.isNotEmpty) {
            _messages.add(ChatMessage(fromUser: false, text: t.reply));
            _turns.addSentence(turn, SpokenSentence(t.reply, rate: _rate));
          }
          _done = t.done;
          _freeLeft = t.free ? t.remaining : null;
        });
        _turns.replyComplete(turn);
    }
  }

  Future<void> _onFailed(int turn, int userIndex, String text, Object e) async {
    _turns.replyFailed(turn);
    if (!mounted) return;
    final ex = e is ConversationException ? e : null;
    setState(() {
      if (userIndex < _messages.length && _messages[userIndex].fromUser) _messages.removeAt(userIndex);
      _replyIndex = null;
      _error = ex?.message ?? CallableConversationService.messageForCode('internal');
      if (_typing) _input.text = text;
      if (ex?.freeQuotaUsed ?? false) _freeLeft = 0;
    });
    if (ex?.freeQuotaUsed ?? false) {
      if (ref.read(premiumProvider)) {
        // Premium on this phone, but the server still counts a free user:
        // say so instead of "Premium açıldı" in a loop.
        setState(() {
          _error =
              'Bugünkü ücretsiz mesajlarını kullandın; Premium üyeliğin sunucuda henüz görünmüyor. '
              'Biraz sonra tekrar dene ya da "Bitir" ile karneni al.';
        });
        return;
      }
      final gate = await requirePremium(
        context,
        ref,
        PremiumFeature.aiConversation,
        pitch: talkFreeTastePitch,
      );
      if (!mounted) return;
      setState(() {
        // Never "Premium açıldı" here: only the server's answer to the next
        // message says whether the entitlement is there.
        _error = gate == GateResult.premium
            ? null
            : 'Bugünkü ücretsiz mesajlarını kullandın. "Bitir" ile karneni alabilirsin.';
        if (gate == GateResult.premium) _freeLeft = null;
      });
      if (gate == GateResult.premium && !_typing) unawaited(_turns.resume());
      return;
    }
    // Any other failure: the learner says it again, no tap needed.
    if (!_typing && !_finished) {
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted && !_finished) unawaited(_turns.resume());
      });
    }
  }

  /// The learner cut in: keep only what was actually heard of the reply.
  void _onBargeIn(int turn, int heardSentences) {
    unawaited(_stream?.cancel());
    final i = _replyIndex;
    if (i == null || !mounted) return;
    setState(() {
      final heard = splitSentences(_messages[i].text).take(heardSentences + 1).join(' ');
      _messages[i] = ChatMessage(fromUser: false, text: heard.endsWith('…') ? heard : '$heard…');
      _replyIndex = null;
    });
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  });

  // ---------------------------------------------------------------- finish

  void _finish() {
    if (_finished) return;
    _finished = true;
    unawaited(_turns.close());
    unawaited(_stream?.cancel());
    final userTurns = _messages.where((m) => m.fromUser).length;
    if (latencyStats(_latencies) case final a?) {
      final r = latencyStats(_firstSentence);
      debugPrint(
        '[talk-latency] ${_latencies.length} turns. first audio median ${a.median} p90 ${a.p90} ms; '
        'first real sentence median ${r?.median} p90 ${r?.p90} ms. all: $_latencies / $_firstSentence',
      );
    }
    if (userTurns == 0) {
      Navigator.of(context).pop();
      return;
    }
    final corrections = _messages.where((m) => m.correction != null).length;
    ref
        .read(progressProvider.notifier)
        .completeNode(
          'talk_${widget.scenario.id}',
          xp: talkXp,
          answered: userTurns,
          correct: userTurns - corrections,
          perfect: corrections == 0,
        );
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('Sohbet bitti! +$talkXp XP')));
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ConversationReportScreen(scenario: widget.scenario, history: List.of(_messages)),
      ),
    );
  }

  @override
  void dispose() {
    _life.dispose();
    _tick?.cancel();
    unawaited(_stream?.cancel());
    _turns
      ..removeListener(_changed)
      ..dispose();
    final out = _io.out;
    if (out is AudioVoiceOut) unawaited(out.dispose());
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------- UI

  String get _status => switch (_turns.phase) {
    TalkPhase.listening => _turns.words.isEmpty ? 'Dinliyorum…' : '“${_turns.words}”',
    TalkPhase.thinking => 'Düşünüyor…',
    TalkPhase.speaking => _settings.bargeIn && _premium ? 'Konuşuyor… (sözünü kesebilirsin)' : 'Konuşuyor…',
    TalkPhase.muted => 'Dinleme duraklatıldı',
    TalkPhase.idle => _idleText,
  };

  String get _idleText => _micProblem != null
      ? 'Mikrofon izni bekleniyor'
      : _turns.gaveUp
      ? 'Seni duyamadım. Son cümleye dokunursan tekrar söyler ve dinlerim; ya da yazarak cevap ver.'
      : 'Birazdan dinliyorum…';

  @override
  Widget build(BuildContext context) {
    final talked = _messages.any((m) => m.fromUser);
    return PopScope(
      canPop: !talked || _finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: widget.call ? _callScreen(context) : _chatScreen(context),
    );
  }

  Widget _phaseChip() {
    final (icon, color) = switch (_turns.phase) {
      TalkPhase.listening => (Icons.hearing_rounded, Brand.success),
      TalkPhase.thinking => (Icons.more_horiz_rounded, Brand.accent),
      TalkPhase.speaking => (Icons.graphic_eq_rounded, Brand.primary),
      TalkPhase.muted => (Icons.voice_over_off_rounded, Brand.error),
      TalkPhase.idle => (Icons.hearing_disabled_rounded, Brand.muted),
    };
    return Semantics(
      liveRegion: true,
      child: Row(
        key: const Key('talk-phase'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _status,
              key: const Key('talk-status'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatScreen(BuildContext context) {
    _keyboardScroll(context);
    final s = widget.scenario;
    return Scaffold(
      appBar: AppBar(
        title: Text('${kidEmoji(s.emoji)}${s.title}', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const Key('talk-settings'),
            tooltip: 'Ses ayarları',
            onPressed: () => showVoiceSettingsSheet(context, character: _character),
            icon: const Icon(Icons.tune_rounded),
          ),
          TextButton(onPressed: _finish, child: const Text('Bitir')),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_freeLeft case final left?)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  left > 0 ? 'Ücretsiz: bugün $left mesajın kaldı' : 'Bugünkü ücretsiz mesajların bitti',
                  key: const Key('talk-free-left'),
                  style: TextStyle(color: Brand.accent, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  for (var i = 0; i < _messages.length; i++)
                    PopIn(key: ValueKey(i), from: 0.9, child: _bubble(i)),
                  if (_done)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: PressableButton(
                        label: 'BİTİR · KARNEMİ GÖR',
                        color: Brand.success,
                        onPressed: _finish,
                      ),
                    ),
                ],
              ),
            ),
            if (_error != null) _errorRow(),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Brand.line, width: 2)),
              ),
              child: _typing ? _textBar() : _voiceBar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorRow() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _error!,
            key: const Key('talk-error'),
            style: TextStyle(color: Brand.error),
          ),
        ),
        if (_micProblem != null) _micFixButton(null),
      ],
    ),
  );

  /// No button to press: the microphone opens by itself after the partner
  /// has spoken, and the turn goes when the learner stops talking.
  Widget _micFixButton(Color? color) {
    final blocked = _micProblem == MicStatus.blocked;
    return TextButton(
      key: const Key('talk-mic-fix'),
      style: color == null ? null : TextButton.styleFrom(foregroundColor: color),
      onPressed: () async {
        if (blocked) {
          await ref.read(micAccessProvider).openSettings();
        } else if (await _micReady()) {
          unawaited(_turns.resume());
        }
      },
      child: Text(blocked ? 'Ayarları aç' : 'İzin ver'),
    );
  }

  Widget _voiceBar() {
    final listening = _turns.phase == TalkPhase.listening;
    final speaking = _turns.phase == TalkPhase.speaking;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _phaseChip(),
        const SizedBox(height: 8),
        _ListenOrb(phase: _turns.phase),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            TextButton.icon(
              key: const Key('talk-to-text'),
              onPressed: () => setState(() => _typing = true),
              icon: const Icon(Icons.keyboard_alt_outlined),
              label: const Text('Yazarak cevapla'),
            ),
            if (speaking)
              TextButton.icon(
                key: const Key('talk-interrupt'),
                onPressed: () => unawaited(_turns.interrupt()),
                icon: const Icon(Icons.front_hand_rounded),
                label: const Text('Sözünü kes'),
              ),
            if (!widget.call && !listening && !speaking)
              TextButton.icon(
                key: const Key('talk-call'),
                onPressed: _switchToCall,
                icon: const Icon(Icons.call_rounded),
                label: const Text('Telefonla konuş'),
              ),
          ],
        ),
        Text('Eller serbest: konuş, susunca gönderilir.', style: TextStyle(color: Brand.muted, fontSize: 12)),
        if (kDebugMode && _latencies.isNotEmpty)
          Text('gecikme: ${_latencies.last} ms', style: TextStyle(color: Brand.muted, fontSize: 11)),
      ],
    );
  }

  Future<void> _switchToCall() async {
    if (!_premium) {
      final gate = await requirePremium(
        context,
        ref,
        PremiumFeature.aiConversation,
        pitch: talkFreeTastePitch,
      );
      if (gate != GateResult.premium || !mounted) return;
    }
    if (!mounted) return;
    await _turns.close();
    _finished = true;
    if (!mounted) return;
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => TalkScreen(scenario: widget.scenario, call: true),
        ),
      ),
    );
  }

  Widget _textBar() => Row(
    children: [
      IconButton(
        key: const Key('talk-to-voice'),
        tooltip: 'Sesli konuş',
        onPressed: () async {
          setState(() => _typing = false);
          if (await _micReady()) unawaited(_turns.resume());
        },
        icon: Icon(Icons.record_voice_over_rounded, color: Brand.primary),
      ),
      Expanded(
        child: TextField(
          key: const Key('talk-input'),
          controller: _input,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => unawaited(_sendTyped()),
          maxLength: 400,
          decoration: const InputDecoration(
            hintText: 'İngilizce yaz…',
            counterText: '',
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
      ),
      const SizedBox(width: 6),
      IconButton.filled(
        key: const Key('talk-send'),
        tooltip: 'Gönder',
        onPressed: _turns.phase == TalkPhase.thinking ? null : () => unawaited(_sendTyped()),
        icon: const Icon(Icons.send_rounded),
      ),
    ],
  );

  /// Sends the typed text. While the partner speaks it is cut off and the
  /// text goes; while the reply is on its way the text stays in the field.
  /// The field is cleared only when the text was really sent.
  Future<void> _sendTyped() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    if (await _turns.submitText(text)) {
      if (_input.text.trim() == text) _input.clear();
    } else if (mounted && !_finished) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Cevap geliyor; mesajın burada duruyor, birazdan gönderebilirsin.')),
      );
    }
  }

  /// The keyboard opened: keep the partner's last line in sight.
  double _lastInset = 0;
  void _keyboardScroll(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset > _lastInset) _scrollDown();
    _lastInset = inset;
  }

  Widget _bubble(int i) {
    final m = _messages[i];
    final me = m.fromUser;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: me ? null : () => _turns.say(SpokenSentence(m.text, rate: _rate)),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: me ? Brand.primary : Brand.card,
            border: me ? null : Border.all(color: Brand.line, width: 2),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(me ? 18 : 4),
              bottomRight: Radius.circular(me ? 4 : 18),
            ),
          ),
          child: Text(
            m.text,
            style: TextStyle(
              fontSize: 16,
              color: me ? Brand.onPrimary : Brand.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ phone call

  Widget _callScreen(BuildContext context) {
    final c = _character;
    final name = c?.name ?? widget.scenario.partner;
    final secs = _callClock.elapsed.inSeconds;
    final clock = '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';
    const fg = Colors.white;
    return Scaffold(
      backgroundColor: const Color(0xFF14202B),
      // Scrolls when the largest font makes it taller than a small phone
      // (it overflowed by 27 dp at 360x640, QA); otherwise fills the screen.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Column(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(color: fg, fontSize: 28, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c?.role ?? widget.scenario.title,
                        style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        clock,
                        key: const Key('call-clock'),
                        style: TextStyle(color: fg.withValues(alpha: 0.7)),
                      ),
                      const Spacer(),
                      _CallAvatar(emoji: c?.emoji ?? widget.scenario.emoji, phase: _turns.phase),
                      const SizedBox(height: 24),
                      DefaultTextStyle.merge(
                        style: const TextStyle(color: fg),
                        child: Text(
                          switch (_turns.phase) {
                            TalkPhase.listening => 'Dinliyorum…',
                            TalkPhase.thinking => 'Düşünüyor…',
                            TalkPhase.speaking => 'Konuşuyor…',
                            TalkPhase.muted => 'Dinleme duraklatıldı',
                            TalkPhase.idle => _idleText,
                          },
                          key: const Key('call-status'),
                          style: const TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            key: const Key('talk-error'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFFFB4A8)),
                          ),
                        ),
                      if (_micProblem != null) _micFixButton(fg),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _CallButton(
                            key: const Key('call-mute'),
                            icon: _muted ? Icons.voice_over_off_rounded : Icons.record_voice_over_rounded,
                            label: _muted ? 'Devam et' : 'Duraklat',
                            active: _muted,
                            onTap: () {
                              setState(() => _muted = !_muted);
                              unawaited(_turns.setMuted(_muted));
                            },
                          ),
                          _CallButton(
                            key: const Key('call-interrupt'),
                            icon: Icons.front_hand_rounded,
                            label: 'Sözünü kes',
                            onTap: _turns.phase == TalkPhase.speaking
                                ? () => unawaited(_turns.interrupt())
                                : null,
                          ),
                          _CallButton(
                            key: const Key('call-speaker'),
                            icon: _earpiece ? Icons.phone_in_talk_rounded : Icons.volume_up_rounded,
                            label: _earpiece ? 'Ahize' : 'Hoparlör',
                            active: !_earpiece,
                            onTap: () {
                              setState(() => _earpiece = !_earpiece);
                              unawaited(_io.setEarpiece?.call(_earpiece));
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Semantics(
                        button: true,
                        label: 'Kapat',
                        child: InkResponse(
                          key: const Key('call-hangup'),
                          onTap: () {
                            Haptics.tap();
                            _finish();
                          },
                          radius: 44,
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: const BoxDecoration(color: Color(0xFFE5484D), shape: BoxShape.circle),
                            child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 36),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The microphone's state, not a button: it pulses with the learner's
/// voice while listening.
class _ListenOrb extends StatelessWidget {
  const _ListenOrb({required this.phase});
  final TalkPhase phase;

  @override
  Widget build(BuildContext context) {
    final listening = phase == TalkPhase.listening;
    final speaking = phase == TalkPhase.speaking;
    final color = listening ? Brand.error : (speaking ? Brand.primary : Brand.line);
    return ExcludeSemantics(
      child: ValueListenableBuilder<double>(
        valueListenable: speechLevel,
        builder: (context, level, _) => AnimatedContainer(
          key: const Key('talk-orb'),
          duration: const Duration(milliseconds: 120),
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: color.withValues(alpha: listening ? 0.9 : 0.35),
            shape: BoxShape.circle,
            boxShadow: [
              if (listening)
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 8 + 24 * level,
                  spreadRadius: 2 + 10 * level,
                ),
            ],
          ),
          child: Icon(
            listening
                ? Icons.hearing_rounded
                : (speaking ? Icons.graphic_eq_rounded : Icons.more_horiz_rounded),
            color: Colors.white,
            size: 30,
          ),
        ),
      ),
    );
  }
}

class _CallAvatar extends StatelessWidget {
  const _CallAvatar({required this.emoji, required this.phase});
  final String emoji;
  final TalkPhase phase;

  @override
  Widget build(BuildContext context) {
    final speaking = phase == TalkPhase.speaking;
    final listening = phase == TalkPhase.listening;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(
          color: speaking ? const Color(0xFF7BD389) : (listening ? Colors.white : Colors.white24),
          width: speaking || listening ? 4 : 2,
        ),
      ),
      alignment: Alignment.center,
      // Decoration: the name above already says who is calling.
      child: ExcludeSemantics(child: Text(emoji, style: const TextStyle(fontSize: 64))),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkResponse(
      onTap: onTap,
      radius: 40,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.white : Colors.white.withValues(alpha: onTap == null ? 0.06 : 0.14),
            ),
            child: Icon(icon, color: active ? const Color(0xFF14202B) : Colors.white, size: 28),
          ),
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: SizedBox(
              width: 84,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Ses ayarları: the partner's voice, pause length, barge-in and
/// the level the partner speaks at.
Future<void> showVoiceSettingsSheet(BuildContext context, {Character? character}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => VoiceSettingsSheet(character: character),
    );

class VoiceSettingsSheet extends ConsumerWidget {
  const VoiceSettingsSheet({super.key, this.character});
  final Character? character;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(voiceSettingsProvider);
    final n = ref.read(voiceSettingsProvider.notifier);
    final premium = ref.watch(premiumProvider);
    final c = character;
    final current = s.voiceFor(c);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c == null ? 'Ses ayarları' : '${c.name} için ses',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (!premium)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Doğal yapay zekâ sesleri Premium\'da. Şimdilik telefonunun sesi okuyor.',
                  style: TextStyle(color: Brand.muted, fontSize: 13),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in neuralVoices)
                  ChoiceChip(
                    key: Key('voice-${v.id}'),
                    label: Text(v.label),
                    selected: current == v.id,
                    onSelected: (_) => c == null ? n.setVoice(v.id) : n.setCharacterVoice(c.id, v.id),
                  ),
              ],
            ),
            const Divider(height: 24),
            SwitchListTile(
              key: const Key('voice-bargein'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Sözünü kesebileyim'),
              subtitle: const Text('Karşındaki konuşurken sen başlarsan susup seni dinler.'),
              value: s.bargeIn,
              onChanged: n.setBargeIn,
            ),
            const SizedBox(height: 4),
            const Text('Sustuktan sonra bekleme', style: TextStyle(fontWeight: FontWeight.w700)),
            Wrap(
              spacing: 8,
              children: [
                for (final ms in VoiceSettings.pauseChoices)
                  ChoiceChip(
                    key: Key('pause-$ms'),
                    label: Text('${(ms / 1000).toStringAsFixed(1)} sn'),
                    selected: s.pauseMs == ms,
                    onSelected: (_) => n.setPause(ms),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Karşındaki hangi seviyede konuşsun?', style: TextStyle(fontWeight: FontWeight.w700)),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Otomatik'),
                  selected: s.level == null,
                  onSelected: (_) => n.setLevel(null),
                ),
                for (final l in const ['A1', 'A2', 'B1', 'B2', 'C1'])
                  ChoiceChip(
                    key: Key('level-$l'),
                    label: Text(l),
                    selected: s.level == l,
                    onSelected: (_) => n.setLevel(l),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// True in Çocuk modu: no live AI chat and no voice partner there.
bool talkHiddenForKids(WidgetRef ref) => ref.read(appSettingsProvider).isKid;
