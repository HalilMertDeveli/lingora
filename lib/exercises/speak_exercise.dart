import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pronunciation_feedback.dart';
import '../core/spoken_match.dart';
import '../models/course.dart';
import '../services/mic_access.dart';
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
  String _heard = '';
  SpokenMatch? _match;
  PronunciationFeedback? _score;
  int _failures = 0;

  /// "Yazarak cevapla": the equal path without a microphone (no permission,
  /// a noisy place, recognition failing). The typed sentence is graded with
  /// the same tolerance as speech and counts like a spoken answer.
  bool _typing = false;
  final _typed = TextEditingController();
  late final AutoListen _mic;

  bool get _listening => _mic.listening;

  @override
  void initState() {
    super.initState();
    _mic = AutoListen(
      speech: ref.read(speechProvider),
      player: ref.read(linePlayerProvider),
      mic: ref.read(micAccessProvider),
    )..addListener(_changed);
    // Hands-free: the sentence is read out, then the microphone opens.
    if (!widget.locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mic.start(target: widget.ex.text!, prompt: widget.ex.text, onHeard: _judge);
      });
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      _heard = _mic.words;
      // Speaking does not work right now: the skip is offered up front.
      if (const {ListenPhase.gaveUp, ListenPhase.unavailable, ListenPhase.blocked}.contains(_mic.phase)) {
        if (_failures < skipOfferAfter) _failures = skipOfferAfter;
      }
    });
  }

  void _again() {
    setState(() {
      _match = null;
      _score = null;
    });
    widget.onReady(null);
    _mic.again();
  }

  void _judge(String heard) {
    if (!mounted) return;
    final match = matchSpoken(widget.ex.text!, [heard]);
    setState(() {
      _heard = heard;
      _match = match;
      _score = pronunciationFeedback(widget.ex.text!, lastRecognition.value, heard: heard);
      if (!match.passed) _failures++;
    });
    widget.onReady(match.heard.isEmpty ? null : () => match.passed);
  }

  void _startTyping() {
    _mic.cancel();
    setState(() => _typing = true);
    widget.onReady(null);
  }

  void _typedChanged(String text) {
    final target = widget.ex.text!;
    widget.onReady(text.trim().isEmpty ? null : () => matchSpoken(target, [text], lenient: false).passed);
  }

  @override
  void dispose() {
    _typed.dispose();
    _mic
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.ex;
    final match = _match;
    final busy = _mic.phase == ListenPhase.listening || _mic.phase == ListenPhase.prompting;
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
          if (!widget.locked) ...[
            AutoListenStatus(listen: _mic, showWords: false),
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
                // The microphone panel already explains a missed try.
                issue: match == null ? null : issue,
                idle: '',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _listening && _heard.isNotEmpty ? Brand.ink : Brand.muted,
                fontSize: 16,
              ),
            ),
          ),
          if (!widget.locked && match != null && !busy) ...[
            const SizedBox(height: 4),
            SayAgainButton(onPressed: _again),
          ],
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
