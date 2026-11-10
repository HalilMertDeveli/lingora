import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/text.dart';
import '../models/course.dart';
import '../services/speech.dart';
import 'common.dart';

/// Hear an English sentence and type it.
class ListenExercise extends ConsumerStatefulWidget {
  const ListenExercise({super.key, required this.ex, required this.locked, required this.onReady});
  final Exercise ex;
  final bool locked;
  final ReadyCallback onReady;

  @override
  ConsumerState<ListenExercise> createState() => _ListenExerciseState();
}

class _ListenExerciseState extends ConsumerState<ListenExercise> {
  final _input = TextEditingController();

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
        const SizedBox(height: 32),
        TextField(
          controller: _input,
          enabled: !widget.locked,
          minLines: 3,
          maxLines: 4,
          autocorrect: false,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(hintText: 'İngilizce yaz'),
          onChanged: (text) =>
              widget.onReady(text.trim().isEmpty ? null : () => matchesAny(_input.text, ex.answers)),
        ),
      ],
    );
  }
}
