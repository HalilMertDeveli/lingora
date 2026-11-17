import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/spoken_match.dart';
import '../models/course.dart';
import '../services/speech.dart';
import '../theme.dart';
import 'common.dart';
import 'speak_mic.dart';

/// Share of the sentence's words that must be recognized when shadowing
/// (lower than speak's 0.7: the learner keeps pace with the audio).
const shadowPassRatio = 0.6;

/// Shadowing (curriculum §3, `shadow`): listen with the text hidden, listen
/// with the text, then say it right after the audio (delayed repetition), at
/// the same pace and stress. Without a microphone
/// the learner can skip it, with no penalty.
class ShadowExercise extends ConsumerStatefulWidget {
  const ShadowExercise({
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
  ConsumerState<ShadowExercise> createState() => _ShadowExerciseState();
}

class _ShadowExerciseState extends ConsumerState<ShadowExercise> {
  late final SpeechService _speech = ref.read(speechProvider);

  /// 0: listen (text hidden), 1: listen with text, 2: say it along.
  int _step = 0;
  bool _listening = false;
  bool _unavailable = false;
  String _heard = '';
  SpokenMatch? _match;
  int _failures = 0;

  void _play() => _speech.say(widget.ex.text!, rate: widget.ex.rate);

  Future<void> _record() async {
    if (_listening) {
      await _speech.stopListening();
      return;
    }
    if (!await _speech.canListen) {
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
    await _speech.listenTo(
      widget.ex.text!,
      onWords: (w) {
        if (mounted) setState(() => _heard = w);
      },
      onDone: () {
        if (!mounted) return;
        final match = matchSpoken(widget.ex.text!, [_heard]);
        final good = match.heard.isNotEmpty && (match.passed || match.score >= shadowPassRatio);
        setState(() {
          _listening = false;
          _match = match;
          if (!good) _failures++;
        });
        widget.onReady(match.heard.isEmpty ? null : () => good);
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
    final t = Theme.of(context).textTheme;
    const steps = ['1. Dinle', '2. Metinle dinle', '3. Hemen ardından söyle'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExerciseTitle('Gölgeleme'),
        Row(
          children: [
            for (final (i, s) in steps.indexed)
              Expanded(
                child: Text(
                  s,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: i == _step ? Brand.primary : Brand.muted,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: SpeakerButton(text: ex.text!, size: 72, rate: ex.rate),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _step == 0
              ? Text(
                  'Önce metni görmeden dinle. Anlamaya çalış.',
                  key: const ValueKey('hidden'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Brand.muted),
                )
              : Column(
                  key: const ValueKey('text'),
                  children: [
                    Text(
                      ex.text!,
                      key: const Key('shadow-text'),
                      textAlign: TextAlign.center,
                      style: t.titleLarge,
                    ),
                    if (ex.translation != null)
                      Text(
                        ex.translation!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Brand.muted),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        if (_step < 2)
          OutlinedButton(
            key: const Key('shadow-next'),
            onPressed: widget.locked
                ? null
                : () {
                    setState(() => _step++);
                    _play();
                  },
            child: Text(_step == 0 ? 'Metni göster ve tekrar dinle' : 'Şimdi sıra sende'),
          )
        else ...[
          Text(
            'Sesi dinle, biter bitmez mikrofona dokun ve aynı hızla, aynı vurguyla söyle.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.muted),
          ),
          Center(
            child: TextButton.icon(
              key: const Key('shadow-replay'),
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Bir daha dinle'),
              onPressed: widget.locked || _listening ? null : _play,
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: MicButton(
              listening: _listening,
              size: 84,
              inkKey: const Key('shadow-mic'),
              onTap: widget.locked ? null : _record,
            ),
          ),
          if (!_listening && (_match?.heard.isNotEmpty ?? false)) SpokenWordsView(match: _match!),
          const SizedBox(height: 8),
          ValueListenableBuilder<String?>(
            valueListenable: speechIssue,
            builder: (context, issue, _) => Text(
              spokenStatus(
                listening: _listening,
                heard: _heard,
                match: _match,
                issue: issue ?? (_unavailable ? SpeechIssues.noRecognizer : null),
                idle: '',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (!widget.locked) SpeakSkipButton(failures: _failures, onSkip: widget.onSkip),
      ],
    );
  }
}
