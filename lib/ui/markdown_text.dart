import 'package:flutter/material.dart';

import '../theme.dart';

/// Renders the small markdown subset of topic guides and reading passages
/// (exam paths): `## heading`, `### subheading`, `- bullet`, `1. numbered`,
/// `> tip`, `| table |`, `**bold**`, `*italic*` and blank-line paragraphs.
/// Lines of one paragraph keep their line breaks (dialogues). Anything else
/// is shown as plain text.
///
/// With [guide] the richer guide blocks are recognised too (examples,
/// mistakes, formulas, labelled callouts, steps); topic guides use
/// [GuideView] in `guide_view.dart`, which also splits them into section
/// cards.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.source, {super.key, this.fontSize, this.guide = false, this.color});
  final String source;

  /// Body text size; 16 (17 in Çocuk modu) by default.
  final double? fontSize;

  /// Recognise guide blocks (see [parseMarkdown]).
  final bool guide;

  /// Accent colour for dots, steps and bold words; primary by default.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final blocks = parseMarkdown(source, guide: guide);
    return MdBlocksView(blocks: blocks, color: color ?? context.palette.primary, fontSize: fontSize);
  }
}

/// A list of parsed blocks drawn one under the other. Consecutive numbered
/// items become one "Adım 1, 2 …" step list.
class MdBlocksView extends StatelessWidget {
  const MdBlocksView({
    super.key,
    required this.blocks,
    required this.color,
    this.fontSize,
    this.steps = false,
  });
  final List<MdBlock> blocks;

  /// Accent colour of the section (dots, numbers, bold words, table header).
  final Color color;
  final double? fontSize;

  /// Label numbered items "Adım n" (step-by-step sections).
  final bool steps;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.kind == MdKind.numbered) {
        final run = <MdBlock>[];
        while (i < blocks.length && blocks[i].kind == MdKind.numbered) {
          run.add(blocks[i++]);
        }
        i--;
        children.add(_StepList(items: run, style: _style(context), labelled: steps));
        continue;
      }
      children.add(_MdBlockView(block: b, style: _style(context), first: i == 0));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  MdStyle _style(BuildContext context) => MdStyle.of(context, color, fontSize);
}

/// Colours and text styles shared by the blocks of one section.
class MdStyle {
  const MdStyle({
    required this.p,
    required this.accent,
    required this.accentText,
    required this.body,
    required this.radius,
  });
  final Palette p;

  /// Section colour (icons, dots, borders).
  final Color accent;

  /// Section colour readable as text on the card.
  final Color accentText;
  final TextStyle body;
  final double radius;

  static MdStyle of(BuildContext context, Color accent, double? fontSize) {
    final p = context.palette;
    final kid = context.isKid;
    return MdStyle(
      p: p,
      accent: accent,
      accentText: readableOn(accent, dark: p.isDark),
      body: TextStyle(fontSize: fontSize ?? (kid ? 17 : 16), height: 1.5, color: p.ink),
      radius: context.lingora.cardRadius,
    );
  }

  double get size => body.fontSize ?? 16;
  TextStyle get small => body.copyWith(fontSize: size - 1.5, height: 1.45);

  /// [c] as a soft fill on the card.
  Color tint(Color c, [double light = 0.10, double dark = 0.18]) =>
      Color.alphaBlend(c.withValues(alpha: p.isDark ? dark : light), p.card);
}

/// [c] darkened (light theme) or lightened (dark theme) until text in it
/// reads well on a card.
Color readableOn(Color c, {required bool dark}) {
  final h = HSLColor.fromColor(c);
  final l = dark ? (h.lightness < 0.72 ? 0.72 : h.lightness) : (h.lightness > 0.38 ? 0.38 : h.lightness);
  return h.withLightness(l).toColor();
}

