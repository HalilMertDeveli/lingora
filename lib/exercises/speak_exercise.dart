import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/spoken_match.dart';
import '../models/course.dart';
import '../services/speech.dart';
import '../theme.dart';
import 'common.dart';
import 'speak_mic.dart';

/// Minimum share of the sentence's words that must be recognized, for
/// callers that still score with a plain ratio. Speaking exercises use
/// [SpokenMatch.passed] (about 80%, one slip in short sentences).
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
  SpokenMatch? _match;
  int _failures = 0;
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
      setState(() {
        _unavailable = true;
        _failures++;
      });
      return;
    }
    setState(() {
      _listening = true;
      _heard = '';
      _match = null;
    });
    await speech.listenTo(
      widget.ex.text!,
      onWords: (w) {
        if (mounted) setState(() => _heard = w);
      },
      onDone: () {
        if (!mounted) return;
        final match = matchSpoken(widget.ex.text!, [_heard]);
        setState(() {
          _listening = false;
          _match = match;
          if (!match.passed) _failures++;
        });
        widget.onReady(match.heard.isEmpty ? null : () => match.passed);
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
    final match = _match;
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
                  if (ex.translation != null) Text(ex.translation!, style: TextStyle(color: Brand.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Center(
          child: MicButton(listening: _listening, onTap: widget.locked ? null : _toggle),
        ),
        const SizedBox(height: 8),
        if (!_listening && match != null && match.heard.isNotEmpty) ...[
          SpokenWordsView(match: match),
          const SizedBox(height: 6),
        ],
        ValueListenableBuilder<String?>(
          valueListenable: speechIssue,
          builder: (context, issue, _) => Text(
            key: const ValueKey('speak-status'),
            spokenStatus(
              listening: _listening,
              heard: _heard,
              match: match,
              issue: issue ?? (_unavailable ? SpeechIssues.noRecognizer : null),
              idle: 'Mikrofona dokun ve konuş',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: _listening && _heard.isNotEmpty ? Brand.ink : Brand.muted, fontSize: 16),
          ),
        ),
        const SizedBox(height: 16),
        if (!widget.locked) SpeakSkipButton(failures: _failures, onSkip: widget.onSkip),
      ],
    );
  }
}
