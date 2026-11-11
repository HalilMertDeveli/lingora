import 'package:flutter/material.dart';

import '../models/course.dart';
import '../theme.dart';
import '../ui/markdown_text.dart';
import 'common.dart';

/// Option letters of exam-style questions (A–E).
const choiceLetters = ['A', 'B', 'C', 'D', 'E'];

/// Exam-style multiple choice (LGS: 4 options, YDS: 5). A long reading text
/// scrolls in its own box so the question and options stay in reach. After
/// "Kontrol et" the right option turns green and a wrong pick red; the
/// Turkish explanation is shown in the feedback panel ([ChoiceExplanation]).
class ChoiceExercise extends StatefulWidget {
  const ChoiceExercise({super.key, required this.ex, required this.locked, required this.onReady});
  final Exercise ex;
  final bool locked;
  final ReadyCallback onReady;

  @override
  State<ChoiceExercise> createState() => _ChoiceExerciseState();
}

class _ChoiceExerciseState extends State<ChoiceExercise> {
  int? _picked;
  final _passageScroll = ScrollController();

  @override
  void dispose() {
    _passageScroll.dispose();
    super.dispose();
  }

  void _pick(int i) {
    if (widget.locked) return;
    setState(() => _picked = i);
    widget.onReady(() => _picked == widget.ex.answerIndex);
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.ex;
    final p = context.palette;
    final kid = context.isKid;
    final passage = ex.passage?.trim() ?? '';
    final screen = MediaQuery.sizeOf(context).height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (passage.isNotEmpty) ...[
          Container(
            key: const Key('choice-passage'),
            constraints: BoxConstraints(maxHeight: screen * 0.34),
            decoration: BoxDecoration(
              color: Color.alphaBlend(p.primary.withValues(alpha: p.isDark ? 0.10 : 0.05), p.card),
              borderRadius: BorderRadius.circular(kid ? Radii.xl : Radii.lg),
              border: Border.all(color: p.line),
            ),
            child: Scrollbar(
              controller: _passageScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _passageScroll,
                padding: const EdgeInsets.fromLTRB(16, 14, 18, 14),
                child: PassageText(passage, fontSize: kid ? 17 : 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          ex.question ?? '',
          key: const Key('choice-question'),
          style: TextStyle(fontSize: kid ? 20 : 18, fontWeight: FontWeight.w700, height: 1.4, color: p.ink),
        ),
        const SizedBox(height: 18),
        for (final (i, option) in ex.options.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Option(
              key: Key('choice-option-$i'),
              letter: choiceLetters[i % choiceLetters.length],
              text: option,
              state: _stateOf(i),
              onTap: widget.locked ? null : () => _pick(i),
            ),
          ),
      ],
    );
  }

  _OptionState _stateOf(int i) {
    if (!widget.locked) return _picked == i ? _OptionState.picked : _OptionState.idle;
    if (i == widget.ex.answerIndex) return _OptionState.right;
    if (i == _picked) return _OptionState.wrong;
    return _OptionState.idle;
  }
}

enum _OptionState { idle, picked, right, wrong }

class _Option extends StatelessWidget {
  const _Option({super.key, required this.letter, required this.text, required this.state, this.onTap});
  final String letter;
  final String text;
  final _OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = switch (state) {
      _OptionState.right => p.success,
      _OptionState.wrong => p.error,
      _ => p.primary,
    };
    final marked = state != _OptionState.idle;
    return TapCard(
      selected: marked,
      color: color,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: marked ? color : p.surface,
              shape: BoxShape.circle,
              border: Border.all(color: marked ? color : p.line, width: 1.5),
            ),
            child: switch (state) {
              _OptionState.right => Icon(Icons.check_rounded, size: 20, color: onColor(color)),
              _OptionState.wrong => Icon(Icons.close_rounded, size: 20, color: onColor(color)),
              _ => Text(
                letter,
                style: TextStyle(fontWeight: FontWeight.w900, color: marked ? onColor(color) : p.muted),
              ),
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3, color: p.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Turkish explanation of a choice exercise, inside the feedback panel.
class ChoiceExplanation extends StatelessWidget {
  const ChoiceExplanation({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const Key('choice-explanation'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.card.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.menu_book_rounded, size: 18, color: p.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(height: 1.4, color: p.ink)),
          ),
        ],
      ),
    );
  }
}
