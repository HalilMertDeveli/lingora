import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/course_repository.dart';
import '../../data/practice.dart';
import '../../data/progress.dart';
import '../../models/course.dart';
import '../../study/analysis.dart';
import '../../data/option_glosses.dart';
import '../../services/billing/premium.dart';
import '../../services/explain_more.dart';
import '../../study/mistake_diagnosis.dart';
import '../../study/mistake_reasons.dart';
import '../../study/mixed_review.dart';
import '../../study/question_types.dart';
import '../../study/review_queue.dart';
import '../../study/year_plan.dart';
import '../../study/study_state.dart';
import '../../theme.dart';
import '../../ui/mistake_inspect.dart';
import '../lesson_screen.dart';
import '../topic_guide.dart';
import 'methods_screen.dart';
import 'mock_report_screen.dart';

/// Opens the error notebook inside the current tab.
void openNotebook(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotebookScreen()));

/// "Hata defteri": the questions answered wrong with "Neden yanıldın?",
/// the targeted suggestion for each reason, and the analysis: weak types,
/// weak units, time against the targets and the YDS score estimate.
class NotebookScreen extends ConsumerWidget {
  const NotebookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseProvider).value;
    final p = ref.watch(progressProvider);
    final log = ref.watch(studyLogProvider).answers;
    final today = dayKey(ref.watch(clockProvider)());
    if (course == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final all = mistakeItems(course, p.mistakes, limit: maxMistakes);
    // Untagged first (today's new mistakes), then the rest, newest first.
    final untagged = all.where((it) => !p.mistakeReason.containsKey(it.key)).toList();
    final tagged = all.where((it) => p.mistakeReason.containsKey(it.key)).toList();
    final due = mistakeItems(course, p.mistakesDue(today), limit: 20);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hata defteri'),
        actions: [
          IconButton(
            tooltip: 'Neden hata defteri?',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => openMethods(context, focus: 'mockloop'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Analysis(log: log, course: course),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('notebook-due'),
            onPressed: due.isEmpty
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) => LessonScreen(
                        nodeId: 'practice',
                        title: 'Hata defteri',
                        items: due,
                        color: Brand.error,
                        mode: LessonMode.practice,
                      ),
                    ),
                  ),
            icon: const Icon(Icons.replay_rounded),
            label: Text(due.isEmpty ? 'Bugün vadesi gelen soru yok' : 'Vadesi gelenleri çöz (${due.length})'),
          ),
          const SizedBox(height: 16),
          if (all.isEmpty)
            Text(
              'Defterin boş. Yanlış yaptığın sorular burada toplanır.',
              style: TextStyle(color: Brand.muted),
            )
          else ...[
            SectionLabel('NEDEN YANILDIN? (${untagged.length})'),
            const SizedBox(height: 4),
            Text(
              'Bir neden seç; sana uygun öneriyi gösterelim. İstersen atla.',
              style: TextStyle(color: Brand.muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            for (final it in untagged) _MistakeCard(item: it, course: course),
            if (tagged.isNotEmpty) ...[
              const SizedBox(height: 8),
              SectionLabel('ETİKETLENENLER (${tagged.length})'),
              const SizedBox(height: 8),
              for (final it in tagged) _MistakeCard(item: it, course: course),
            ],
          ],
          const SizedBox(height: 8),
          Text(
            'Sorular 1, 3, 7 ve 21 gün sonra döner; arka arkaya 2 doğruyla defterden çıkar.',
            style: TextStyle(color: Brand.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Analysis extends ConsumerWidget {
  const _Analysis({required this.log, required this.course});
  final List<AnswerLog> log;
  final Course course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final stats = typeStats(log);
    final weak = weakTypes(stats);
    final units = weakUnits(log);
    final score = estimateScore(
      log,
      halfMocks: halfMockNodes(ref.watch(yearPlanProvider).value),
      mix: ExamMix.of(ref.watch(progressProvider).studyPlan?.exam),
    );
    final title = {for (final u in course.units) u.id: u.title};
    return TapCard(
      key: const Key('notebook-analysis'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Zayıf noktaların', style: t.titleMedium),
          const SizedBox(height: 6),
          if (score != null)
            Text(
              'Tahmini YDS puanı: $score',
              key: const Key('score-estimate'),
              style: TextStyle(fontWeight: FontWeight.w900, color: Brand.tone(Brand.primary)),
            )
          else
            Text(
              'Tahmini puan için en az $minAnswersForEstimate sınav sorusu çözmelisin.',
              style: TextStyle(color: Brand.muted, fontSize: 13),
            ),
          if (score != null)
            Text(
              !score.fromMocks
                  ? 'Alıştırmalara göre (${score.basis} soru); ilk deneme sonrası netleşir.'
                  : score.halfMocksOnly
                  ? 'Yarım denemelerine göre (${score.basis} soru); tam deneme çözünce netleşir.'
                  : 'Tam denemelerine göre (${score.basis} soru). Gerçek sınavda puanı ÖSYM hesaplar.',
              style: TextStyle(color: Brand.muted, fontSize: 12),
            ),
          const SizedBox(height: 8),
          if (weak.isEmpty)
            Text('Analiz için her tipten birkaç soru çöz.', style: TextStyle(color: Brand.muted))
          else
            for (final s in weak)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${s.type.label}: %${(s.accuracy * 100).round()} doğru · '
                        'ort. ${s.avgSeconds.round()} sn (hedef ${s.type.targetSeconds})',
                        style: TextStyle(color: s.slow ? Brand.tone(Brand.error) : null),
                      ),
                    ),
                    TextButton(
                      key: Key('target-${s.type.name}'),
                      onPressed: () => _targeted(context, ref, s.type),
                      child: const Text('Çalış'),
                    ),
                  ],
                ),
              ),
          if (units.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'En çok yanlış: ${units.map((u) => '${title[u.$1] ?? u.$1} (${u.$2})').join(', ')}',
              style: TextStyle(color: Brand.muted, fontSize: 13),
            ),
          ],
          if (log.lastWhere((a) => a.fromMock, orElse: () => _noMock) case final last when last.fromMock) ...[
            const SizedBox(height: 8),
            MockReportButton(key: const Key('last-mock-report'), source: last.source),
          ],
        ],
      ),
    );
  }

  static const _noMock = AnswerLog(key: '', day: '', correct: false, seconds: 0);

  /// Targeted review: a mixed set of finished units' questions of [type].
  void _targeted(BuildContext context, WidgetRef ref, QType type) {
    final items = mixedSet(
      course,
      ref.read(progressProvider),
      only: (unit, it) => exerciseType(it.ex, unitId: unit.id) == type,
    );
    if (items.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${type.label}: bitirdiğin ünitelerde soru bulunamadı.')));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => LessonScreen(
          nodeId: 'targeted_review',
          title: '${type.label} tekrarı',
          items: items,
          color: Brand.error,
          mode: LessonMode.practice,
          logSource: 'targeted',
        ),
      ),
    );
  }
}

