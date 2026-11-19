import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pronunciation_feedback.dart';
import '../core/spoken_match.dart';
import '../models/course.dart';
import '../services/speech.dart';
import '../theme.dart';
import '../ui/pronunciation_score.dart';
import 'common.dart';
import 'hands_free.dart';
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
  PronunciationFeedback? _score;
  int _failures = 0;
  bool _noSpeech = false;

  /// "Yazarak cevapla": the equal path without a microphone (no permission,
  /// a noisy place, recognition failing). The typed sentence is graded with
  /// the same tolerance as speech and counts like a spoken answer.
  bool _typing = false;
  final _typed = TextEditingController();
  late final SpeechService _speech;
  late final HandsFreeTurn _turn;

  bool get _handsFree => ref.read(handsFreeProvider);

  @override
  void initState() {
    super.initState();
    _speech = ref.read(speechProvider);
    _turn = HandsFreeTurn(speech: _speech, player: ref.read(linePlayerProvider));
    // Hands-free: the sentence is read out, then the microphone opens.
    if (!widget.locked && _handsFree) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoListen(prompt: widget.ex.text);
      });
    }
  }

  Future<void> _autoListen({String? prompt}) async {
    setState(() {
      _noSpeech = false;
      _heard = '';
    });
    await _turn.run(
      target: widget.ex.text!,
      prompt: prompt,
      onListening: () {
        if (!mounted) return;
        setState(() {
          _listening = true;
          _match = null;
          _score = null;
        });
      },
      onWords: (w) {
        if (mounted) setState(() => _heard = w);
      },
      onDone: ({required bool noSpeech}) {
        if (!mounted) return;
        if (noSpeech) {
          setState(() {
            _listening = false;
            _noSpeech = true;
          });
          return;
        }
        _judge();
      },
    );
  }

  void _judge() {
    final match = matchSpoken(widget.ex.text!, [_heard]);
    setState(() {
      _listening = false;
      _match = match;
      _score = pronunciationFeedback(widget.ex.text!, lastRecognition.value, heard: _heard);
      if (!match.passed) _failures++;
    });
    widget.onReady(match.heard.isEmpty ? null : () => match.passed);
  }

  Future<void> _toggle() async {
    final speech = _speech;
    if (_listening) {
      await speech.stopListening();
      return;
    }
    if (_handsFree) {
      _turn.cancel();
      if (!await speech.canListen) {
        setState(() {
          _unavailable = true;
          _failures++;
        });
        return;
      }
      handsFreeMicRefused = false;
      await _autoListen();
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
      _score = null;
    });
    await speech.listenTo(
      widget.ex.text!,
      onWords: (w) {
        if (mounted) setState(() => _heard = w);
      },
      onDone: () {
        if (mounted) _judge();
      },
    );
  }

  void _startTyping() {
    _turn.cancel();
    if (_listening) _speech.stopListening();
    setState(() {
      _typing = true;
      _listening = false;
      _noSpeech = false;
    });
    widget.onReady(null);
  }

  void _typedChanged(String text) {
    final target = widget.ex.text!;
    widget.onReady(text.trim().isEmpty ? null : () => matchSpoken(target, [text], lenient: false).passed);
  }

  @override
  void dispose() {
    _typed.dispose();
    _turn.cancel();
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
        if (_typing) ...[
          TextField(
            key: const Key('speak-type-field'),
            controller: _typed,
            enabled: !widget.locked,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Cümleyi yaz',
              helperText: 'Mikrofon olmadan da aynı ilerlemeyi alırsın.',
            ),
            onChanged: _typedChanged,
          ),
          const SizedBox(height: 16),
          if (!widget.locked) SpeakSkipButton(failures: _failures, onSkip: widget.onSkip),
        ] else ...[
          Center(
            child: MicButton(listening: _listening, onTap: widget.locked ? null : _toggle),
          ),
          const SizedBox(height: 8),
          if (_listening && _handsFree) ...[const ListeningIndicator(), const SizedBox(height: 6)],
          if (_noSpeech && !_listening && !widget.locked) ...[
            NoSpeechHint(onRetry: () => _autoListen()),
            const SizedBox(height: 6),
          ],
          if (!_listening && match != null && match.heard.isNotEmpty) ...[
            SpokenWordsView(match: match),
            const SizedBox(height: 6),
            if (_score case final score? when !score.allClear) ...[
              PronunciationScoreCard(feedback: score),
              const SizedBox(height: 6),
            ],
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
              style: TextStyle(
                color: _listening && _heard.isNotEmpty ? Brand.ink : Brand.muted,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!widget.locked) ...[
            Center(
              child: TextButton.icon(
                key: const Key('speak-type'),
                icon: const Icon(Icons.keyboard_rounded),
                label: const Text('Yazarak cevapla'),
                onPressed: _startTyping,
              ),
            ),
            SpeakSkipButton(failures: _failures, onSkip: widget.onSkip),
          ],
        ],
      ],
    );
  }
}
