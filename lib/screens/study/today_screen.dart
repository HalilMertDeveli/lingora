import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/course_repository.dart';
import '../../data/placement.dart';
import '../../data/practice.dart';
import '../../data/progress.dart';
import '../../models/course.dart';
import '../../models/study_plan.dart';
import '../../nav/nav_target.dart';
import '../../study/daily_plan.dart';
import '../../study/mixed_review.dart';
import '../../study/question_types.dart';
import '../../study/study_state.dart';
import '../../study/year_plan.dart';
import '../../theme.dart';
import '../../ui/motion.dart';
import '../exam_screen.dart';
import '../lesson_screen.dart';
import '../practice_hub_screen.dart';
import '../reading_screen.dart';
import '../../data/exam_pack_repository.dart';
import '../../data/exam_path.dart';
import '../../services/billing/exam_packs.dart';
import '../../services/billing/products.dart';
import '../../study/analysis.dart';
import '../story_screen.dart';
import 'notebook_screen.dart';
import 'methods_screen.dart';
import 'srs_review_screen.dart';

/// Opens "Bugün" inside the current tab.
void openToday(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TodayScreen()));

/// The general course, loaded for the plan's general-course weeks.
final generalCourseProvider = FutureProvider<Course>((ref) => loadCourse(rootBundle, 'tr_en'));

/// Everything "Bugün" needs that comes from assets: the year plan and the
/// units of the general course and the YDS path, by id.
final planDataProvider = FutureProvider<({YearPlan year, Map<String, Unit> units})?>((ref) async {
  final year = await ref.watch(yearPlanProvider.future);
  if (year == null) return null;
  final general = await ref.watch(generalCourseProvider.future);
  final yds = await ref.watch(examPathProvider('yds').future);
  return (year: year, units: planUnits([general, ?yds]));
});

/// Answers logged on [day] that are exam-style questions.
int questionsOn(StudyLog log, String day) =>
    log.answers.where((a) => a.day == day && QType.byName(a.type) != null).length;

bool mockOn(StudyLog log, String day) => log.answers.any((a) => a.day == day && a.fromMock);

/// Today's plan; null without a plan or before the assets load.
class TodayPlan {
  const TodayPlan({
    required this.plan,
    required this.year,
    required this.week,
    required this.status,
    required this.kind,
    required this.blocks,
    required this.next,
    required this.units,
    this.mock,
  });

  /// Today's mock on a mock day.
  final PlanMock? mock;
  final StudyPlan plan;
  final YearPlan year;
  final PlanWeek week;
  final WeekStatus status;
  final DayKind kind;
  final List<DayBlock> blocks;
  final (Unit, PathNode)? next;
  final Map<String, Unit> units;

  int get minutes => blocks.fold(0, (a, b) => a + b.minutes);
  int get doneMinutes => blocks.fold(0, (a, b) => a + (b.minutes * b.progress).round());
  double get progress => minutes == 0 ? 0 : doneMinutes / minutes;
}

final todayPlanProvider = Provider<TodayPlan?>((ref) {
  final p = ref.watch(progressProvider);
  final plan = p.studyPlan;
  final data = ref.watch(planDataProvider).value;
  if (plan == null || data == null) return null;
  final now = ref.watch(clockProvider)();
  final today = dayKey(now);
  final yesterday = dayKey(now.subtract(const Duration(days: 1)));
  final log = ref.watch(studyLogProvider);
  final week = planWeekOf(plan, data.year);
  final queue = ref.watch(reviewQueueProvider(newWordsPerDay(week, data.year)));
  final next = nextPlanStep(week, data.units, p, year: data.year);
  final kind = dayKind(plan: plan, week: week, now: now, mockYesterday: mockOn(log, yesterday));
  final mock = todayMock(plan: plan, week: week, now: now);
  final counts = DayCounts(
    cardsLeft: queue?.cards.length ?? 0,
    cardsDone: p.wordLast.values.where((d) => d == today).length,
    reviewDay: queue?.reviewDay ?? false,
    mistakesDue: queue?.mistakes.length ?? 0,
    lessonsToday: p.counters['$today:lessons'] ?? 0,
    questionsToday: questionsOn(log, today),
    readingToday: p.readingWordsOn(today),
    mockToday: mockOn(log, today),
  );
  return TodayPlan(
    plan: plan,
    year: data.year,
    week: week,
    status: weekStatus(plan: plan, year: data.year, units: data.units, progress: p),
    kind: kind,
    blocks: dayBlocks(
      kind: kind,
      plan: plan,
      year: data.year,
      week: week,
      c: counts,
      nextStep: next?.$2.title,
      mock: mock,
    ),
    next: next,
    units: data.units,
    mock: mock,
  );
});

