import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../services/speech.dart';
import '../theme.dart';
import 'common.dart';

class SelectExercise extends ConsumerStatefulWidget {
  const SelectExercise({super.key, required this.ex, required this.locked, required this.onReady});
  final Exercise ex;
  final bool locked;
  final ReadyCallback onReady;

  @override
  ConsumerState<SelectExercise> createState() => _SelectExerciseState();
}

class _SelectExerciseState extends ConsumerState<SelectExercise> {
  String? _picked;

  void _pick(Choice c) {
    if (widget.locked) return;
    setState(() => _picked = c.text);
    ref.read(speechProvider).say(c.text);
    widget.onReady(() => _picked == widget.ex.answer);
  }

  @override
  Widget build(BuildContext context) {
    final choices = stableShuffle(widget.ex.choices, widget.ex.prompt ?? widget.ex.answer ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExerciseTitle('“${widget.ex.prompt}” hangisi?'),
        // Two cards per row, as tall as their content needs: a fixed-ratio grid
        // cut "good morning" at the largest font on a 360 dp phone (QA).
        LayoutBuilder(
          builder: (context, box) {
            final minHeight = (box.maxWidth - 12) / 2 / 0.95;
            // Card width less its padding (6) and selected border (2) on each side.
            final textWidth = (box.maxWidth - 12) / 2 - 16;
            Widget card(int i) => i < choices.length
                ? _ChoiceCard(
                    choice: choices[i],
                    selected: _picked == choices[i].text,
                    textWidth: textWidth,
                    onTap: () => _pick(choices[i]),
                  )
                : const SizedBox.shrink();
            return Column(
              children: [
                for (var i = 0; i < choices.length; i += 2)
                  Padding(
                    padding: EdgeInsets.only(bottom: i + 2 < choices.length ? 12 : 0),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: minHeight),
                              child: card(i),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: card(i + 1)),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.choice,
    required this.selected,
    required this.textWidth,
    required this.onTap,
  });
  final Choice choice;
  final bool selected;
  final double textWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: selected ? Brand.primary : Brand.ink,
    );
    return TapCard(
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: selected ? 1.18 : 1,
            duration: const Duration(milliseconds: 380),
            curve: Curves.elasticOut,
            // The picture is decoration: it need not grow with the font.
            child: Text(
              choice.emoji,
              textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
              style: const TextStyle(fontSize: 56),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            choice.text,
            textAlign: TextAlign.center,
            textScaler: wholeWordScaler(context, choice.text, style, textWidth),
            style: style,
          ),
        ],
      ),
    );
  }
}
