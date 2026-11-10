import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/text.dart';
import '../models/course.dart';
import '../services/speech.dart';
import '../theme.dart';
import 'common.dart';

/// Minimum share of the sentence's words that must be recognized.
const speakPassRatio = 0.7;

class SpeakExercise extends ConsumerStatefulWidget {
  const SpeakExercise({
    super.key,
    required this.ex,
    required this.locked,
    required this.onReady,
    required this.onSkip,
  });
  final Exercise ex;
  final bool locked;
  final ReadyCallback onReady;
  final VoidCallback onSkip;

  @override
  ConsumerState<SpeakExercise> createState() => _SpeakExerciseState();
}

class _SpeakExerciseState extends ConsumerState<SpeakExercise> {
  bool _listening = false;
  bool _unavailable = false;
  String _heard = '';
  late final SpeechService _speech;

  @override
  void initState() {
    super.initState();
    _speech = ref.read(speechProvider);
  }

  Future<void> _toggle() async {
    final speech = _speech;
    if (_listening) {
      await speech.stopListening();
      return;
    }
    if (!await speech.canListen) {
      setState(() => _unavailable = true);
      return;
    }
    setState(() {
      _listening = true;
      _heard = '';
    });
    await speech.listen(
      onWords: (w) => setState(() => _heard = w),
      onDone: () {
        if (!mounted) return;
        setState(() => _listening = false);
        widget.onReady(
          _heard.isEmpty ? null : () => spokenSimilarity(widget.ex.text!, _heard) >= speakPassRatio,
        );
      },
    );
  }

  @override
  void dispose() {
    if (_listening) _speech.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.ex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExerciseTitle('Bu cümleyi sesli oku'),
        Row(
          children: [
            SpeakerButton(text: ex.text!),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ex.text!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  if (ex.translation != null)
                    Text(ex.translation!, style: const TextStyle(color: Brand.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
        Center(
          child: Material(
            color: _listening ? Brand.error : Brand.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.locked ? null : _toggle,
              child: SizedBox(
                width: 96,
                height: 96,
                child: Icon(
                  _listening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _unavailable
              ? 'Bu cihazda ses tanıma kullanılamıyor.'
              : _listening
              ? 'Dinliyorum…'
              : _heard.isEmpty
              ? 'Mikrofona dokun ve konuş'
              : '“$_heard”',
          textAlign: TextAlign.center,
          style: TextStyle(color: _heard.isEmpty ? Brand.muted : Brand.ink, fontSize: 16),
        ),
        const SizedBox(height: 16),
        if (!widget.locked) TextButton(onPressed: widget.onSkip, child: const Text('Şu an konuşamıyorum')),
      ],
    );
  }
}
