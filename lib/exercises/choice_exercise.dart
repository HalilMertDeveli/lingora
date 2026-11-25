import 'package:flutter/material.dart';

import '../data/option_glosses.dart';
import '../models/course.dart';
import '../theme.dart';
import '../ui/markdown_text.dart';
import 'common.dart';
import 'option_gloss.dart';

/// Option letters of exam-style questions (A–E).
const choiceLetters = ['A', 'B', 'C', 'D', 'E'];

/// Exam-style multiple choice (LGS: 4 options, YDS: 5). A long reading text
/// scrolls in its own box so the question and options stay in reach. After
/// "Kontrol et" the right option turns green and a wrong pick red; the
/// Turkish explanation is shown in the feedback panel ([ChoiceExplanation]).
/// With a [gloss], after a wrong answer only, every option gets its Turkish
/// under it ("Neden yanlış?", open; can be folded). A right answer shows none.
class ChoiceExercise extends StatefulWidget {
  const ChoiceExercise({
    super.key,
    required this.ex,
    required this.locked,
    required this.onReady,
    this.gloss,
    this.glossLocked = false,
    this.onPicked,
    this.eliminated = const {},
    this.wink,
    this.lastPicked,
  });
  final Exercise ex;

  /// On a retried test, the option that "winks" (glows twice) when a question
  /// missed before comes back: the right one, as a nudge. Null = no wink.
  final int? wink;

  /// On a retried test, the wrong option picked on this question last time
  /// ("Geçen sefer bunu seçmiştin").
  final int? lastPicked;

  /// Wrong options greyed out on a retried test (lib/data/test_retry.dart):
  /// crossed out and not tappable.
  final Set<int> eliminated;

  /// The option index the learner tapped (for the notebook's "Senin cevabın").
  final ValueChanged<int>? onPicked;

  /// Turkish of the options, shown once answered (see [OptionGloss]).
  final OptionGloss? gloss;

  /// The day's free "Neden yanlış?" explanations are used up (WhyWrongQuota):
  /// after a wrong answer a blurred preview and the Premium card show
  /// instead of the [gloss].
  final bool glossLocked;
  final bool locked;
  final ReadyCallback onReady;

  @override
  State<ChoiceExercise> createState() => _ChoiceExerciseState();
}

class _ChoiceExerciseState extends State<ChoiceExercise> {
  int? _picked;

  /// The learner's choice of showing the glosses; null = the default.
  bool? _glossOpen;
  final _passageScroll = ScrollController();

  @override
  void dispose() {
    _passageScroll.dispose();
    super.dispose();
  }

  void _pick(int i) {
    if (widget.locked) return;
    setState(() => _picked = i);
    widget.onPicked?.call(i);
    widget.onReady(() => _picked == widget.ex.answerIndex);
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.ex;
    final p = context.palette;
    final kid = context.isKid;
    final passage = ex.passage?.trim() ?? '';
    final screen = MediaQuery.sizeOf(context).height;
    final wrongWithGloss = widget.locked && widget.gloss != null && _picked != ex.answerIndex;
    final showGloss = wrongWithGloss && !widget.glossLocked;
    final glossOpen = _glossOpen ?? true;
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
        if (showGloss) ...[
          OptionGlossToggle(open: glossOpen, onChanged: (v) => setState(() => _glossOpen = v)),
          const SizedBox(height: 10),
        ],
        // Locked: the basic reason and the Premium card sit under the
        // explanation in the feedback panel (LessonScreen), not here.
        for (final (i, option) in ex.options.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Option(
              key: Key('choice-option-$i'),
              letter: choiceLetters[i % choiceLetters.length],
              text: option,
              state: _stateOf(i),
              gloss: showGloss && glossOpen
                  ? optionGlossFor(widget.gloss, i, answer: ex.answerIndex ?? -1, picked: _picked)
                  : null,
              eliminated: widget.eliminated.contains(i) && _stateOf(i) == _OptionState.idle,
              wink: !widget.locked && widget.wink == i,
              lastPick: !widget.locked && widget.lastPicked == i && widget.lastPicked != ex.answerIndex,
              onTap: widget.locked || widget.eliminated.contains(i) ? null : () => _pick(i),
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
  const _Option({
    super.key,
    required this.letter,
    required this.text,
    required this.state,
    this.onTap,
    this.gloss,
    this.eliminated = false,
    this.wink = false,
    this.lastPick = false,
  });
  final String letter;

  /// Glows twice to nudge the learner (see [ChoiceExercise.wink]).
  final bool wink;

  /// Marked "Geçen sefer bunu seçmiştin".
  final bool lastPick;
  final String text;

  /// Greyed out on a retried test ("2 şık elendi").
  final bool eliminated;

  /// Turkish of the option, under its text.
  final Widget? gloss;
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
    final card = TapCard(
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
              _OptionState.right => Icon(
                Icons.check_rounded,
                size: 20,
                color: onColor(color),
                semanticLabel: 'Doğru',
              ),
              _OptionState.wrong => Icon(
                Icons.close_rounded,
                size: 20,
                color: onColor(color),
                semanticLabel: 'Yanlış',
              ),
              _ => Text(
                letter,
                style: TextStyle(fontWeight: FontWeight.w900, color: marked ? onColor(color) : p.muted),
              ),
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: p.ink,
                      decoration: eliminated ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (lastPick)
                    Padding(
                      key: const Key('choice-last-pick'),
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Geçen sefer bunu seçmiştin',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.error),
                      ),
                    ),
                  ?gloss,
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (wink) return OptionWink(child: card);
    if (!eliminated) return card;
    return Semantics(
      label: 'Elendi',
      child: Opacity(opacity: 0.4, child: card),
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

/// A soft glow that blinks twice around an option, then stays faintly lit:
/// the right option "winking" on a question missed in an earlier attempt.
/// With animations turned off it is lit at once, without blinking.
class OptionWink extends StatefulWidget {
  const OptionWink({super.key, required this.child});
  final Widget child;

  /// Whole wink: a short wait, then two blinks.
  static const duration = Duration(milliseconds: 2400);

  @override
  State<OptionWink> createState() => _OptionWinkState();
}

class _OptionWinkState extends State<OptionWink> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: OptionWink.duration);

  /// Glow strength: wait, blink, blink, then a faint glow that stays.
  late final Animation<double> _glow = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0), weight: 25),
    for (var i = 0; i < 2; i++) ...[
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 15,
      ),
    ],
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.45), weight: 15),
  ]).animate(_controller);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glow = context.palette.accent;
    return Semantics(
      label: 'Göz kırpan şık',
      child: AnimatedBuilder(
        animation: _glow,
        child: widget.child,
        builder: (context, child) {
          final t = _glow.value;
          return Container(
            key: const Key('choice-wink'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: glow.withValues(alpha: t), width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: glow.withValues(alpha: 0.5 * t),
                  blurRadius: 14 * t,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: child,
          );
        },
      ),
    );
  }
}