/// New words a day in [week] (its new words over the study days).
int newWordsPerDay(PlanWeek week, YearPlan year) =>
    week.newWords == 0 ? 0 : (week.newWords / year.daysPerWeek).ceil();

/// "Bugün": the day's blocks and where the learner is in the year plan.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _settle());
  }

  /// Moves the plan on when the week is done.
  Future<void> _settle() async {
    final data = await ref.read(planDataProvider.future);
    final p = ref.read(progressProvider);
    final plan = p.studyPlan;
    if (data == null || plan == null || !mounted) return;
    final week = planWeekOf(plan, data.year);
    final queue = ref.read(reviewQueueProvider(newWordsPerDay(week, data.year)));
    final next = settleWeek(
      plan: plan,
      year: data.year,
      units: data.units,
      progress: p,
      now: ref.read(clockProvider)(),
      noNewCards: queue != null && queue.fresh.isEmpty && queue.due.isEmpty,
    );
    if (next.week != plan.week) ref.read(progressProvider.notifier).setStudyPlan(next);
  }

  @override
  Widget build(BuildContext context) {
    final hasPlan = ref.watch(progressProvider.select((p) => p.studyPlan != null));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bugün'),
        actions: [
          IconButton(
            key: const Key('today-methods'),
            tooltip: 'Nasıl öğretiyoruz?',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => openMethods(context, focus: 'habit'),
          ),
          if (hasPlan)
            IconButton(
              key: const Key('today-edit'),
              tooltip: 'Planı düzenle',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const PlanSetupScreen())),
            ),
        ],
      ),
      body: hasPlan ? const _TodayBody() : const PlanSetupBody(),
    );
  }
}

