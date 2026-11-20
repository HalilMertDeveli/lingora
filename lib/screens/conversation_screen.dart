import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/speech_evidence.dart';
import '../core/tr_errors.dart';
import '../data/app_settings.dart';
import '../data/progress.dart';
import '../data/scenarios.dart';
import '../services/billing/premium.dart';
import '../services/conversation.dart';
import '../services/speech.dart';
import '../services/growth/analytics.dart';
import '../services/growth/remote_flags.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../exercises/hands_free.dart';
import '../services/mic_access.dart';
import '../ui/motion.dart';
import 'conversation_report_screen.dart';
import 'paywall_screen.dart';
import 'pronunciation_screen.dart';
import '../voice/natural_talk_section.dart';
import '../voice/talk_screen.dart';

const conversationXp = 15;

/// Learner messages a day with the live AI without Premium (server: FREE_DAILY_MESSAGE_LIMIT).
const freeChatMessagesPerDay = 3;

/// Shown on the paywall once the free daily taste is used up.
const freeTastePitch = "Özel hoca saati 500 TL. Çenebaz'da her gün sınırsız konuşma, ayda bir ders fiyatına.";

/// "Konuş" tab: pick a role-play scenario.
class ConversationHomeScreen extends ConsumerWidget {
  const ConversationHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Çocuk modu never talks to the live AI: the scripted demo only.
    final kid = ref.watch(appSettingsProvider.select((s) => s.isKid));
    final live = ref.watch(conversationServiceProvider).isLive && !kid;
    final premium = ref.watch(premiumProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            const Mascot(mood: Mood.happy, size: 84, decorative: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Konuşarak öğren', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Gerçek bir sahnede İngilizce konuş. Hatalarını anında, Türkçe açıklamayla düzeltelim.',
                    style: TextStyle(color: Brand.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const PronunciationEntryCard(),
        const SizedBox(height: 12),
        if (!live)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Brand.accentBg, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Icon(Icons.science_rounded, color: Brand.accent),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    // Kid mode is a choice, not a missing server: say so.
                    kid ? 'Ebeveyn gözetimli modda yapay zekâ kapalı: cevaplar hazır senaryodan gelir.' : 'Demo modu: cevaplar hazır senaryodan gelir. Yapay zekâ sohbeti sunucu bağlanınca açılır.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        if (live && !premium) ...[
          Container(
            key: const Key('free-taste-banner'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Brand.accentBg, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Icon(Icons.record_voice_over_rounded, color: Brand.accent),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Sesli konuşma koçu: her gün $freeChatMessagesPerDay mesaj ücretsiz, sonunda karnen hazır. '
                    'Premium ile her gün doyasıya konuş.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (!kid) ...[const NaturalTalkSection(), const SizedBox(height: 12), const SectionLabel('SAHNELER')],
        const SizedBox(height: 12),
        for (final s in scenarios)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TapCard(
              onTap: () => openConversation(context, ref, s),
              child: Row(
                children: [
                  IconBadge(icon: scenarioIcon(s.id), emoji: s.emoji, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(s.title, style: Theme.of(context).textTheme.titleMedium)),
                            const SizedBox(width: 6),
                            _Tag(s.level),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(s.goal, style: TextStyle(color: Brand.muted, fontSize: 13)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Brand.muted),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Opens a role-play with the voice coach. Everyone talks to the live AI:
/// Premium all day, free users for a daily taste of [freeChatMessagesPerDay]
/// messages (the server counts), after which the paywall opens.
Future<void> openConversation(BuildContext context, WidgetRef ref, Scenario s) async {
  final kid = ref.read(appSettingsProvider).isKid;
  final live = ref.read(conversationServiceProvider).isLive;
  // Remote Config can switch the live AI off (cost/incident); the demo stays.
  // Çocuk modu always gets the scripted demo: no live AI chat for kids.
  final demo = kid || (live && !ref.read(remoteFlagsProvider).aiChatEnabled);
  logEvent(ref, AnalyticsEvent.featureUse(live && !demo ? AppFeature.aiChat : AppFeature.demoChat));
  // Premium: the natural voice partner (hands-free, neural voice, barge-in).
  if (live && !demo && ref.read(premiumProvider)) {
    await openTalk(context, ref, s);
    return;
  }
  final screen = ConversationScreen(scenario: s);
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => demo || !live
          ? ProviderScope(
              overrides: [
                conversationServiceProvider.overrideWithValue(DemoConversationService()),
                conversationReportServiceProvider.overrideWithValue(DemoConversationReportService()),
              ],
              child: screen,
            )
          : screen,
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Brand.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, required this.scenario});
  final Scenario scenario;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final SpeechService _speech = ref.read(speechProvider);
  late final List<ChatMessage> _messages = [
    ChatMessage(fromUser: false, text: widget.scenario.opening, tipTr: widget.scenario.openingTr),
  ];
  final Set<int> _showTr = {};
  bool _waiting = false;
  bool _done = false;
  String? _error;

  /// "Bitir" ran: XP is counted once and nothing is sent any more.
  bool _finished = false;

  /// Voice coach: the partner's line is read aloud, then the microphone
  /// opens by itself; when the learner stops talking the message goes.
  /// Off = the text fallback (type and send).
  bool _voice = true;
  late final AutoListen _mic = AutoListen(
    speech: _speech,
    player: ref.read(linePlayerProvider),
    mic: ref.read(micAccessProvider),
    // Free speech: a longer pause before the turn ends.
    silence: const Duration(milliseconds: 1600),
  )..addListener(_micChanged);

  /// The recognizer's guesses for the text now in the input (null once typed over).
  List<SpeechGuess>? _guesses;

  /// Free daily taste: messages left today (null = unknown / Premium).
  int? _freeLeft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _partnerSays(widget.scenario.opening));
  }

  void _micChanged() {
    if (!mounted) return;
    setState(() {
      final phase = _mic.phase;
      // Back from the settings with the permission: voice again.
      if (phase == ListenPhase.listening) _voice = true;
      if (_voice && _mic.listening) _input.text = _mic.words;
      // Cannot be heard: the text fallback, with the reason (and the
      // permission notice above it).
      if (_voice &&
          const {ListenPhase.unavailable, ListenPhase.blocked, ListenPhase.denied}.contains(phase)) {
        _voice = false;
        if (phase == ListenPhase.unavailable) _error = 'Mikrofon kullanılamıyor; yazarak devam edebilirsin.';
      }
    });
  }

  /// The partner's line is read aloud; in voice mode the microphone opens
  /// when it ends.
  void _partnerSays(String line) {
    if (_voice && !_finished && !_done) {
      _mic.start(prompt: line, onHeard: _heardTurn);
    } else {
      _speech.say(line);
    }
  }

  void _heardTurn(String words) {
    if (!mounted || _finished) return;
    final heard = lastRecognition.value;
    setState(() {
      _input.text = words.trim();
      _guesses = heard.isEmpty ? [(words: _input.text, confidence: null)] : heard;
    });
    if (_input.text.isNotEmpty) _send();
  }

  @override
  void dispose() {
    _mic
      ..removeListener(_micChanged)
      ..dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  });

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _waiting || _finished) return;
    final guesses = _guesses;
    _guesses = null;
    _input.clear();
    setState(() {
      _messages.add(
        ChatMessage(
          fromUser: true,
          text: text,
          spoken: guesses != null,
          evidence: guesses == null ? const [] : speechEvidence(guesses, text),
        ),
      );
      _waiting = true;
      _error = null;
    });
    _scrollDown();
    try {
      final turn = await ref.read(conversationServiceProvider).send(widget.scenario, _messages);
      if (!mounted) return;
      setState(() {
        // Attach feedback to the learner's message, then add the reply.
        final i = _messages.length - 1;
        _messages[i] = _messages[i].withFeedback(correction: turn.correction, tipTr: turn.tipTr);
        _messages.add(ChatMessage(fromUser: false, text: turn.reply));
        _done = turn.done;
        _waiting = false;
        _freeLeft = turn.free ? turn.remaining : null;
      });
      turn.correction == null ? Haptics.success() : Haptics.tap();
      ref.read(progressProvider.notifier).recordTrErrors(detectTrErrors(text), text: text);
      _partnerSays(turn.reply);
    } on ConversationException catch (e) {
      if (!mounted) return;
      final failed = _messages.removeLast();
      setState(() {
        _input.text = text;
        _guesses = failed.spoken ? guesses : null;
        _waiting = false;
        _error = e.message;
        _voice = false; // the text stays in the input, ready to send again
        if (e.freeQuotaUsed) _freeLeft = 0;
      });
      if (e.freeQuotaUsed) await _freeTasteOver();
    } on Object {
      // A malformed answer must not leave the chat stuck on "yazıyor…".
      if (!mounted) return;
      final failed = _messages.removeLast();
      setState(() {
        _input.text = text;
        _guesses = failed.spoken ? guesses : null;
        _waiting = false;
        _voice = false;
        _error = CallableConversationService.messageForCode('internal');
      });
    }
    _scrollDown();
  }

  /// The free daily taste is used up: the paywall, with the private-tutor
  /// comparison. After buying, the same message can simply be sent again.
  Future<void> _freeTasteOver() async {
    if (ref.read(premiumProvider)) {
      // Premium on this phone, but the server still counts a free user: say
      // so instead of a silent loop.
      setState(() {
        _error =
            'Bugünkü ücretsiz mesajlarını kullandın; Premium üyeliğin sunucuda henüz görünmüyor. '
            'Biraz sonra tekrar dene ya da "Bitir" ile karneni al.';
      });
      return;
    }
    final gate = await requirePremium(context, ref, PremiumFeature.aiConversation, pitch: freeTastePitch);
    if (!mounted) return;
    setState(() {
      if (gate == GateResult.premium) {
        _freeLeft = null;
        _error = null;
      } else {
        _error =
            'Bugünkü $freeChatMessagesPerDay ücretsiz mesajını kullandın. "Bitir" ile karneni alabilirsin.';
      }
    });
  }

  void _finish() {
    if (_finished) return;
    _mic.cancel();
    final userTurns = _messages.where((m) => m.fromUser).length;
    final corrections = _messages.where((m) => m.correction != null).length;
    if (userTurns == 0) {
      Navigator.pop(context);
      return;
    }
    _finished = true;
    ref
        .read(progressProvider.notifier)
        .completeNode(
          'talk_${widget.scenario.id}',
          xp: conversationXp,
          answered: userTurns,
          correct: userTurns - corrections,
          perfect: corrections == 0,
        );
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('Sohbet bitti! +$conversationXp XP')));
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ConversationReportScreen(scenario: widget.scenario, history: List.of(_messages)),
      ),
    );
  }

  /// Back or ✕ in a started chat: end it with the karne, or leave.
  Future<void> _confirmLeave() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sohbetten çıkılsın mı?'),
        content: const Text("Çıkarsan bu sohbetin XP'si ve karnesi kaydedilmez."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'stay'), child: const Text('Devam et')),
          TextButton(
            key: const Key('chat-leave'),
            onPressed: () => Navigator.pop(context, 'leave'),
            child: const Text('Çık'),
          ),
          FilledButton(
            key: const Key('chat-leave-finish'),
            onPressed: () => Navigator.pop(context, 'finish'),
            child: const Text('Bitir, karnemi gör'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'finish' && !_waiting) {
      _finish();
    } else if (choice == 'leave') {
      _mic.cancel();
      _finished = true; // nothing is sent any more
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// The keyboard opened: keep the partner's last line in sight.
  double _lastInset = 0;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset > _lastInset) _scrollDown();
    _lastInset = inset;
    final s = widget.scenario;
    // With the keyboard up (small phone, large text) the pinned goal would
    // leave no room for the input itself; it comes back when typing ends.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final talked = _messages.any((m) => m.fromUser);
    return PopScope(
      // Leaving a started chat loses its messages and karne: ask first.
      canPop: !talked || _finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${kidEmoji(s.emoji)}${s.title}'),
          actions: [TextButton(onPressed: _waiting ? null : _finish, child: const Text('Bitir'))],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (!typing)
                Container(
                  key: const Key('chat-goal'),
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(14)),
                  child: Text(
                    '${kidEmoji('🎯')}${s.goal}\nKarşındaki: ${s.partner}',
                    style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
                  ),
                ),
              if (_freeLeft case final left?)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    left > 0 ? 'Ücretsiz: bugün $left mesajın kaldı' : 'Bugünkü ücretsiz mesajların bitti',
                    key: const Key('free-left'),
                    style: TextStyle(color: Brand.accent, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    for (var i = 0; i < _messages.length; i++)
                      PopIn(key: ValueKey(i), from: 0.85, child: _bubble(i)),
                    if (_waiting)
                      Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 10),
                            Text('yazıyor…', style: TextStyle(color: Brand.muted)),
                          ],
                        ),
                      ),
                    if (_done)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: PressableButton(
                          label: 'HEDEF TAMAM · KARNEMİ GÖR',
                          color: Brand.success,
                          onPressed: _finish,
                        ),
                      ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_error!, style: TextStyle(color: Brand.error)),
                      ),
                    ],
                  ),
                ),
              if (!_voice && const {ListenPhase.blocked, ListenPhase.denied}.contains(_mic.phase))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: AutoListenStatus(listen: _mic),
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Brand.line, width: 2)),
                ),
                child: _voice ? _voiceBar() : _textBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Voice mode: no button to press. The microphone opens by itself after
  /// the partner's line; what is heard shows live.
  Widget _voiceBar() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_mic.phase != ListenPhase.idle && !_waiting) AutoListenStatus(listen: _mic, again: false),
      if (_mic.phase == ListenPhase.idle || _waiting)
        Text(
          _waiting ? 'Gönderildi, cevap bekleniyor…' : 'Karşındaki konuşunca mikrofon kendiliğinden açılır.',
          key: const Key('voice-status'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Brand.muted),
        ),
      const SizedBox(height: 6),
      Center(
        child: TextButton.icon(
          key: const Key('to-text'),
          onPressed: () {
            _mic.cancel();
            setState(() => _voice = false);
          },
          icon: const Icon(Icons.keyboard_alt_outlined),
          label: const Text('Yazarak cevapla'),
        ),
      ),
    ],
  );

  /// Text fallback: type (or dictate and fix) and send.
  Widget _textBar() => Row(
    children: [
      IconButton(
        key: const Key('to-voice'),
        tooltip: 'Sesli konuş',
        onPressed: _waiting
            ? null
            : () {
                setState(() {
                  _voice = true;
                  _error = null;
                });
                _mic.start(onHeard: _heardTurn);
              },
        icon: Icon(Icons.record_voice_over_rounded, color: Brand.primary),
      ),
      Expanded(
        child: TextField(
          key: const Key('chat-input'),
          controller: _input,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _send(),
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
        tooltip: 'Gönder',
        key: const Key('chat-send'),
        onPressed: _waiting ? null : _send,
        icon: const Icon(Icons.send_rounded),
      ),
    ],
  );

  Widget _bubble(int i) {
    final m = _messages[i];
    final me = m.fromUser;
    final bubble = GestureDetector(
      onTap: me
          ? null
          : () {
              _speech.say(m.text);
              if (m.tipTr != null) setState(() => _showTr.contains(i) ? _showTr.remove(i) : _showTr.add(i));
            },
      child: Container(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (me && m.spoken)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 2),
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      size: 16,
                      color: Brand.onPrimary,
                      semanticLabel: 'sesli',
                    ),
                  ),
                if (!me)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 2),
                    child: Icon(Icons.volume_up_rounded, size: 16, color: Brand.muted),
                  ),
                Flexible(
                  child: Text(
                    m.text,
                    style: TextStyle(
                      fontSize: 16,
                      color: me ? Brand.onPrimary : Brand.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (!me && _showTr.contains(i) && m.tipTr != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(m.tipTr!, style: TextStyle(color: Brand.muted)),
              ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: me ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          bubble,
          if (me && m.correction != null)
            Container(
              margin: const EdgeInsets.only(top: 6, left: 30),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Brand.accentBg, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${kidEmoji('💡')}Daha doğal: ${m.correction}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (m.tipTr != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(m.tipTr!, style: TextStyle(color: Brand.muted, fontSize: 13)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Adult-mode icon for a role-play scenario (kid mode shows its emoji).
IconData scenarioIcon(String id) => switch (id) {
  'cafe' => Icons.local_cafe_outlined,
  'hotel_checkin' => Icons.hotel_outlined,
  'hotel_reception' => Icons.room_service_outlined,
  'restaurant_guest' => Icons.restaurant_outlined,
  'directions' => Icons.map_outlined,
  'interview' => Icons.work_outline_rounded,
  'doctor' => Icons.medical_services_outlined,
  _ => Icons.forum_outlined,
};