class _MdBlockView extends StatelessWidget {
  const _MdBlockView({required this.block, required this.style, required this.first});
  final MdBlock block;
  final MdStyle style;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final b = block;
    final s = style;
    final t = Theme.of(context).textTheme;
    return switch (b.kind) {
      MdKind.h2 => Padding(
        padding: EdgeInsets.only(top: first ? 4 : 18, bottom: 6),
        child: Text.rich(inlineSpan(b.text, t.titleLarge ?? s.body, s.accentText), key: const Key('md-h2')),
      ),
      MdKind.h3 => Padding(
        padding: EdgeInsets.only(top: first ? 2 : 12, bottom: 6),
        child: Row(
          children: [
            Container(
              width: 4,
              height: s.size + 2,
              decoration: BoxDecoration(color: s.accent, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                inlineSpan(
                  b.text,
                  (t.titleMedium ?? s.body).copyWith(fontWeight: FontWeight.w800),
                  s.accentText,
                ),
              ),
            ),
          ],
        ),
      ),
      MdKind.bullet => _Bullet(block: b, style: s),
      MdKind.numbered => _StepList(items: [b], style: s, labelled: false),
      MdKind.tip => _Callout(block: b, style: s),
      MdKind.quote => _Quote(block: b, style: s),
      MdKind.example => _Example(en: b.text, tr: b.translation, style: s),
      MdKind.mistake => _Mistake(block: b, style: s),
      MdKind.pattern => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: PatternChips(parts: b.parts, joiner: b.joiner, style: s),
      ),
      MdKind.table => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _Table(rows: b.rows, style: s),
      ),
      MdKind.paragraph => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text.rich(inlineSpan(b.text, s.body, s.accentText)),
      ),
    };
  }
}

/// A bullet with a coloured dot. A leading `**formula + parts**:` is drawn
/// as pattern chips above its meaning, and a trailing "Örnek: …" as a small
/// example line under it.
class _Bullet extends StatelessWidget {
  const _Bullet({required this.block, required this.style});
  final MdBlock block;
  final MdStyle style;