class _TodayBody extends ConsumerWidget {
  const _TodayBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayPlanProvider);
    if (today == null) return const Center(child: CircularProgressIndicator());
    final t = Theme.of(context).textTheme;
    final p = ref.watch(progressProvider);
    final now = ref.watch(clockProvider)();
    final status = today.status;
    final phase = today.year.phaseOf(today.plan.week);
    final finish = estimatedFinish(today.plan, today.year, now);
    final kindLabel = switch (today.kind) {
      DayKind.mock => 'DENEME GÜNÜ',
      DayKind.light => 'HAFİF GÜN',
      DayKind.afterMock => 'DENEME ANALİZİ GÜNÜ',
      DayKind.normal => null,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        TapCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${today.doneMinutes} / ${today.minutes} dk',
                      key: const Key('today-minutes'),
                      style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (kindLabel != null)
                    Text(
                      kindLabel,
                      key: const Key('today-kind'),
                      style: TextStyle(color: Brand.tone(Brand.accent), fontWeight: FontWeight.w900),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _Bar(value: today.progress, color: Brand.success),
              const SizedBox(height: 8),
              Text(
                today.progress >= 1
                    ? 'Bugünkü planı bitirdin. Harika!'
                    : today.plan.place.isEmpty
                    ? 'Blokları sırayla yap; aralarda 5–10 dk mola ver.'
                    : 'Çalışma yerin: ${today.plan.place}. Blokları sırayla yap.',
                style: TextStyle(color: Brand.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionLabel('BUGÜNÜN BLOKLARI'),
        const SizedBox(height: 8),
        for (final b in today.blocks) _BlockTile(block: b),
        if (today.kind == DayKind.light) ...[
          const SizedBox(height: 8),
          _WeeklyReport(progress: p, now: now, status: status),
        ],
        const SizedBox(height: 16),
        const SectionLabel('BU HAFTA'),
        const SizedBox(height: 8),
        TapCard(
          key: const Key('today-week'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                inMaintenance(today.plan, today.year)
                    ? 'Program bitti · sürdürme haftası ${today.plan.week - today.year.length}'
                    : 'Hafta ${today.plan.week} / ${today.year.length}'
                          '${phase == null ? '' : ' · ${phase.title}'}',
                style: t.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(today.week.units, style: TextStyle(color: Brand.muted)),
              const SizedBox(height: 10),
              if (today.week.reviewWeek)
                _WeekRow(
                  inMaintenance(today.plan, today.year)
                      ? 'Bu hafta çalışılan gün'
                      : 'Tekrar haftası: çalışılan gün',
                  status.studyDays,
                  today.year.daysPerWeek,
                  key: const Key('week-days'),
                )
              else
                _WeekRow(
                  'Haftanın adımları',
                  status.stepsDone,
                  status.stepsTotal,
                  key: const Key('week-steps'),
                ),
              if (status.wordsTarget > 0) _WeekRow('Yeni kelime', status.words, status.wordsTarget),
              const SizedBox(height: 6),
              Text(
                inMaintenance(today.plan, today.year)
                    ? 'Dersler bitmez: her hafta bir tam deneme, kalan kelime bankalarından yeni kartlar, '
                          'okunmamış ya da yeniden okunacak metinler ve hata defteri.'
                    : 'Hafta, hedefleri bitince ilerler; kaçırdığın gün birikmez. '
                          'Bu hızla planın ${_dateTr(finish)} civarında biter.',
                key: const Key('today-finish'),
                style: TextStyle(color: Brand.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => openMethods(context),
          icon: const Icon(Icons.lightbulb_outline_rounded),
          label: const Text('Bu plan neden böyle? Nasıl öğretiyoruz?'),
        ),
      ],
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow(this.label, this.done, this.total, {super.key});
  final String label;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('${done.clamp(0, total)} / $total', style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 4),
        _Bar(value: total == 0 ? 1 : done / total, color: Brand.primary),
      ],
    ),
  );
}

/// Light day: the week in numbers (§3.4).
class _WeeklyReport extends ConsumerWidget {
  const _WeeklyReport({required this.progress, required this.now, required this.status});
  final Progress progress;
  final DateTime now;
  final WeekStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(studyLogProvider);
    final days = [for (var i = 0; i < 7; i++) dayKey(now.subtract(Duration(days: i)))];
    final reading = days.fold(0, (a, d) => a + progress.readingWordsOn(d));
    final answers = log.answers.where((a) => days.contains(a.day) && QType.byName(a.type) != null).toList();
    final right = answers.where((a) => a.correct).length;
    return TapCard(
      key: const Key('weekly-report'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Haftalık rapor', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('Yeni kelime: ${status.words} / ${status.wordsTarget}'),
          Text('Bilinen kelime toplamı: ${wordsStarted(progress)}'),
          Text('Son 7 günde okunan: $reading kelime'),
          Text(
            answers.isEmpty
                ? 'Bu hafta soru çözülmedi'
                : 'Soru doğruluğu: %${(right * 100 / answers.length).round()} (${answers.length} soru)',
          ),
          if (estimateScore(
                log.answers,
                halfMocks: halfMockNodes(ref.watch(yearPlanProvider).value),
                mix: ExamMix.of(progress.studyPlan?.exam),
              )
              case final score?)
            Text('Tahmini YDS puanı: $score', key: const Key('weekly-score')),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: LinearProgressIndicator(
      value: value.clamp(0, 1).toDouble(),
      minHeight: 10,
      color: Brand.tone(color),
      backgroundColor: Brand.line,
    ),
  );
}

class _BlockTile extends ConsumerWidget {
  const _BlockTile({required this.block});
  final DayBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = switch (block.block) {
      PlanBlock.review => Brand.primary,
      PlanBlock.lesson => Brand.success,
      PlanBlock.reading => const Color(0xFF2F80ED),
      PlanBlock.questions || PlanBlock.mock => Brand.accent,
      PlanBlock.mistakes || PlanBlock.mockReview => Brand.error,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TapCard(
        key: Key('block-${block.block.name}'),
        onTap: () => runBlock(context, ref, block.block),
        child: Row(
          children: [
            Text(block.done ? '✅' : block.block.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(block.name, style: Theme.of(context).textTheme.titleMedium)),
                      Text(
                        '${block.minutes} dk',
                        style: TextStyle(fontWeight: FontWeight.w800, color: Brand.tone(color)),
                      ),
                    ],
                  ),
                  Text(block.detail, style: TextStyle(color: Brand.muted, fontSize: 13)),
                  const SizedBox(height: 6),
                  _Bar(value: block.progress, color: color),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens [block]'s activity.
Future<void> runBlock(BuildContext context, WidgetRef ref, PlanBlock block) async {
  final nav = Navigator.of(context);
  final today = ref.read(todayPlanProvider);
  final course = ref.read(courseProvider).value;
  final p = ref.read(progressProvider);
  if (today == null) return;
  Future<void> full(Widget screen) =>
      nav.push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => screen));
  void snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  final mistakes = course == null
      ? const <LessonItem>[]
      : mistakeItems(course, p.mistakesDue(dayKey(ref.read(clockProvider)())), limit: 20);

  switch (block) {
    case PlanBlock.review:
      await openReviewCards(context, newPerDay: newWordsPerDay(today.week, today.year));
    case PlanBlock.lesson:
      final next = today.next;
      if (next == null) {
        snack('Haftanın üniteleri bitti. Bugün tekrar ve soru bloklarına ağırlık ver.');
        return;
      }
      final (unit, node) = next;
      final color = Brand.tone(unit.color);
      switch (node.type) {
        case NodeType.lesson:
          await full(LessonScreen.forNode(node, color));
        case NodeType.test:
          LessonScreen build() => LessonScreen(
            nodeId: node.id,
            title: node.title,
            items: testItems(unit, node),
            color: color,
            mode: LessonMode.test,
            rewardXp: node.rewardXp,
            retry: build,
          );
          await full(build());
        case NodeType.story:
          await full(StoryScreen(node: node, color: color));
        case NodeType.chest:
          ref.read(progressProvider.notifier).completeNode(node.id, xp: node.rewardXp);
          snack('${unit.title}: sandık açıldı, +${node.rewardXp} XP');
        case NodeType.mock:
          nav.popUntil((r) => r.isFirst);
          ref.read(pendingNavTargetProvider.notifier).open(const NavTarget(AppTab.learn));
      }
    case PlanBlock.reading:
      await nav.push(MaterialPageRoute<void>(builder: (_) => const ReadingLibraryScreen()));
    case PlanBlock.questions:
      // Interleaving: the last four weeks' units, else the whole open path.
      // In maintenance: every finished section.
      final recent = {
        if (!inMaintenance(today.plan, today.year))
          for (var w = today.plan.week; w > today.plan.week - 4 && w > 0; w--) ...today.year.week(w).unitIds,
      };
      final pool = Course(
        id: 'plan_mix',
        title: 'Karışık',
        fromLang: 'tr',
        learningLang: 'en',
        units: [for (final id in recent) ?today.units[id]],
      );
      var items = pool.units.isEmpty ? <LessonItem>[] : mixedSet(pool, p);
      if (items.length < 4 && course != null) items = mixedSet(course, p);
      if (items.isEmpty) {
        snack('Karışık set için önce birkaç ders bitir.');
        return;
      }
      await full(
        LessonScreen(
          nodeId: 'mixed_review',
          title: 'Karışık soru seti',
          items: items,
          color: Brand.accent,
          mode: LessonMode.practice,
          logSource: 'mixed',
        ),
      );
    case PlanBlock.mistakes || PlanBlock.mockReview:
      // The notebook: tag today's mistakes, solve the due ones, analysis.
      if (mistakes.isEmpty && p.mistakes.isEmpty) {
        snack('Hata defterin boş.');
        return;
      }
      await nav.push(MaterialPageRoute<void>(builder: (_) => const NotebookScreen()));
    case PlanBlock.mock:
      final mock = today.mock ?? (today.week.examMocks.isEmpty ? null : today.week.examMocks.first);
      if (mock != null && await startPlanMock(context, ref, mock)) return;
      if (!context.mounted) return;
      PracticeHubScreen.openPage(
        context,
        'Deneme sınavları',
        const ExamHomeScreen(examId: 'yds', view: ExamHomeView.mocks),
      );
  }
}

/// Starts a plan mock directly: a pack mock (`full`, when the pack is
/// unlocked) or a path mock node (`half` / `section`). Returns false to
/// fall back to the mocks page.
Future<bool> startPlanMock(BuildContext context, WidgetRef ref, PlanMock mock) async {
  final nav = Navigator.of(context);
  try {
    final exam = await ref.read(examProvider('yds').future);
    if (mock.kind == MockKind.full) {
      final pack = ExamPack.forExam('yds');
      if (pack == null || !ref.read(examPackUnlockedProvider('yds'))) return false;
      final content = await ref.read(examPackContentProvider(pack).future);
      final p = ref.read(progressProvider);
      final id = pickFullMock(
        packIds: [for (final m in content.mocks) m.id],
        exam: p.studyPlan?.exam ?? 'yds',
        mock: mock,
        taken: p.examBest.keys.toSet(),
      );
      final full = content.mocks.where((m) => m.id == id).firstOrNull;
      if (full == null) return false;
      await nav.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ExamSessionScreen(
            exam: exam,
            questions: full.questions,
            mock: true,
            title: full.title,
            minutes: full.minutes,
            pack: content,
            fullMock: full,
          ),
        ),
      );
      return true;
    }
    final course = await ref.read(examPathProvider('yds').future);
    final node = course?.allNodes.where((n) => n.id == mock.nodeId).firstOrNull;
    final section = node == null ? null : sectionOf(course!, node);
    if (node == null || section == null) return false;
    final questions = mockQuestions(section, node, bank: exam);
    await nav.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ExamSessionScreen(
          exam: mockExam(node, exam, questions),
          questions: questions,
          mock: true,
          title: node.title,
          minutes: node.minutes > 0 ? node.minutes : mock.minutes,
          nodeId: node.id,
        ),
      ),
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// Plan settings as their own page ("Planı düzenle").
class PlanSetupScreen extends StatelessWidget {
  const PlanSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Çalışma planı')),
    body: PlanSetupBody(onSaved: () => Navigator.of(context).pop()),
  );
}

const _weekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

/// Plan setup: exam, start week, daily time, when and where (the reminder),
/// light day and mock day.
class PlanSetupBody extends ConsumerStatefulWidget {
  const PlanSetupBody({super.key, this.onSaved});
  final VoidCallback? onSaved;

  @override
  ConsumerState<PlanSetupBody> createState() => _PlanSetupBodyState();
}

class _PlanSetupBodyState extends ConsumerState<PlanSetupBody> {
  late String _exam;
  late int _minutes;
  late int _week;
  late int _time;
  late int _lightDay;
  late int _mockDay;
  final _place = TextEditingController();
  bool get _editing => ref.read(progressProvider).studyPlan != null;

  @override
  void initState() {
    super.initState();
    final p = ref.read(progressProvider);
    final plan = p.studyPlan;
    _exam = plan?.exam ?? 'yds';
    _minutes = plan?.dailyMinutes ?? 180;
    _week = plan?.week ?? startWeekFor(ref.read(placementProvider)?.level);
    _time = p.reminderMinutes;
    _lightDay = plan?.lightDay ?? DateTime.sunday;
    _mockDay = plan?.mockDay ?? DateTime.saturday;
    _place.text = plan?.place ?? '';
  }

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  String _label(int m) => m < 60 ? '$m dk' : '${m ~/ 60} saat';

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _time ~/ 60, minute: _time % 60),
      helpText: 'Hangi saatte çalışacaksın?',
    );
    if (picked != null) setState(() => _time = picked.hour * 60 + picked.minute);
  }

  Future<void> _save(YearPlan year) async {
    final notifier = ref.read(progressProvider.notifier);
    final p = ref.read(progressProvider);
    final today = dayKey(ref.read(clockProvider)());
    final old = p.studyPlan;
    final plan =
        (old ??
                StudyPlan(
                  exam: _exam,
                  week: _week,
                  weekStart: today,
                  dailyMinutes: _minutes,
                  startDay: today,
                  weekWordsBase: wordsStarted(p),
                ))
            .copyWith(
              exam: _exam,
              dailyMinutes: _minutes,
              place: _place.text.trim(),
              lightDay: _lightDay,
              mockDay: _mockDay,
            );
    // Starting further on: the earlier weeks' steps count as known (no XP).
    if (old == null && _week > 1) {
      final data = await ref.read(planDataProvider.future);
      final units = data?.units ?? const <String, Unit>{};
      notifier.markKnown([
        for (var w = 1; w < _week; w++)
          for (final id in year.week(w).unitIds)
            for (final n in units[id]?.nodes ?? const <PathNode>[])
              if (n.type != NodeType.mock) n.id,
      ]);
    }
    notifier
      ..setStudyPlan(plan)
      // Implementation intention: "when and where" becomes the reminder.
      ..setReminders(enabled: true, minutes: _time);
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final year = ref.watch(yearPlanProvider).value;
    if (year == null) return const Center(child: CircularProgressIndicator());
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(_editing ? 'Planını düzenle' : 'YDS planını kuralım', style: t.headlineSmall),
        const SizedBox(height: 4),
        Text(
          '52 haftalık programı her gün bloklara bölüyoruz: tekrar, yeni ders, okuma, soru, hata defteri.',
          style: TextStyle(color: Brand.muted),
        ),
        const SizedBox(height: 16),
        const SectionLabel('SINAV'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in planExams.entries)
              ChoiceChip(
                key: Key('exam-${e.key}'),
                label: Text(e.value),
                selected: _exam == e.key,
                onSelected: (_) => setState(() => _exam = e.key),
              ),
          ],
        ),
        if (!_editing) ...[
          const SizedBox(height: 16),
          const SectionLabel('NEREDEN BAŞLIYORSUN?'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in startWeeks(year))
                ChoiceChip(
                  key: Key('start-$w'),
                  label: Text('H$w · ${year.phaseOf(w)?.title ?? ''}'),
                  selected: _week == w,
                  onSelected: (_) => setState(() => _week = w),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            ref.watch(placementProvider) == null
                ? 'Seviye testi yaparsan başlangıcı ona göre seçeriz.'
                : 'Seviye testine göre önerildi. Önceki haftaların adımları biliniyor sayılır.',
            style: TextStyle(color: Brand.muted, fontSize: 13),
          ),
        ],
        const SizedBox(height: 16),
        const SectionLabel('GÜNDE NE KADAR?'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in dailyMinuteChoices)
              ChoiceChip(
                key: Key('minutes-$m'),
                label: Text(_label(m)),
                selected: _minutes == m,
                onSelected: (_) => setState(() => _minutes = m),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _minutes >= 120
              ? 'Program günde 3–4 saat için kuruldu; bloklar seçtiğin süreye göre ölçeklenir.'
              : 'Kısa günlerde önce tekrar, sonra hata defteri ve soru gelir.',
          style: TextStyle(color: Brand.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        const SectionLabel('NE ZAMAN, NEREDE?'),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 130,
              child: OutlinedButton.icon(
                key: const Key('plan-time'),
                onPressed: _pickTime,
                icon: const Icon(Icons.alarm_rounded),
                label: Text(
                  '${(_time ~/ 60).toString().padLeft(2, '0')}:${(_time % 60).toString().padLeft(2, '0')}',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('plan-place'),
                controller: _place,
                maxLength: 40,
                decoration: const InputDecoration(hintText: 'Nerede? (ör. mutfak masası)', counterText: ''),
              ),
            ),
          ],
        ),
        Text(
          'Her gün bu saatte hatırlatırız. Saat ve yer belirlemek alışkanlığı kolaylaştırır.',
          style: TextStyle(color: Brand.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        const SectionLabel('HAFİF GÜN'),
        const SizedBox(height: 8),
        _DayPicker(keyPrefix: 'light', value: _lightDay, onChanged: (d) => setState(() => _lightDay = d)),
        const SizedBox(height: 16),
        const SectionLabel('DENEME GÜNÜ'),
        const SizedBox(height: 8),
        _DayPicker(keyPrefix: 'mock', value: _mockDay, onChanged: (d) => setState(() => _mockDay = d)),
        const SizedBox(height: 24),
        PressableButton(
          key: const Key('plan-save'),
          label: _editing ? 'KAYDET' : 'PLANI BAŞLAT',
          onPressed: () => _save(year),
        ),
      ],
    );
  }
}

