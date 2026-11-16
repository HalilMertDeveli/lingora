import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/course_repository.dart';
import '../data/practice.dart';
import '../data/progress.dart';
import '../data/sections.dart';
import '../data/skip_exam.dart';
import '../models/course.dart';
import '../theme.dart';
import '../ui/hearts.dart';
import '../ui/motion.dart';
import '../ui/tea_art.dart';
import 'lesson_screen.dart';
import 'skip_exam_card.dart';

/// "Bölüm 2 · A1 · Günlük hayat" with the share of finished steps. Tapping
/// it opens the section summary.
class SectionHeader extends ConsumerWidget {
  const SectionHeader({super.key, required this.section, required this.open});
  final Section section;
  final bool open;

  Color get _color => Brand.tone(section.units.isEmpty ? Brand.primary : section.units.first.color);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);
    final ratio = sectionProgress(section, progress);
    // The path draws an outline without exercises; the skills test and the
    // writing task are found in the full course, loaded in the background.
    final full = ref.watch(courseProvider).value?.sections.where((s) => s.id == section.id).firstOrNull;
    final completed = full != null && sectionCompleted(full, progress);
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
                completed
                    ? Icons.verified_rounded
                    : open
                    ? Icons.flag_circle_rounded
                    : Icons.lock_rounded,
                key: completed ? Key('section-completed-${section.id}') : null,
                color: completed ? Brand.success : (open ? _color : Brand.muted),
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
                completed ? 'Tamamlandı' : (open ? '%$percent' : 'Kilitli'),
                style: TextStyle(fontWeight: FontWeight.w800, color: Brand.muted),
              ),
              // "Bölümü atla": the summary explains the exam and starts it.
              if (!section.parallel && !sectionSkipFinished(section, progress)) ...[
                const SizedBox(width: 8),
                Material(
                  color: _color,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    key: Key('section-skip-quick-${section.id}'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => showSectionSummary(context, section, open: open),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 2),
                          Text(
                            'Atla',
                            semanticsLabel: open ? 'Bu bölümü sınavla atla' : 'Sınavla bu bölüme atla',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// "Bölüm 2 · A1 · Günlük hayat".
String sectionLabel(Section s) => ['Bölüm ${s.index}', if (s.cefr.isNotEmpty) s.cefr, s.title].join(' · ');

/// Section summary: description, grammar topics, unit count and, until every
/// step is done, the "Bölüme atla" skip exam (five hearts).
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
    // The path is drawn from an outline without exercises: the exam's
    // questions come from the full course.
    final full =
        ref.watch(courseProvider).value?.sections.where((s) => s.id == section.id).firstOrNull ?? section;
    final finished = sectionSkipFinished(full, p);
    final canSkip = !section.parallel && !finished && sectionSkipItems(full).length >= sectionSkipSize ~/ 2;
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
              const HeartsBar(left: skipHearts, total: skipHearts),
              const SizedBox(height: 8),
              Text(
                'Bu konuları biliyorsan $sectionSkipSize soruluk karışık bir sınavla '
                '${open ? 'bölümü bitir' : 'bu bölüme atla'}. ${skipRules(unit: false)}',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 12),
              PressableButton(
                key: const Key('section-skip'),
                label: switch ((open, Brand.isKid)) {
                  (true, true) => 'BU BÖLÜMÜ ATLA',
                  (true, false) => 'Bu bölümü atla',
                  (false, true) => 'BÖLÜME ATLA',
                  (false, false) => 'Bölüme atla',
                },
                onPressed: () {
                  final nav = Navigator.of(context)..pop();
                  startSectionSkip(nav, full);
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

/// "Bölüme atla": a mixed test over the whole section with [skipHearts]
/// hearts. Passing it records [sectionPassKey] (which opens the section and
/// those before it) and counts every step of the section as done, so the
/// next section opens too; running out of hearts changes nothing.
/// [section] must come from the full course (with exercises).
Future<void> startSectionSkip(NavigatorState nav, Section section) {
  final color = Brand.tone(section.units.first.color);
  LessonScreen build() => LessonScreen(
    nodeId: sectionPassKey(section),
    title: 'Bölüm ${section.index}',
    items: sectionSkipItems(section),
    color: color,
    mode: LessonMode.test,
    rewardXp: sectionSkipXp,
    hearts: skipHearts,
    retry: build,
    badge: 'BÖLÜME ATLA',
    passHeadline: 'Bölüm ${section.index} geçildi!',
  );
  return nav.push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => build()));
}
