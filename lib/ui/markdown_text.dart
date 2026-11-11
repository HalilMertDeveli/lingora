import 'package:flutter/material.dart';

import '../theme.dart';
import 'motion.dart';

/// Renders the small markdown subset of topic guides and reading passages
/// (exam paths): `## heading`, `### subheading`, `- bullet`, `1. numbered`,
/// `> tip`, `| table |`, `**bold**`, `*italic*` and blank-line paragraphs.
/// Lines of one paragraph keep their line breaks (dialogues). Anything else
/// is shown as plain text.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.source, {super.key, this.fontSize});
  final String source;

  /// Body text size; 16 (17 in Çocuk modu) by default.
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final blocks = parseMarkdown(source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final (i, b) in blocks.indexed) _block(context, b, first: i == 0)],
    );
  }

  Widget _block(BuildContext context, MdBlock b, {required bool first}) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final body = TextStyle(fontSize: fontSize ?? (context.isKid ? 17 : 16), height: 1.5, color: p.ink);
    return switch (b.kind) {
      MdKind.h2 => Padding(
        padding: EdgeInsets.only(top: first ? 4 : 18, bottom: 6),
        child: Text.rich(_inline(b.text, t.titleLarge ?? body), key: const Key('md-h2')),
      ),
      MdKind.h3 => Padding(
        padding: EdgeInsets.only(top: first ? 2 : 12, bottom: 4),
        child: Text.rich(_inline(b.text, t.titleMedium ?? body)),
      ),
      MdKind.bullet || MdKind.numbered => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (b.kind == MdKind.numbered)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${b.number}.',
                  style: body.copyWith(fontWeight: FontWeight.w800, color: p.primary),
                ),
              )
            else
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
        margin: const EdgeInsets.symmetric(vertical: 6),
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
      MdKind.table => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _table(context, b.rows, body),
      ),
      MdKind.paragraph => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(_inline(b.text, body)),
      ),
    };
  }

  /// A table that fits the width: every column shares it, cells wrap.
  Widget _table(BuildContext context, List<List<String>> rows, TextStyle body) {
    final p = context.palette;
    final columns = rows.fold(0, (m, r) => r.length > m ? r.length : m);
    final cell = body.copyWith(fontSize: (body.fontSize ?? 16) - 2, height: 1.35);
    return ClipRRect(
      key: const Key('md-table'),
      borderRadius: BorderRadius.circular(Radii.md),
      child: Table(
        border: TableBorder.symmetric(inside: BorderSide(color: p.line)),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          for (final (i, r) in rows.indexed)
            TableRow(
              decoration: BoxDecoration(
                color: i == 0
                    ? Color.alphaBlend(p.primary.withValues(alpha: p.isDark ? 0.22 : 0.12), p.card)
                    : (i.isEven ? Color.alphaBlend(p.line.withValues(alpha: 0.35), p.card) : p.card),
              ),
              children: [
                for (var c = 0; c < columns; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: Text.rich(
                      _inline(
                        c < r.length ? r[c] : '',
                        i == 0 ? cell.copyWith(fontWeight: FontWeight.w800) : cell,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static final _emphasis = RegExp(r'\*\*(.+?)\*\*|\*([^*\s][^*]*?)\*');

  /// `**bold**` and `*italic*` spans inside a block.
  static TextSpan _inline(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _emphasis.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(
        m.group(1) != null
            ? TextSpan(
                text: m.group(1),
                style: const TextStyle(fontWeight: FontWeight.w800),
              )
            : TextSpan(
                text: m.group(2),
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
      );
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: spans);
  }
}

/// A reading passage: plain text keeps its line breaks; a passage with a
/// table (`| … |` lines) or markdown is drawn with [MarkdownText].
class PassageText extends StatelessWidget {
  const PassageText(this.text, {super.key, this.fontSize = 16});
  final String text;
  final double fontSize;

  static bool _rich(String s) => RegExp(r'^\s*(\||#{2,3} |\*\*)', multiLine: true).hasMatch(s);

  @override
  Widget build(BuildContext context) => _rich(text)
      ? MarkdownText(text, fontSize: fontSize)
      : Text(
          text,
          style: TextStyle(fontSize: fontSize, height: 1.5, color: context.palette.ink),
        );
}

enum MdKind { h2, h3, bullet, numbered, tip, table, paragraph }

class MdBlock {
  const MdBlock(this.kind, this.text, {this.number = 0, this.rows = const []});
  final MdKind kind;
  final String text;

  /// Number of a numbered item.
  final int number;

  /// Cells of a table, header first (separator line dropped).
  final List<List<String>> rows;

  @override
  String toString() => '${kind.name}: $text';
}

final _numbered = RegExp(r'^(\d+)[.)] (.*)$');
final _separator = RegExp(r'^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$');

List<String> _cells(String line) {
  var l = line.trim();
  if (l.startsWith('|')) l = l.substring(1);
  if (l.endsWith('|')) l = l.substring(0, l.length - 1);
  return [for (final c in l.split('|')) c.trim()];
}

/// Splits [source] into blocks. Consecutive plain lines form one paragraph
/// (line breaks kept), consecutive `>` lines one tip and consecutive `|`
/// lines one table.
List<MdBlock> parseMarkdown(String source) {
  final out = <MdBlock>[];
  final buffer = <String>[];
  MdKind? open;
  void flush() {
    if (open != null && buffer.isNotEmpty) {
      out.add(switch (open!) {
        MdKind.table => MdBlock(
          MdKind.table,
          '',
          rows: [
            for (final l in buffer)
              if (!_separator.hasMatch(l)) _cells(l),
          ],
        ),
        MdKind.tip => MdBlock(MdKind.tip, buffer.join(' ')),
        _ => MdBlock(open!, buffer.join('\n')),
      });
    }
    buffer.clear();
    open = null;
  }

  void collect(MdKind kind, String line) {
    if (open != kind) flush();
    open = kind;
    buffer.add(line);
  }

  for (final raw in source.split('\n')) {
    final line = raw.trim();
    final number = _numbered.firstMatch(line);
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
    } else if (number != null) {
      flush();
      out.add(MdBlock(MdKind.numbered, number.group(2)!.trim(), number: int.parse(number.group(1)!)));
    } else if (line.startsWith('|')) {
      collect(MdKind.table, line);
    } else if (line.startsWith('>')) {
      final tip = line.substring(1).trim();
      // "> **Sınav ipucu 2:** …" starts a new tip even without a blank line.
      if (open == MdKind.tip && tip.startsWith('**')) flush();
      collect(MdKind.tip, tip);
    } else {
      collect(MdKind.paragraph, line);
    }
  }
  flush();
  return out;
}
