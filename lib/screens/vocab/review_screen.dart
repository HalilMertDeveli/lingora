import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/practice.dart';
import '../../data/progress.dart';
import '../../data/vocab_practice.dart';
import '../../exercises/common.dart';
import '../../models/vocab.dart';
import '../../services/speech.dart';
import '../../theme.dart';
import '../../ui/mascot.dart';
import '../../nav/flow.dart';
import '../../ui/motion.dart';
import '../../ui/session.dart';
import '../lesson_result_screen.dart';
import 'vocab_home_screen.dart';
import 'word_list_screen.dart';

/// Node id for completed review sessions (XP, streak, daily quests).
const vocabReviewNodeId = 'sw_review';

/// Spaced review with mixed card types. The first answer for each word
/// moves it up or back down its box; a wrong card comes back at the end of
/// the session (no hearts, no penalty).
class VocabReviewScreen extends ConsumerStatefulWidget {
  const VocabReviewScreen({super.key, required this.queue, required this.all, this.random});
  final List<VocabEntry> queue;
  final List<VocabEntry> all;
  final Random? random;

  @override
  ConsumerState<VocabReviewScreen> createState() => _VocabReviewScreenState();
}

class _VocabReviewScreenState extends ConsumerState<VocabReviewScreen> {
  late final List<VocabCard> _cards = buildSession(
    widget.queue,
    widget.all,
    ref.read(progressProvider),
    widget.random,
  );
  late final int _total = _cards.length;
  final _graded = <String>{};
  final _started = DateTime.now();
  final _input = TextEditingController();
  int _pos = 0;
  int _combo = 0;
  int _firstTryCorrect = 0;
  String? _picked;
  bool? _correct;

  VocabCard get _card => _cards[_pos];

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _check(String answer) {
    if (_correct != null || answer.trim().isEmpty) return;
    final ok = _card.check(answer);
    final e = _card.entry;
    if (_graded.add(e.id)) {
      ref.read(progressProvider.notifier).reviewWord(e.id, known: ok);
      if (ok) _firstTryCorrect++;
    }
    setState(() {
      _picked = answer;
      _correct = ok;
      _combo = ok ? _combo + 1 : 0;
      if (!ok) _cards.add(_card);
    });
    ok ? SessionFx.correct() : SessionFx.wrong();
    if (ok) ref.read(speechProvider).say(e.word);
  }

  void _next() {
    if (_pos + 1 >= _cards.length) {
      _finish();
      return;
    }
    setState(() {
      _pos++;
      _picked = null;
      _correct = null;
      _input.clear();
    });
  }

  void _finish() {
    final answered = _graded.length;
    final reward = ref
        .read(progressProvider.notifier)
        .completeNode(
          vocabReviewNodeId,
          xp: practiceXp,
          correct: _firstTryCorrect,
          answered: answered,
          perfect: _firstTryCorrect == answered,
        );
    showEndSequence(Navigator.of(context), [
      (next) => LessonResultScreen(
        reward: reward,
        accuracy: answered == 0 ? 100 : (_firstTryCorrect * 100 / answered).round(),
        duration: DateTime.now().difference(_started),
        perfect: _firstTryCorrect == answered,
        headline: 'Tekrar tamamlandı!',
        showStreak: !reward.streakExtended,
        showQuests: !hasQuestStep(reward),
        onContinue: next,
      ),
      ...celebrationSteps(reward),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_cards.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: EmptyState(message: 'Şu an tekrar edilecek kelime yok.')),
      );
    }
    final card = _card;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              SessionHeader(
                progress: min(_graded.length / _total, 1),
                color: vocabColor,
                combo: _combo,
                onClose: _confirmQuit,
                caption: card.type.label.toUpperCase(),
                trailing: Text(
                  '${min(_graded.length, _total)}/$_total',
                  style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: KeyedSubtree(key: ValueKey(_pos), child: _body(card)),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                child: _correct != null
                    ? KeyedSubtree(key: ValueKey('fb$_pos'), child: _feedback(card))
                    : (card.isTyping
                          ? CheckBar(
                              key: const ValueKey('check'),
                              color: Brand.success,
                              onCheck: () => _check(_input.text),
                            )
                          : const SizedBox.shrink(key: ValueKey('none'))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmQuit() async {
    final quit = await confirmQuitFlow(
      context,
      title: 'Tekrardan çıkılsın mı?',
      detail: 'Cevapladığın kelimeler kaydedildi; kalanları sonra tekrar edebilirsin.',
    );
    if (quit && mounted) Navigator.of(context).pop();
  }

  Widget _body(VocabCard card) {
    final locked = _correct != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (card.where != null)
          Text(
            '${kidEmoji(card.where!.emoji)}${card.where!.label}',
            style: TextStyle(color: vocabColor, fontWeight: FontWeight.w800),
          ),
        const SizedBox(height: 8),
        if (card.type == VocabCardType.listenSpell) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SpeakerButton(text: card.speak!, size: 72),
              const SizedBox(width: 16),
              SpeakerButton(text: card.speak!, size: 52, slow: true),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                card.prompt,
                style: TextStyle(
                  fontSize: _isWordPrompt(card) ? 30 : 19,
                  fontWeight: _isWordPrompt(card) ? FontWeight.w900 : FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
            if (card.speak != null && card.type != VocabCardType.listenSpell)
              SpeakerButton(text: card.speak!, size: 40),
          ],
        ),
        if (card.sub != null) ...[
          const SizedBox(height: 6),
          Text(card.sub!, style: TextStyle(color: Brand.muted, fontSize: 15)),
        ],
        const SizedBox(height: 20),
        if (card.isTyping) ...[
          TextField(
            key: const Key('vocabInput'),
            controller: _input,
            enabled: !locked,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: _check,
            decoration: InputDecoration(hintText: card.hint),
          ),
        ] else
          for (final o in card.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TapCard(
                selected: _picked == o || (locked && o == card.answer),
                color: locked
                    ? (o == card.answer ? Brand.success : (o == _picked ? Brand.error : null))
                    : null,
                onTap: locked ? null : () => _check(o),
                child: Text(o, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
      ],
    );
  }

  bool _isWordPrompt(VocabCard c) => c.type == VocabCardType.meaning || c.type == VocabCardType.synonym;

  Widget _feedback(VocabCard card) {
    final ok = _correct!;
    final e = card.entry;
    return AnswerFeedbackPanel(
      correct: ok,
      continueKey: const Key('vocabNext'),
      title: ok ? (_combo >= comboThreshold ? 'Doğru! $_combo üst üste' : 'Doğru!') : 'Doğru cevap:',
      answer: ok || card.answer == e.word || card.answer == e.tr
          ? '${e.word} = ${e.tr}'
          : '${card.answer}  ·  ${e.word} = ${e.tr}',
      detail: e.tip != null && !ok
          ? Text('${kidEmoji('💡')}${e.tip}', style: TextStyle(fontSize: 13, color: Brand.ink))
          : null,
      secondary: TextButton(onPressed: () => showVocabEntry(context, e), child: const Text('Kelimeye bak')),
      onContinue: _next,
    );
  }
}