class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.keyPrefix, required this.value, required this.onChanged});
  final String keyPrefix;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (var d = 1; d <= 7; d++)
        ChoiceChip(
          key: Key('$keyPrefix-$d'),
          label: Text(_weekdays[d - 1]),
          selected: value == d,
          onSelected: (_) => onChanged(d),
        ),
    ],
  );
}

const _months = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', //
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

String _dateTr(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "Bugün" card at the top of the Pratik tab.
class TodayCard extends ConsumerWidget {
  const TodayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPlan = ref.watch(progressProvider.select((p) => p.studyPlan != null));
    final today = ref.watch(todayPlanProvider);
    final t = Theme.of(context).textTheme;
    return TapCard(
      key: const Key('today-card'),
      onTap: () => openToday(context),
      child: Row(
        children: [
          const Text('🗓️', style: TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bugün', style: t.titleMedium),
                Text(
                  !hasPlan
                      ? 'YDS planını kur: günlük süreni seç, bloklara bölelim'
                      : today == null
                      ? 'Plan yükleniyor…'
                      : 'Hafta ${today.plan.week} · ${today.doneMinutes} / ${today.minutes} dk',
                  style: TextStyle(color: Brand.muted, fontSize: 13),
                ),
                if (today != null) ...[
                  const SizedBox(height: 6),
                  _Bar(value: today.progress, color: Brand.success),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Brand.muted),
        ],
      ),
    );
  }
}
