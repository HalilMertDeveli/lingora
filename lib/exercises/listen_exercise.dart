import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/spelling.dart';
import '../core/text.dart';
import '../data/spelling_lexicon.dart';
import '../models/course.dart';
import '../services/speech.dart';
import 'common.dart';
import 'word_bank.dart';

/// Hear an English sentence and type it. A learner who cannot type it can
/// switch to building it from word tiles ("Yazamıyorum, kelimelerden seç");
/// the choice lasts for this exercise only, the next one starts typed.
class ListenExercise extends ConsumerStatefulWidget {
  const ListenExercise({
    super.key,
    required this.ex,
    required this.locked,
    required this.onReady,
    this.onText,
  });
  final Exercise ex;
  final bool locked;
  final ReadyCallback onReady;

  /// Reports what the user typed or built (for the "Neden yanlış?" panel).
  final ValueChanged<String>? onText;

  @override
  ConsumerState<ListenExercise> createState() => _ListenExerciseState();
}

class _ListenExerciseState extends ConsumerState<ListenExercise> {
  final _input = TextEditingController();

  /// Building from word tiles instead of typing.
  bool _useBank = false;
  late final List<String> _bank = sentenceBank(widget.ex.text!);
  List<int> _chosen = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(speechProvider).say(widget.ex.text!));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _typed(String text) {
    widget.onText?.call(text);
    widget.onReady(text.trim().isEmpty ? null : () => listenMatch(ref, widget.ex, _input.text).correct);
  }

  void _built(List<int> chosen) {
    setState(() => _chosen = chosen);
    final text = WordBank.sentence(_bank, chosen);
    widget.onText?.call(text);
    // Tiles are real words: no spelling slip to forgive, so a distractor one
    // letter off ("an" for "a") is simply wrong.
    widget.onReady(chosen.isEmpty ? null : () => matchesAny(text, widget.ex.answers));
  }

  void _switch(bool bank) {
    FocusScope.of(context).unfocus();
    setState(() => _useBank = bank);
    bank ? _built(_chosen) : _typed(_input.text);
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.ex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExerciseTitle('Duyduğunu yaz'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SpeakerButton(text: ex.text!, size: 88),
            const SizedBox(width: 20),
            SpeakerButton(text: ex.text!, size: 56, slow: true),
          ],
        ),
        SizedBox(height: _useBank ? 20 : 32),
        if (_useBank)
          WordBank(words: _bank, chosen: _chosen, locked: widget.locked, onChanged: _built)
        else
          TextField(
            key: const Key('listen-field'),
            controller: _input,
            enabled: !widget.locked,
            minLines: 3,
            maxLines: 4,
            autocorrect: false,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(hintText: 'İngilizce yaz'),
            onChanged: _typed,
          ),
        if (!widget.locked)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: _useBank
                  ? TextButton.icon(
                      key: const Key('listen-use-keyboard'),
                      icon: const Icon(Icons.keyboard_rounded),
                      label: const Text('Klavyeyle yaz'),
                      onPressed: () => _switch(false),
                    )
                  : TextButton.icon(
                      key: const Key('listen-use-bank'),
                      icon: const Icon(Icons.view_module_rounded),
                      label: const Text('Yazamıyorum, kelimelerden seç'),
                      onPressed: () => _switch(true),
                    ),
            ),
          ),
      ],
    );
  }
}

/// How a dinle-yaz answer compares to the accepted ones; the lesson screen
/// uses the same call for its "Küçük bir yazım hatası" note.
AnswerMatch listenMatch(WidgetRef ref, Exercise ex, String input) =>
    matchAnswer(input, ex.answers, lexicon: ref.read(spellingLexiconProvider));