  @override
  Widget build(BuildContext context) {
    final s = style;
    final b = block;
    Widget content = Text.rich(inlineSpan(b.text, s.body, s.accentText));
    if (b.parts.isNotEmpty) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PatternChips(parts: b.parts, joiner: b.joiner, style: s),
          if (b.text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text.rich(inlineSpan(b.text, s.body, s.accentText)),
          ],
        ],
      );
    }
    return Padding(
      key: const Key('md-bullet'),
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: s.size * 0.75 - 4, right: 10),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: s.accent, shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                if (b.example.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _Example(en: b.example, tr: '', style: s, compact: true),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Numbered items as steps: a numbered circle on a line that links them,
/// "Adım n" above each one when [labelled].
class _StepList extends StatelessWidget {
  const _StepList({required this.items, required this.style, required this.labelled});
  final List<MdBlock> items;
  final MdStyle style;
  final bool labelled;

  @override
  Widget build(BuildContext context) {
    final s = style;
    final d = s.size + 12;
    return Padding(
      key: const Key('md-steps'),
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, b) in items.indexed)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: d,
                    child: Column(
                      children: [
                        Container(
                          key: Key('md-step-${b.number}'),
                          width: d,
                          height: d,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: s.accent, shape: BoxShape.circle),
                          child: Text(
                            '${b.number}',
                            style: TextStyle(
                              color: onColor(s.accent),
                              fontWeight: FontWeight.w900,
                              fontSize: s.size - 2,
                            ),
                          ),
                        ),
                        if (i < items.length - 1)
                          Expanded(child: Container(width: 2, color: s.accent.withValues(alpha: 0.35))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: i < items.length - 1 ? 12 : 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (labelled)
                            Text(
                              'ADIM ${b.number}',
                              style: TextStyle(
                                color: s.accentText,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          Padding(
                            padding: EdgeInsets.only(top: labelled ? 1 : (d - s.size * 1.5) / 2),
                            child: Text.rich(inlineSpan(b.text, s.body, s.accentText)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Visual of a callout kind.
({Color color, IconData icon, String title}) calloutLook(CalloutTone tone, Palette p) => switch (tone) {
  CalloutTone.tip => (color: p.accent, icon: Icons.lightbulb_rounded, title: 'İpucu'),
  CalloutTone.warning => (color: p.error, icon: Icons.warning_amber_rounded, title: 'Dikkat'),
  CalloutTone.rule => (color: p.tone(const Color(0xFF7B5BE6)), icon: Icons.rule_rounded, title: 'Kural'),
  CalloutTone.note => (color: p.info, icon: Icons.info_outline_rounded, title: 'Not'),
  CalloutTone.example => (color: p.success, icon: Icons.chat_bubble_outline_rounded, title: 'Örnek'),
};

/// "İpucu", "Dikkat", "Kural", "Not" or "Örnek" box: tinted, with an icon
/// and the label as its title.
class _Callout extends StatelessWidget {
  const _Callout({required this.block, required this.style});
  final MdBlock block;
  final MdStyle style;

  @override
  Widget build(BuildContext context) {
    final s = style;
    final look = calloutLook(block.tone, s.p);
    final ink = readableOn(look.color, dark: s.p.isDark);
    final title = block.label.isEmpty ? look.title : block.label;
    return Container(
      key: Key('md-callout-${block.tone.name}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: s.tint(look.color, 0.12, 0.16),
        borderRadius: BorderRadius.circular(s.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(look.icon, size: 20, color: ink),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: ink, fontWeight: FontWeight.w900, fontSize: s.size - 1),
                ),
              ),
            ],
          ),
          if (block.text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text.rich(inlineSpan(block.text, s.body, ink)),
          ],
        ],
      ),
    );
  }
}

/// A model text or quoted message: a calm box that keeps line breaks.
class _Quote extends StatelessWidget {
  const _Quote({required this.block, required this.style});
  final MdBlock block;
  final MdStyle style;

  @override
  Widget build(BuildContext context) {
    final s = style;
    return Container(
      key: const Key('md-quote'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: s.p.surface,
        borderRadius: BorderRadius.circular(s.radius),
        border: Border(left: BorderSide(color: s.accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote_rounded, size: 22, color: s.accentText),
          Text.rich(inlineSpan(block.text, s.small, s.accentText)),
        ],
      ),
    );
  }
}

/// An English example with its Turkish meaning, highlighted.
class _Example extends StatelessWidget {
  const _Example({required this.en, required this.tr, required this.style, this.compact = false});
  final String en;
  final String tr;
  final MdStyle style;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = style;
    final green = s.p.success;
    final ink = readableOn(green, dark: s.p.isDark);
    return Container(
      key: const Key('md-example'),
      margin: EdgeInsets.symmetric(vertical: compact ? 0 : 4),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 6 : 10),
      decoration: BoxDecoration(
        color: s.tint(green, 0.10, 0.16),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border(left: BorderSide(color: green, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: Icon(Icons.record_voice_over_rounded, size: compact ? 16 : 18, color: ink),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  inlineSpan(
                    en,
                    (compact ? s.small : s.body).copyWith(fontWeight: FontWeight.w600),
                    ink,
                    false,
                  ),
                ),
                if (tr.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text.rich(inlineSpan(tr, s.small.copyWith(color: s.p.muted), ink)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ❌ wrong → ✅ right (and why).
class _Mistake extends StatelessWidget {
  const _Mistake({required this.block, required this.style});
  final MdBlock block;
  final MdStyle style;

  @override
  Widget build(BuildContext context) {
    final s = style;
    final bad = readableOn(s.p.error, dark: s.p.isDark);
    final good = readableOn(s.p.success, dark: s.p.isDark);
    Widget line(IconData icon, Color c, String text, TextStyle st) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 8),
          child: Icon(icon, size: 18, color: c),
        ),
        Expanded(child: Text.rich(inlineSpan(text, st, c))),
      ],
    );
    return Container(
      key: const Key('md-mistake'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: s.p.card,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: s.p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (block.label.isNotEmpty) ...[
            Text.rich(inlineSpan(block.label, s.small.copyWith(fontWeight: FontWeight.w700), s.accentText)),
            const SizedBox(height: 6),
          ],
          line(
            Icons.close_rounded,
            bad,
            block.text,
            s.body.copyWith(
              color: s.p.muted,
              decoration: TextDecoration.lineThrough,
              decorationColor: bad.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          line(Icons.check_rounded, good, block.translation, s.body.copyWith(fontWeight: FontWeight.w700)),
          if (block.example.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text.rich(inlineSpan(block.example, s.small.copyWith(color: s.p.muted), s.accentText)),
          ],
        ],
      ),
    );
  }
}

/// A formula such as "Özne + am/is/are + fiil-ing" as coloured chips joined
/// by "+" (or "→" for word families).
class PatternChips extends StatelessWidget {
  const PatternChips({super.key, required this.parts, required this.style, this.joiner = '+'});
  final List<String> parts;
  final String joiner;
  final MdStyle style;

  @override
  Widget build(BuildContext context) {
    final s = style;
    return Wrap(
      key: const Key('md-pattern'),
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, part) in parts.indexed) ...[
          if (i > 0)
            Text(
              joiner,
              style: TextStyle(color: s.accentText, fontWeight: FontWeight.w900, fontSize: s.size),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: s.tint(s.accent, 0.14, 0.24),
              borderRadius: BorderRadius.circular(Radii.xl),
              border: Border.all(color: s.accent.withValues(alpha: 0.5)),
            ),
            child: Text.rich(
              inlineSpan(part, s.small.copyWith(fontWeight: FontWeight.w800, height: 1.2), s.accentText),
            ),
          ),
        ],
      ],
    );
  }
}

/// A table that fits the width: every column shares it, cells wrap. The
/// header takes the section colour; "Yanlış" / "Doğru" columns are tinted.
class _Table extends StatelessWidget {
  const _Table({required this.rows, required this.style});
  final List<List<String>> rows;
  final MdStyle style;

  @override
  Widget build(BuildContext context) {
    final s = style;
    final p = s.p;
    final columns = rows.fold(0, (m, r) => r.length > m ? r.length : m);
    final cell = s.body.copyWith(fontSize: s.size - 2, height: 1.35);
    final header = rows.isEmpty ? const <String>[] : rows.first;
    Color? columnInk(int c) {
      if (c >= header.length) return null;
      final h = header[c].toLowerCase();
      if (h.startsWith('yanlış')) return readableOn(p.error, dark: p.isDark);
      if (h.startsWith('doğru')) return readableOn(p.success, dark: p.isDark);
      return null;
    }

    return Container(
      key: const Key('md-table'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: p.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        border: TableBorder.symmetric(inside: BorderSide(color: p.line)),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          for (final (i, r) in rows.indexed)
            TableRow(
              decoration: BoxDecoration(
                color: i == 0
                    ? s.tint(s.accent, 0.16, 0.26)
                    : (i.isEven ? s.tint(p.line, 0.35, 0.35) : p.card),
              ),
              children: [
                for (var c = 0; c < columns; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: Text.rich(
                      inlineSpan(
                        c < r.length ? r[c] : '',
                        i == 0
                            ? cell.copyWith(fontWeight: FontWeight.w800, color: columnInk(c) ?? s.accentText)
                            : (columnInk(c) == null ? cell : cell.copyWith(color: columnInk(c))),
                        columnInk(c) ?? s.accentText,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

final _emphasis = RegExp(r'\*\*(.+?)\*\*|\*([^*\s][^*]*?)\*');

/// `**bold**` and `*italic*` spans inside a block. Bold words take [strong]
/// (the section colour); italics stay in the text colour.
TextSpan inlineSpan(String text, TextStyle style, [Color? strong, bool italic = true]) {
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
              style: TextStyle(fontStyle: italic ? FontStyle.italic : null),
            ),
    );
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: style, children: spans);
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

enum MdKind { h2, h3, bullet, numbered, tip, quote, example, mistake, pattern, table, paragraph }

/// Kind of a labelled box ([MdKind.tip]).
enum CalloutTone { tip, warning, rule, note, example }

class MdBlock {
  const MdBlock(
    this.kind,
    this.text, {
    this.number = 0,
    this.rows = const [],
    this.tone = CalloutTone.tip,
    this.label = '',
    this.translation = '',
    this.example = '',
    this.parts = const [],
    this.joiner = '+',
  });
  final MdKind kind;

  /// Main text. For an example the English sentence, for a mistake the
  /// wrong form.
  final String text;

  /// Number of a numbered item.
  final int number;

  /// Cells of a table, header first (separator line dropped).
  final List<List<String>> rows;

  /// Callout kind and its label as written ("Sınav ipucu 1").
  final CalloutTone tone;
  final String label;

  /// Turkish meaning of an example; the right form of a mistake.
  final String translation;

  /// "Örnek: …" of a bullet; the reason of a mistake.
  final String example;

  /// Formula chips of a pattern (or of a bullet's leading `**a + b**:`).
  final List<String> parts;
  final String joiner;

  @override
  String toString() => '${kind.name}: $text';
}

final _numbered = RegExp(r'^(\d+)[.)] (.*)$');
final _separator = RegExp(r'^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$');

/// "**1. Present simple:** …" paragraphs: numbered topics.
final _boldNumbered = RegExp(r'^\*\*(\d+)[.)]\s*(.+?)\*\*\s*(.*)$');

/// A label that starts a callout: "**Dikkat:** …", "*Örnek:* …", "Not: …".
final _label = RegExp(
  r'^(\*\*|\*)?((?:Sınav ipucu|Sınav ipuçları|Okurken ipucu|İpucu|İpuçları|Dikkat|Uyarı|Unutma|Hatırla|Kural|Yapı|Formül|Not|Örnek çözüm|Örnek soru|Örnek)(?: [0-9]{1,2})?)\s*[:.]\s*(?:\1)?\s*(.*)$',
);

/// A label alone (old style "> İpucu" tips without a colon).
final _bareLabel = RegExp(r'^(?:\*\*)?(Sınav ipucu|İpucu|Dikkat|Uyarı|Kural|Not|Unutma)\b');

CalloutTone _toneOf(String label) {
  final l = label.toLowerCase();
  if (l.startsWith('dikkat') || l.startsWith('uyarı') || l.startsWith('unutma')) return CalloutTone.warning;
  if (l.startsWith('kural') || l.startsWith('yapı') || l.startsWith('formül')) return CalloutTone.rule;
  if (l.startsWith('not') || l.startsWith('hatırla')) return CalloutTone.note;
  if (l.startsWith('örnek')) return CalloutTone.example;
  return CalloutTone.tip;
}

/// `*English sentence.* — Türkçesi.`
final _example = RegExp(r'^\*([^*].*?)\*\s+[—–]\s+(.+)$');

/// `❌ wrong ✅ right (why)` and `"wrong" → **right**: why`.
final _crossCheck = RegExp(r'^(.*?)❌\s*(.+?)\s*✅\s*(.+)$');
final _arrowFix = RegExp(
  r'^(["“].+?["”](?:\s*\(.+?\))?(?:\s+ya da\s+["“].+?["”])?)\s*→\s*\*\*(.+?)\*\*[:.]?\s*(.*)$',
);

/// `**love / like / enjoy + -ing**: meaning`.
final _leadFormula = RegExp(r'^\*\*([^*]+?\s\+\s[^*]+?)\*\*\s*:\s*(.*)$');

/// A whole line that is a formula: `Özne + am/is/are + fiil-ing`, or a word
/// family `*sustain → sustainable → sustainability*`.
(List<String>, String)? _formula(String line) {
  var l = line.trim();
  final wrapped = RegExp(r'^\*{1,2}([^*]+)\*{1,2}$').firstMatch(l);
  if (wrapped != null) l = wrapped.group(1)!.trim();
  if (l.length > 90 || RegExp(r'[.!?;:]$').hasMatch(l)) return null;
  for (final joiner in ['+', '→']) {
    final parts = [for (final p in l.split(' $joiner ')) p.trim()];
    if (parts.length >= (joiner == '+' ? 2 : 3) &&
        parts.length <= 6 &&
        parts.every((p) => p.isNotEmpty && p.length <= 32 && !p.contains(':')) &&
        (joiner != '+' || _goodParts(parts))) {
      return (parts, joiner);
    }
  }
  return null;
}

/// Formula parts that read well as chips: balanced brackets, and no
/// "a / b" alternatives in the middle of a longer chain.
bool _goodParts(List<String> parts) {
  for (final (i, p) in parts.indexed) {
    if ('('.allMatches(p).length != ')'.allMatches(p).length) return false;
    if (parts.length > 2 && i > 0 && i < parts.length - 1 && p.contains(' / ')) return false;
  }
  return true;
}

/// Guide-only reading of a bullet's or paragraph's text.
MdBlock? _guideBlock(String text, {required bool bullet}) {
  final cross = _crossCheck.firstMatch(text);
  if (cross != null) {
    final right = cross.group(3)!.replaceAll(RegExp(r'\s*✅\s*'), ' ');
    // A trailing "(why …)" goes under the right form.
    final why = RegExp(r'^(.*?)\s*(\([^()]*\))$').firstMatch(right);
    return MdBlock(
      MdKind.mistake,
      cross.group(2)!,
      label: cross.group(1)!.trim(),
      translation: why == null ? right : why.group(1)!,
      example: why?.group(2) ?? '',
    );
  }
  final arrow = _arrowFix.firstMatch(text);
  if (arrow != null) {
    return MdBlock(
      MdKind.mistake,
      arrow.group(1)!,
      translation: '**${arrow.group(2)!}**',
      example: arrow.group(3)!,
    );
  }
  final ex = _example.firstMatch(text);
  if (ex != null) return MdBlock(MdKind.example, ex.group(1)!, translation: ex.group(2)!);
  final label = _label.firstMatch(text);
  if (label != null) {
    final name = label.group(2)!;
    return MdBlock(MdKind.tip, label.group(3)!, tone: _toneOf(name), label: name);
  }
  final formula = _formula(text);
  if (formula != null) return MdBlock(MdKind.pattern, text, parts: formula.$1, joiner: formula.$2);
  if (bullet) {
    var rest = text;
    var parts = const <String>[];
    final lead = _leadFormula.firstMatch(text);
    if (lead != null) {
      final split = [for (final p in lead.group(1)!.split(' + ')) p.trim()];
      if (_goodParts(split)) {
        parts = split;
        rest = lead.group(2)!;
      }
    }
    final at = rest.indexOf(' Örnek: ');
    final example = at < 0 ? '' : rest.substring(at + 8).trim();
    if (at >= 0) rest = rest.substring(0, at).trim();
    if (parts.isNotEmpty || example.isNotEmpty) {
      return MdBlock(MdKind.bullet, rest, parts: parts, example: example);
    }
  }
  return null;
}

List<String> _cells(String line) {
  var l = line.trim();
  if (l.startsWith('|')) l = l.substring(1);
  if (l.endsWith('|')) l = l.substring(0, l.length - 1);
  return [for (final c in l.split('|')) c.trim()];
}

/// Splits [source] into blocks. Consecutive plain lines form one paragraph
/// (line breaks kept), consecutive `>` lines one tip and consecutive `|`
/// lines one table.
///
/// With [guide] it also finds examples (`*EN* — TR`), mistakes (`❌ … ✅ …`,
/// `"…" → **…**`), formulas (`Özne + fiil`), labelled callouts ("İpucu:",
/// "Dikkat:", "Kural:", "Not:", "Örnek:"), "**1. Başlık:**" paragraphs as
/// numbered items, and `>` blocks without a label as quotes (model texts)
/// that keep their line breaks. The words themselves are never changed.
List<MdBlock> parseMarkdown(String source, {bool guide = false}) {
  final out = <MdBlock>[];
  final buffer = <String>[];
  MdKind? open;

  MdBlock quoteOrTip() {
    final first = buffer.firstWhere((l) => l.isNotEmpty, orElse: () => '');
    final label = _label.firstMatch(first);
    if (!guide || label != null || _bareLabel.hasMatch(first)) {
      final text = buffer.where((l) => l.isNotEmpty).join(' ');
      if (guide && label != null) {
        final name = label.group(2)!;
        final rest = _label.firstMatch(text)!.group(3)!;
        return MdBlock(MdKind.tip, rest, tone: _toneOf(name), label: name);
      }
      return MdBlock(MdKind.tip, text);
    }
    final lines = [...buffer];
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return MdBlock(MdKind.quote, lines.join('\n'));
  }

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
        MdKind.tip => quoteOrTip(),
        MdKind.paragraph when guide => _paragraph(buffer.join('\n')),
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
      // A blank "> " line inside a quote is a paragraph break of the quote.
      flush();
    } else if (line.startsWith('### ')) {
      flush();
      out.add(MdBlock(MdKind.h3, line.substring(4).trim()));
    } else if (line.startsWith('## ') || line.startsWith('# ')) {
      flush();
      out.add(MdBlock(MdKind.h2, line.substring(line.indexOf(' ') + 1).trim()));
    } else if (line.startsWith('- ') || line.startsWith('* ')) {
      flush();
      final text = line.substring(2).trim();
      out.add((guide ? _guideBlock(text, bullet: true) : null) ?? MdBlock(MdKind.bullet, text));
    } else if (number != null) {
      flush();
      out.add(MdBlock(MdKind.numbered, number.group(2)!.trim(), number: int.parse(number.group(1)!)));
    } else if (line.startsWith('|')) {
      collect(MdKind.table, line);
    } else if (line.startsWith('>')) {
      final tip = line.substring(1).trim();
      // "> **Sınav ipucu 2:** …" starts a new tip even without a blank line.
      if (open == MdKind.tip && tip.startsWith('**') && (!guide || _label.hasMatch(tip))) flush();
      collect(MdKind.tip, tip);
    } else {
      collect(MdKind.paragraph, line);
    }
  }
  flush();
  return out;
}

/// A guide paragraph: "**1. Başlık:** …" → numbered, labelled → callout,
/// formula → chips, `*EN* — TR` → example; else a plain paragraph.
MdBlock _paragraph(String text) {
  if (!text.contains('\n')) {
    final n = _boldNumbered.firstMatch(text);
    if (n != null) {
      final rest = n.group(3)!;
      return MdBlock(
        MdKind.numbered,
        '**${n.group(2)!.trim()}**${rest.isEmpty ? '' : ' $rest'}',
        number: int.parse(n.group(1)!),
      );
    }
  }
  return _guideBlock(text, bullet: false) ?? MdBlock(MdKind.paragraph, text);
}
