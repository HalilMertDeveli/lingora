import 'package:flutter/material.dart';

import '../theme.dart';
import 'motion.dart';

/// Renders the small markdown subset of topic guides (exam paths):
/// `## heading`, `### subheading`, `- bullet`, `> tip`, `**bold**` and
/// blank-line paragraphs. Anything else is shown as plain text.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.source, {super.key});
  final String source;

  @override
  Widget build(BuildContext context) {
    final blocks = parseMarkdown(source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final b in blocks) _block(context, b)],
    );
  }

  Widget _block(BuildContext context, MdBlock b) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final body = TextStyle(fontSize: context.isKid ? 17 : 16, height: 1.5, color: p.ink);
    return switch (b.kind) {
      MdKind.h2 => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text.rich(_inline(b.text, t.titleLarge ?? body), key: const Key('md-h2')),
      ),
      MdKind.h3 => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text.rich(_inline(b.text, t.titleMedium ?? body)),
      ),
      MdKind.bullet => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 9, right: 10),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: p.primary, shape: BoxShape.circle),
              ),
            ),
            Expanded(child: Text.rich(_inline(b.text, body))),
          ],
        ),
      ),
      MdKind.tip => Container(
        key: const Key('md-tip'),
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(p.accent.withValues(alpha: p.isDark ? 0.18 : 0.14), p.card),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border(left: BorderSide(color: p.accent, width: 4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_rounded, size: 20, color: edgeOf(p.accent)),
            const SizedBox(width: 8),
            Expanded(child: Text.rich(_inline(b.text, body))),
          ],
        ),
      ),
      MdKind.paragraph => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(_inline(b.text, body)),
      ),
    };
  }

  /// `**bold**` spans inside a line.
  static TextSpan _inline(String text, TextStyle style) {
    final parts = text.split('**');
    return TextSpan(
      style: style,
      children: [
        for (final (i, part) in parts.indexed)
          if (part.isNotEmpty)
            TextSpan(
              text: part,
              style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w800) : null,
            ),
      ],
    );
  }
}

enum MdKind { h2, h3, bullet, tip, paragraph }

class MdBlock {
  const MdBlock(this.kind, this.text);
  final MdKind kind;
  final String text;

  @override
  String toString() => '${kind.name}: $text';
}

/// Splits [source] into blocks. Consecutive plain lines join into one
/// paragraph and consecutive `>` lines into one tip.
List<MdBlock> parseMarkdown(String source) {
  final out = <MdBlock>[];
  final buffer = <String>[];
  MdKind? open;
  void flush() {
    if (open != null && buffer.isNotEmpty) out.add(MdBlock(open!, buffer.join(' ')));
    buffer.clear();
    open = null;
  }

  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      flush();
    } else if (line.startsWith('### ')) {
      flush();
      out.add(MdBlock(MdKind.h3, line.substring(4).trim()));
    } else if (line.startsWith('## ') || line.startsWith('# ')) {
      flush();
      out.add(MdBlock(MdKind.h2, line.substring(line.indexOf(' ') + 1).trim()));
    } else if (line.startsWith('- ') || line.startsWith('* ')) {
      flush();
      out.add(MdBlock(MdKind.bullet, line.substring(2).trim()));
    } else if (line.startsWith('>')) {
      if (open != MdKind.tip) flush();
      open = MdKind.tip;
      buffer.add(line.substring(1).trim());
    } else {
      if (open != MdKind.paragraph) flush();
      open = MdKind.paragraph;
      buffer.add(line);
    }
  }
  flush();
  return out;
}
