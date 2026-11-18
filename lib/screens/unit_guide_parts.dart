import 'package:flutter/material.dart';

import '../models/course.dart';
import '../theme.dart';
import '../ui/guide_view.dart';
import '../ui/markdown_text.dart' show readableOn;

/// "English — Türkçe" rows with a coloured dot, separated by thin lines
/// (the unit guide's "Anahtar ifadeler" card).
class PhraseList extends StatelessWidget {
  const PhraseList({super.key, required this.phrases});
  final List<(String, String)> phrases;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dot = guideLook(GuideTopic.words, p).color;
    final size = context.isKid ? 17.0 : 16.0;
    return Column(
      children: [
        for (final (i, (en, tr)) in phrases.indexed) ...[
          if (i > 0) Divider(height: 1, color: p.line),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: size * 0.75 - 4, right: 10),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                ),
                Expanded(
                  child: Text(
                    en,
                    style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: p.ink, height: 1.4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr,
                    style: TextStyle(fontSize: size - 1, color: p.muted, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A unit's lessons as numbered steps: done ones with a tick, open ones
/// numbered, locked ones greyed out with a lock.
class NodeSteps extends StatelessWidget {
  const NodeSteps({super.key, required this.nodes, required this.stateOf, required this.iconOf});
  final List<PathNode> nodes;

  /// 0 = locked, 1 = open, 2 = done.
  final int Function(PathNode) stateOf;
  final IconData Function(PathNode) iconOf;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = guideLook(GuideTopic.steps, p).color;
    final ink = readableOn(accent, dark: p.isDark);
    final size = context.isKid ? 17.0 : 16.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, n) in nodes.indexed)
          Padding(
            key: Key('unit-step-${n.id}'),
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _circle(p, accent, ink, stateOf(n), i + 1),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(iconOf(n), size: 16, color: p.muted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                n.title,
                                style: TextStyle(
                                  fontSize: size,
                                  fontWeight: FontWeight.w700,
                                  color: stateOf(n) == 0 ? p.muted : p.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (n.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            n.description,
                            style: TextStyle(fontSize: size - 2, color: p.muted, height: 1.35),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _circle(Palette p, Color accent, Color ink, int state, int number) {
    final locked = state == 0;
    final done = state == 2;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: locked
            ? p.surface
            : done
            ? accent
            : Color.alphaBlend(accent.withValues(alpha: p.isDark ? 0.24 : 0.14), p.card),
        border: Border.all(color: locked ? p.line : accent, width: 1.5),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: 18, color: onColor(accent))
          : locked
          ? Icon(Icons.lock_outline_rounded, size: 16, color: p.muted)
          : Text(
              '$number',
              style: TextStyle(color: ink, fontWeight: FontWeight.w900, fontSize: 14),
            ),
    );
  }
}
