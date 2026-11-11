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
import '../../ui/motion.dart';
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
      if (!ok) _cards.add(_card);
    });
    ok ? Haptics.success() : Haptics.error();
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LessonResultScreen(
          reward: reward,
          accuracy: answered == 0 ? 100 : (_firstTryCorrect * 100 / answered).round(),
          duration: DateTime.now().difference(_started),
          perfect: _firstTryCorrect == answered,
          headline: 'Tekrar tamamlandı!',
        ),
      ),
    );
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
    return Scaffold(
      appBar: AppBar(
        title: Text(card.type.label),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: min(_graded.length / _total, 1), color: vocabColor),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: KeyedSubtree(key: ValueKey(_pos), child: _body(card)),
              ),
            ),
            if (_correct != null) _feedback(card),
          ],
        ),
      ),
    );
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
          const SizedBox(height: 12),
          if (!locked)
            PressableButton(label: 'KONTROL ET', color: vocabColor, onPressed: () => _check(_input.text)),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      color: ok ? Brand.successBg : Brand.errorBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            ok ? 'Doğru! ${e.word} = ${e.tr}' : 'Doğru cevap: ${card.answer}',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: ok ? Brand.success : Brand.error,
            ),
          ),
          if (!ok) Text('${e.word} = ${e.tr}', style: TextStyle(color: Brand.ink)),
          if (e.tip != null && !ok) ...[
            const SizedBox(height: 6),
            Text('${kidEmoji('💡')}${e.tip}', style: const TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(onPressed: () => showVocabEntry(context, e), child: const Text('Kelimeye bak')),
              const Spacer(),
              PressableButton(
                key: const Key('vocabNext'),
                label: 'DEVAM',
                color: ok ? Brand.success : Brand.error,
                onPressed: _next,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
