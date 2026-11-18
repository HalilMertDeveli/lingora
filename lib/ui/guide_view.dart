import 'package:flutter/material.dart';

import '../theme.dart';
import 'markdown_text.dart';

/// What a guide section is about, guessed from its heading. Decides the
/// section's colour and icon.
enum GuideTopic { goal, rule, example, steps, mistakes, tips, words, compare, test, other }

/// A section of a guide: its `##` heading (empty for text before the first
/// heading) and the blocks under it.
class GuideSection {
  const GuideSection(this.title, this.blocks);
  final String title;
  final List<MdBlock> blocks;

  GuideTopic get topic => guideTopic(title);
}

/// Splits a guide into sections by `##` heading.
List<GuideSection> guideSections(String source) {
  final out = <GuideSection>[];
  var title = '';
  var blocks = <MdBlock>[];
  void close() {
    if (title.isNotEmpty || blocks.isNotEmpty) out.add(GuideSection(title, blocks));
  }

  for (final b in parseMarkdown(source, guide: true)) {
    if (b.kind == MdKind.h2) {
      close();
      title = b.text;
      blocks = [];
    } else {
      blocks.add(b);
    }
  }
  close();
  return out;
}

String _lower(String s) => s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

GuideTopic guideTopic(String heading) {
  final h = _lower(heading);
  bool has(List<String> words) => words.any(h.contains);
  if (has(['hata', 'tuzak', 'yanlış'])) return GuideTopic.mistakes;
  if (has(['ipucu', 'ipuçları'])) return GuideTopic.tips;
  if (has(['biz nasıl', 'türkçe'])) return GuideTopic.compare;
  if (has(['kalıp'])) return GuideTopic.rule;
  if (has(['öğren', 'yapabilecek', 'hedef', 'bu hafta'])) return GuideTopic.goal;
  if (has(['nasıl', 'strateji', 'uygula', 'adım', 'plan', 'denemeden sonra'])) return GuideTopic.steps;
  if (has(['örnek', 'model metin'])) return GuideTopic.example;
  if (has(['kural', 'yapı', 'kalıp', 'özet', 'nedir', 'öbe'])) return GuideTopic.rule;
  if (has(['kelime', 'sözcük', 'ifade', 'terim', 'eşdizim', 'aile'])) return GuideTopic.words;
  if (has(['test', 'deneme', 'soru tip'])) return GuideTopic.test;
  return GuideTopic.other;
}

/// Colour and icon of a section. Content hues go through [Palette.tone] so
/// adult mode stays calm and dark mode stays readable.
({Color color, IconData icon}) guideLook(GuideTopic topic, Palette p, {int index = 0, Color? unit}) {
  const blue = Color(0xFF2F7DE1);
  const purple = Color(0xFF7B5BE6);
  const teal = Color(0xFF00959C);
  const pink = Color(0xFFD6457B);
  const indigo = Color(0xFF4C5BD4);
  return switch (topic) {
    GuideTopic.goal => (color: p.tone(blue), icon: Icons.flag_rounded),
    GuideTopic.rule => (color: p.tone(purple), icon: Icons.auto_stories_rounded),
    GuideTopic.example => (color: p.success, icon: Icons.chat_bubble_rounded),
    GuideTopic.steps => (color: p.tone(teal), icon: Icons.route_rounded),
    GuideTopic.mistakes => (color: p.error, icon: Icons.report_rounded),
    GuideTopic.tips => (color: p.accent, icon: Icons.lightbulb_rounded),
    GuideTopic.words => (color: p.tone(indigo), icon: Icons.translate_rounded),
    GuideTopic.compare => (color: p.tone(pink), icon: Icons.compare_arrows_rounded),
    GuideTopic.test => (color: p.primary, icon: Icons.quiz_rounded),
    GuideTopic.other => (
      color: unit ?? p.tone([blue, purple, teal, pink][index % 4]),
      icon: Icons.bookmark_rounded,
    ),
  };
}

/// A topic guide drawn as a column of section cards: each `##` section gets
/// a coloured header with an icon, its bullets coloured dots, numbered
/// items "Adım" steps, examples, mistakes, tips and formulas their own
/// boxes. [color] is the unit colour, used for untyped sections.
class GuideView extends StatelessWidget {
  const GuideView(this.source, {super.key, this.color});
  final String source;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final sections = guideSections(source);
    return Column(
      key: const Key('guide-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in sections.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: GuideSectionCard(section: s, index: i, unitColor: color),
          ),
      ],
    );
  }
}

class GuideSectionCard extends StatelessWidget {
  const GuideSectionCard({super.key, required this.section, required this.index, this.unitColor});
  final GuideSection section;
  final int index;
  final Color? unitColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final kid = context.isKid;
    final topic = section.topic;
    final look = guideLook(topic, p, index: index, unit: unitColor);
    final ink = readableOn(look.color, dark: p.isDark);
    final radius = context.lingora.cardRadius;
    final title = section.title;
    return Container(
      key: Key('guide-section-$index'),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: kid ? 34 : 30,
                    height: kid ? 34 : 30,
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(look.color.withValues(alpha: p.isDark ? 0.24 : 0.14), p.card),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Icon(look.icon, size: kid ? 20 : 18, color: ink),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      inlineSpan(
                        title,
                        TextStyle(
                          fontSize: kid ? 19 : 17,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          color: p.ink,
                        ),
                      ),
                      key: const Key('md-h2'),
                    ),
                  ),
                ],
              ),
            ),
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Divider(height: 1, thickness: 1, color: p.line),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: MdBlocksView(blocks: section.blocks, color: look.color, steps: topic == GuideTopic.steps),
          ),
        ],
      ),
    );
  }
}

/// About how many minutes the guide takes to read (180 words a minute).
int guideMinutes(String source) {
  final words = RegExp(r'\S+').allMatches(source).length;
  return (words / 180).ceil().clamp(1, 99);
}
