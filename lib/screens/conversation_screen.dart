import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tr_errors.dart';
import '../data/progress.dart';
import '../data/scenarios.dart';
import '../services/billing/premium.dart';
import '../services/conversation.dart';
import '../services/speech.dart';
import '../services/growth/analytics.dart';
import '../services/growth/remote_flags.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import 'paywall_screen.dart';
import 'pronunciation_screen.dart';

const conversationXp = 15;

/// "Konuş" tab: pick a role-play scenario.
class ConversationHomeScreen extends ConsumerWidget {
  const ConversationHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(conversationServiceProvider).isLive;
    final premium = ref.watch(premiumProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            const Mascot(mood: Mood.happy, size: 84),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Konuşarak öğren', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  const Text(
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
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4DC),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.science_rounded, color: Brand.accent),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Demo modu: cevaplar hazır senaryodan gelir. Yapay zekâ sohbeti sunucu bağlanınca açılır.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        for (final s in scenarios)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TapCard(
              onTap: () => openConversation(context, ref, s),
              child: Row(
                children: [
                  Text(s.emoji, style: const TextStyle(fontSize: 34)),
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
                            if (live && !premium) ...[
                              const SizedBox(width: 4),
                              const _Tag('PREMIUM', color: Brand.accent),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(s.goal, style: const TextStyle(color: Brand.muted, fontSize: 13)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Brand.muted),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Opens a role-play. The live AI partner is Premium; without Premium the
/// paywall offers the free scripted demo of the same scenario instead.
Future<void> openConversation(BuildContext context, WidgetRef ref, Scenario s) async {
  final live = ref.read(conversationServiceProvider).isLive;
  // Remote Config can switch the live AI off (cost/incident); the demo stays.
  var demo = live && !ref.read(remoteFlagsProvider).aiChatEnabled;
  if (live && !demo) {
    final gate = await requirePremium(
      context,
      ref,
      PremiumFeature.aiConversation,
      freeAlternative: 'ÜCRETSİZ DEMO İLE DENE',
    );
    if (gate == GateResult.closed || !context.mounted) return;
    demo = gate == GateResult.free;
  }
  logEvent(ref, AnalyticsEvent.featureUse(live && !demo ? AppFeature.aiChat : AppFeature.demoChat));
  final screen = ConversationScreen(scenario: s);
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => demo
          ? ProviderScope(
              overrides: [conversationServiceProvider.overrideWithValue(DemoConversationService())],
              child: screen,
            )
          : screen,
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.color = Brand.primary});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
    ),
  );
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
  bool _listening = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speech.say(widget.scenario.opening));
  }

  @override
  void dispose() {
    _speech.stopListening();
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
    if (text.isEmpty || _waiting) return;
    _input.clear();
    setState(() {
      _messages.add(ChatMessage(fromUser: true, text: text));
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
        _messages[i] = ChatMessage(
          fromUser: true,
          text: text,
          correction: turn.correction,
          tipTr: turn.tipTr,
        );
        _messages.add(ChatMessage(fromUser: false, text: turn.reply));
        _done = turn.done;
        _waiting = false;
      });
      turn.correction == null ? Haptics.success() : Haptics.tap();
      ref.read(progressProvider.notifier).recordTrErrors(detectTrErrors(text));
      _speech.say(turn.reply);
    } on ConversationException catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeLast();
        _input.text = text;
        _waiting = false;
        _error = e.message;
      });
    }
    _scrollDown();
  }

  Future<void> _mic() async {
    if (_listening) {
      await _speech.stopListening();
      return;
    }
    if (!await _speech.canListen) {
      setState(() => _error = 'Mikrofon kullanılamıyor; yazarak devam edebilirsin.');
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onWords: (w) => setState(() => _input.text = w),
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
  }

  void _finish() {
    final userTurns = _messages.where((m) => m.fromUser).length;
    final corrections = _messages.where((m) => m.correction != null).length;
    if (userTurns > 0) {
      ref
          .read(progressProvider.notifier)
          .completeNode(
            'talk_${widget.scenario.id}',
            xp: conversationXp,
            answered: userTurns,
            correct: userTurns - corrections,
            perfect: corrections == 0,
          );
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: Mascot(mood: corrections == 0 ? Mood.cheer : Mood.happy, size: 96),
        title: const Text('Sohbet bitti!', textAlign: TextAlign.center),
        content: Text(
          userTurns == 0
              ? 'Bir dahaki sefere birkaç cümle dene.'
              : '$userTurns mesaj yazdın, $corrections tanesinde düzeltme önerildi.\n+$conversationXp XP',
          textAlign: TextAlign.center,
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              Navigator.pop(context);
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scenario;
    return Scaffold(
      appBar: AppBar(
        title: Text('${s.emoji} ${s.title}'),
        actions: [TextButton(onPressed: _finish, child: const Text('BİTİR'))],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(14)),
              child: Text(
                '🎯 ${s.goal}\nKarşındaki: ${s.partner}',
                style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
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
                    const Padding(
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
                        label: 'HEDEF TAMAM · BİTİR',
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
                child: Text(_error!, style: const TextStyle(color: Brand.error)),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Brand.line, width: 2)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _mic,
                    icon: Icon(
                      _listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
                      color: _listening ? Brand.error : Brand.primary,
                    ),
                  ),
                  Expanded(
                    child: TextField(
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
                  IconButton.filled(onPressed: _waiting ? null : _send, icon: const Icon(Icons.send_rounded)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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
          color: me ? Brand.primary : Colors.white,
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
            Text(
              m.text,
              style: TextStyle(
                fontSize: 16,
                color: me ? Colors.white : Brand.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (!me && _showTr.contains(i) && m.tipTr != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(m.tipTr!, style: const TextStyle(color: Brand.muted)),
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
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4DC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('💡 Daha doğal: ${m.correction}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (m.tipTr != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(m.tipTr!, style: const TextStyle(color: Brand.muted, fontSize: 13)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
