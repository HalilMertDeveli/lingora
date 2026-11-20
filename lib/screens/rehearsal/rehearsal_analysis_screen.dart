import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/notes_repository.dart';
import '../../data/rehearsal.dart';
import '../../services/rehearsal_service.dart';
import '../../theme.dart';
import '../grammar_path_screen.dart';
import 'rehearsal_screen.dart';

/// "Çenebaz takıldığın yeri gösteriyor": the analysis of one rehearsal,
/// quoting the learner's own words. Free for the first rehearsal.
class RehearsalAnalysisScreen extends ConsumerWidget {
  const RehearsalAnalysisScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rehearsalProvider);
    final session = state.sessions.where((s) => s.id == sessionId).firstOrNull;
    final a = session?.analysis;
    final p = context.palette;
    final demo = !ref.watch(rehearsalServiceProvider).isLive;
    if (session == null || a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Analiz bulunamadı.')),
      );
    }
    final followUp = session.kind != RehearsalKind.first;
    return Scaffold(
      appBar: AppBar(title: Text(followUp ? 'Yeni provanın analizi' : 'Takıldığın yerler')),
      body: ListView(
        key: const Key('prova-analysis'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (demo)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Demo analiz (çevrimdışı kurallar)',
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ),
          Text(a.summaryTr, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '${session.answers.length} cevap · ${session.wordCount} kelime',
            style: TextStyle(color: p.muted),
          ),
          if (followUp && a.recurrenceNoteTr.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Box(
              key: const Key('prova-recurrence'),
              color: a.repeatedTags.isEmpty && a.repeatedGaps.isEmpty ? p.successBg : p.accentBg,
              child: Text(a.recurrenceNoteTr),
            ),
          ],
          if (a.gaps.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionLabel('İÇERİKTE EKSİK KALANLAR'),
            const SizedBox(height: 8),
            for (final g in a.gaps)
              _Box(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(gapTypeNames[g.type] ?? g.type, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (g.quote.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '“${g.quote}”',
                        style: TextStyle(color: p.muted, fontStyle: FontStyle.italic),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(g.messageTr),
                  ],
                ),
              ),
          ],
          if (a.errors.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionLabel('TEKRARLAYAN HATALAR'),
            const SizedBox(height: 8),
            for (final e in a.errors) _ErrorCard(error: e),
          ],
          const SizedBox(height: 20),
          const SectionLabel('SENİN CÜMLELERİNDEN ALIŞTIRMALAR'),
          const SizedBox(height: 8),
          for (final x in a.exercises)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• ${x.instructionTr}  ${x.kind == ExerciseKind.reorder ? x.words.join(' / ') : x.prompt}',
              ),
            ),
          const SizedBox(height: 8),
          Text('Yeniden anlat: ${a.retellPromptTr}'),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('prova-to-home'),
            onPressed: () {
              final nav = Navigator.of(context);
              // Every way here starts from the Prova home, which is right
              // below: going back to it avoids a second copy on the stack
              // (its back arrow then seemed to do nothing).
              if (nav.canPop()) {
                nav.pop();
              } else {
                nav.pushReplacement(MaterialPageRoute<void>(builder: (_) => const RehearsalHomeScreen()));
              }
            },
            child: Text(followUp ? 'Prova sayfasına dön' : 'Yarınki çalışmanı gör'),
          ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({super.key, required this.child, this.color});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color ?? context.palette.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.palette.line),
    ),
    child: child,
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});
  final GrammarError error;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _Box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${grammarTagNames[error.tag] ?? error.tag} · ${error.examples.length} kez',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (error.explanationTr.isNotEmpty) ...[const SizedBox(height: 4), Text(error.explanationTr)],
          const SizedBox(height: 6),
          for (final ex in error.examples)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: ex.quote,
                      style: TextStyle(color: p.error, decoration: TextDecoration.lineThrough),
                    ),
                    const TextSpan(text: '  →  '),
                    TextSpan(
                      text: ex.fix,
                      style: TextStyle(color: p.success, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          LessonLinks(tags: [error.tag]),
        ],
      ),
    );
  }
}

/// Chips that open the existing grammar-path lessons for [tags].
class LessonLinks extends ConsumerWidget {
  const LessonLinks({super.key, required this.tags});
  final List<String> tags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = lessonsForTags(tags);
    final lessons = ref.watch(grammarLessonsProvider).value;
    if (ids.isEmpty || lessons == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final id in ids)
          if (lessons.where((l) => l.id == id).firstOrNull case final lesson?)
            ActionChip(
              key: Key('prova-lesson-$id'),
              avatar: const Icon(Icons.menu_book_rounded, size: 16),
              label: Text(lesson.title),
              onPressed: () async {
                final notes = await ref.read(notesProvider.future);
                if (!context.mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => GrammarLessonScreen(lesson: lesson, notes: notes),
                  ),
                );
              },
            ),
      ],
    );
  }
}