/// "Neden yanlış?" on a notebook card: the kind of mistake the app found and
/// the reason (the learner's own option's reason with Premium, the rule for
/// the kind otherwise), then why the right option fits.
class _WhyBox extends StatelessWidget {
  const _WhyBox({required this.diagnosis, required this.premium});
  final MistakeDiagnosis diagnosis;
  final bool premium;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final d = diagnosis;
    final right = d.rightWhy;
    return Container(
      key: const Key('mistake-why'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.card.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Hata türü: ',
                  style: TextStyle(color: p.muted, fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: d.kind.label,
                  style: TextStyle(color: p.primary, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            key: const Key('mistake-kind'),
          ),
          const SizedBox(height: 4),
          Text(
            premium ? d.reason : d.kind.rule,
            key: const Key('mistake-reason'),
            style: TextStyle(color: p.ink, height: 1.35),
          ),
          if (right != null && right.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              right,
              style: TextStyle(color: p.ink, height: 1.35, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

class _MistakeCard extends ConsumerStatefulWidget {
  const _MistakeCard({required this.item, required this.course});
  final LessonItem item;
  final Course course;

  @override
  ConsumerState<_MistakeCard> createState() => _MistakeCardState();
}

class _MistakeCardState extends ConsumerState<_MistakeCard> {
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: ref.read(progressProvider).mistakeNote[widget.item.key] ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _pick(MistakeReason r) {
    final n = ref.read(progressProvider.notifier);
    n.tagMistake(widget.item.key, reason: r.name);
    if (r == MistakeReason.twoOptions) n.postponeMistake(widget.item.key, 3);
  }

  Future<void> _act(MistakeReason r) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final unit = unitOfItem(widget.course, widget.item.key);
    switch (r) {
      case MistakeReason.vocab:
        final cards = wordsInQuestion(
          widget.item.ex,
          widget.course,
          ydsCards: ref.read(ydsVocabProvider).value ?? const [],
        );
        final added = ref.read(progressProvider.notifier).queueWords(cards.map((c) => c.id));
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              cards.isEmpty
                  ? 'Bu sorudaki kelimeler henüz kart değil; Notlarım’a kendin ekleyebilirsin.'
                  : added == 0
                  ? 'Bu kelimeler zaten kartlarında: ${cards.map((c) => c.en).join(', ')}'
                  : '$added kelime bugünkü tekrar kartlarına eklendi.',
            ),
          ),
        );
      case MistakeReason.structure || MistakeReason.guess:
        if (unit == null) return;
        if (unit.hasGuide) {
          await nav.push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => TopicGuideScreen(unit: unit, index: 1, startLabel: '10 SORU ÇÖZ'),
            ),
          );
        }
        final items = unitQuestions(unit);
        if (items.isEmpty || !mounted) return;
        await nav.push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => LessonScreen(
              nodeId: 'unit_review',
              title: unit.title,
              items: items,
              color: Brand.tone(unit.color),
              mode: LessonMode.practice,
              logSource: 'targeted',
            ),
          ),
        );
      case MistakeReason.misread || MistakeReason.time || MistakeReason.twoOptions:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.item.ex;
    final p = ref.watch(progressProvider);
    final reason = MistakeReason.byName(p.mistakeReason[widget.item.key]);
    final unit = unitOfItem(widget.course, widget.item.key);
    final type = exerciseType(ex, unitId: unit?.id);
    final question = ex.question ?? ex.prompt ?? ex.text ?? '';
    final picked = p.mistakePicked[widget.item.key];
    final premium = ref.watch(premiumProvider);
    final diagnosis = diagnoseMistake(
      ex,
      picked: picked,
      gloss: ref.watch(optionGlossesProvider).value?.of(widget.item.key, ex.options.length),
      unitId: unit?.id,
    );
    final explain = explainQuestionOf(ex, picked: picked);
    final explanation = ex.explanation?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TapCard(
        key: Key('mistake-${widget.item.key}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              {if (type != null) type.label, ?unit?.title}.join(' · '),
              style: TextStyle(color: Brand.muted, fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(question, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            if (diagnosis?.picked case final yours?)
              Text(
                'Senin cevabın: $yours',
                key: const Key('mistake-picked'),
                style: TextStyle(fontWeight: FontWeight.w700, color: Brand.tone(Brand.error)),
              ),
            Text(
              'Doğrusu: ${diagnosis?.answer ?? ex.displayAnswer}',
              key: const Key('mistake-answer'),
              style: TextStyle(fontWeight: FontWeight.w800, color: Brand.tone(Brand.success)),
            ),
            if (diagnosis != null) ...[
              const SizedBox(height: 8),
              _WhyBox(diagnosis: diagnosis, premium: premium),
            ],
            if (explanation.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                explanation,
                key: const Key('mistake-explanation'),
                style: TextStyle(color: Brand.muted, fontSize: 13),
              ),
            ],
            if (explain != null) ...[
              const SizedBox(height: 8),
              MistakeInspect(key: ValueKey('inspect-${widget.item.key}'), question: explain),
            ],
            const SizedBox(height: 8),
            Text(
              'Sence neden yanıldın?',
              style: TextStyle(color: Brand.muted, fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in MistakeReason.values)
                  ChoiceChip(
                    key: Key('reason-${r.name}'),
                    label: Text('${r.emoji} ${r.label}', style: const TextStyle(fontSize: 12)),
                    selected: reason == r,
                    onSelected: (_) => _pick(r),
                  ),
              ],
            ),
            if (reason != null) ...[
              const SizedBox(height: 8),
              Text(reason.advice, key: const Key('reason-advice')),
              if (reason == MistakeReason.vocab ||
                  reason == MistakeReason.structure ||
                  reason == MistakeReason.guess)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('reason-act'),
                    onPressed: () => _act(reason),
                    child: Text(reason == MistakeReason.vocab ? 'Kartlara ekle' : 'Rehber ve 10 soru'),
                  ),
                ),
              TextField(
                key: const Key('mistake-note'),
                controller: _note,
                maxLength: 140,
                decoration: const InputDecoration(hintText: 'Neden yanıldım? (kendi cümlen, isteğe bağlı)'),
                onSubmitted: (v) => ref.read(progressProvider.notifier).tagMistake(widget.item.key, note: v),
                onTapOutside: (_) =>
                    ref.read(progressProvider.notifier).tagMistake(widget.item.key, note: _note.text),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
