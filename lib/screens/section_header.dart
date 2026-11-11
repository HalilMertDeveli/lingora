import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/practice.dart';
import '../data/progress.dart';
import '../data/sections.dart';
import '../models/course.dart';
import '../theme.dart';
import '../ui/motion.dart';
import '../ui/tea_art.dart';
import 'lesson_screen.dart';

/// "Bölüm 2 · A1 · Günlük hayat" with the share of finished steps. Tapping
/// it opens the section summary.
class SectionHeader extends ConsumerWidget {
  const SectionHeader({super.key, required this.section, required this.open});
  final Section section;
  final bool open;

  Color get _color => Brand.tone(section.units.isEmpty ? Brand.primary : section.units.first.color);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratio = sectionProgress(section, ref.watch(progressProvider));
    final percent = (ratio * 100).round();
    final t = Theme.of(context).textTheme;
    return TapCard(
      key: Key('section-${section.id}'),
      color: _color,
      onTap: () => showSectionSummary(context, section, open: open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The place this section walks through (Mahalle, Çarşı, Vapur…).
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: SizedBox(
              height: 58,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      key: Key('district-${section.id}'),
                      painter: DistrictPainter(
                        district: District.of(section.index),
                        color: open ? _color : Brand.muted,
                        palette: Brand.palette,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Brand.card.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        District.of(section.index).label,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: open ? _color : Brand.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                open ? Icons.flag_circle_rounded : Icons.lock_rounded,
                color: open ? _color : Brand.muted,
                size: 34,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sectionLabel(section), style: t.titleMedium),
                    const SizedBox(height: 8),
                    GlossyProgress(value: ratio, height: 10, color: _color),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                open ? '%$percent' : 'Kilitli',
                style: TextStyle(fontWeight: FontWeight.w800, color: Brand.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Bölüm 2 · A1 · Günlük hayat".
String sectionLabel(Section s) => ['Bölüm ${s.index}', if (s.cefr.isNotEmpty) s.cefr, s.title].join(' · ');

/// Section summary: description, grammar topics, unit count and, while the
/// section is locked, the "Bölüme atla" exam.
Future<void> showSectionSummary(BuildContext context, Section section, {required bool open}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => _SectionSummary(section: section, open: open),
    );

class _SectionSummary extends ConsumerWidget {
  const _SectionSummary({required this.section, required this.open});
  final Section section;
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final p = ref.watch(progressProvider);
    final lessons = section.nodes.where((n) => n.type == NodeType.lesson);
    final doneLessons = lessons.where((n) => p.isDone(n.id)).length;
    final canSkip = !open && sectionSkipItems(section).length >= sectionSkipSize ~/ 2;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          key: Key('section-summary-${section.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(sectionLabel(section), style: t.titleLarge),
            if (section.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(section.description, style: t.bodyMedium?.copyWith(color: Brand.muted)),
            ],
            const SizedBox(height: 12),
            Text(
              '${section.units.length} ünite · $doneLessons / ${lessons.length} ders',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (section.grammar.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Dilbilgisi konuları', style: t.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final g in section.grammar) Chip(label: Text(g))],
              ),
            ],
            if (canSkip) ...[
              const SizedBox(height: 20),
              Text(
                'Bu konuları biliyorsan $sectionSkipSize soruluk sınavla bölümü hemen aç. '
                '%$testPassPercent doğru yeterli; geçemezsen hiçbir şey kaybetmezsin.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 12),
              PressableButton(
                key: const Key('section-skip'),
                label: Brand.isKid ? 'BÖLÜME ATLA' : 'Bölüme atla',
                onPressed: () {
                  final nav = Navigator.of(context)..pop();
                  startSectionSkip(nav, section);
                },
              ),
            ] else if (!open) ...[
              const SizedBox(height: 16),
              Text('Önceki bölümün sınavını geçince bu bölüm açılır.', style: t.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Bölüme atla": a mixed test over the whole section. Passing it records
/// [sectionPassId], which opens the section; failing changes nothing.
Future<void> startSectionSkip(NavigatorState nav, Section section) {
  final color = Brand.tone(section.units.first.color);
  LessonScreen build() => LessonScreen(
    nodeId: sectionPassId(section.index),
    title: 'Bölüm ${section.index}',
    items: sectionSkipItems(section),
    color: color,
    mode: LessonMode.test,
    retry: build,
    badge: 'BÖLÜME ATLA',
    passHeadline: 'Bölüm ${section.index} açıldı!',
  );
  return nav.push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => build()));
}
