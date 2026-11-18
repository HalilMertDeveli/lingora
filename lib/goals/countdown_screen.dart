import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/course_repository.dart';
import '../data/progress.dart';
import '../models/course.dart';
import '../models/exam.dart';
import '../screens/exam_screen.dart';
import '../screens/lesson_screen.dart';
import '../screens/paywall_screen.dart';
import '../screens/practice_hub_screen.dart';
import '../screens/study/mock_report_screen.dart';
import '../screens/study/notebook_screen.dart';
import '../screens/study/srs_review_screen.dart';
import '../services/billing/premium.dart';
import '../study/analysis.dart';
import '../study/question_types.dart';
import '../study/study_state.dart';
import '../theme.dart';
import 'exam_countdown_plan.dart';
import 'goal_picker.dart';
import 'learn_goal.dart';

/// Paywall placement of the countdown plan (analytics).
const goalPlanPlacement = 'goal_plan';

/// The learner's last full mock (pack mock of 40+ questions) in the answer
/// log: its log source and answers. Null before the first one.
({String source, List<AnswerLog> answers})? lastFullMock(List<AnswerLog> log) {
  String? source;
  for (final a in log) {
    if (a.fromMock && fullMockId.hasMatch(mockIdOf(a.source))) source = a.source;
  }
  if (source == null) return null;
  final answers = [
    for (final a in log)
      if (a.source == source) a,
  ];
  return answers.length < 40 ? null : (source: source, answers: answers);
}

/// Path units (lessons) and exam bank sections (topic practice) per type.
Map<QType, List<PlanLink>> lessonLinks(Course? path) {
  final m = <QType, List<PlanLink>>{};
  for (final u in path?.units ?? const <Unit>[]) {
    final t = u.id.startsWith('ys1')
        ? QType.grammar
        : u.id.startsWith('ys2')
        ? QType.vocabulary
        : questionType(question: '', unitId: u.id);
    if (t == QType.other) continue;
    m.putIfAbsent(t, () => []).add(PlanLink(PlanItemKind.lesson, u.title, ref: u.id));
  }
  return m;
}

Map<QType, List<PlanLink>> practiceLinks(Exam? exam) {
  final m = <QType, List<PlanLink>>{};
  for (final s in exam?.sections ?? const <ExamSection>[]) {
    final t = questionType(question: '', section: s.id);
    if (t == QType.other) continue;
    m.putIfAbsent(t, () => []).add(PlanLink(PlanItemKind.practice, '${s.title}: 10 soru', ref: s.id));
  }
  return m;
}

void openCountdown(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CountdownScreen()));

/// "Sınava kadar": days left, the last mock's estimated score and the
/// day-by-day plan. Today's day is free; the whole plan is Premium.
class CountdownScreen extends ConsumerWidget {
  const CountdownScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(learnGoalProvider);
    final now = ref.watch(clockProvider)();
    final premium = ref.watch(premiumProvider);
    final log = ref.watch(studyLogProvider).answers;
    final path = ref.watch(examPathProvider('yds')).value;
    final exam = ref.watch(examProvider('yds')).value;
    final examGoal = goal != null && goal.kind == GoalKind.exam ? goal : null;
    final label = examGoal?.exam.label ?? 'YDS';
    final left = examGoal?.daysLeft(now);
    final last = lastFullMock(log);
    final mix = ExamMix.of(examGoal?.exam.name);
    final report = last == null ? null : MockReport(last.answers, mix: mix);
    final plan = left == null
        ? null
        : buildCountdownPlan(
            today: now,
            daysLeft: left,
            weak: [for (final r in report?.focus ?? const <MockRow>[]) (r.stat.type, r.gap)],
            lessons: lessonLinks(path),
            practice: practiceLinks(exam),
            mix: mix,
          );
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('$label planım')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: context.lingora.hero(Brand.primary, from: const Color(0xFF3B2FA8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  switch (left) {
                    null => 'Sınav tarihini ekle, planını kuralım',
                    0 => '$label günü geldi. Başarılar!',
                    < 0 => 'Sınav tarihi geçti',
                    _ => "$label'ye $left gün kaldı",
                  }.replaceAll("YÖKDİL'ye", "YÖKDİL'e"),
                  key: const ValueKey('countdown-title'),
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  report == null
                      ? 'Henüz tam deneme çözmedin. İlk tam denemen ücretsiz; plan zayıf soru tiplerine göre kurulur.'
                      : 'Son tam denemen: ${report.correct} / ${report.total} doğru · '
                            'tahmini puan ${formatScore(estimatedYdsScore(correct: report.correct, total: report.total))}',
                  key: const ValueKey('countdown-estimate'),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), height: 1.35),
                ),
                if (report != null)
                  Text(
                    'Tahmindir: her soru eşit ağırlıkta, toplam 100 puan. Gerçek puanı ÖSYM hesaplar.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (left == null || left < 0) ...[
            Text('Hedefin', style: t.titleLarge),
            const SizedBox(height: 8),
            const GoalProfileTile(),
          ] else if (plan != null && !plan.isEmpty) ...[
            _Summary(plan: plan),
            const SizedBox(height: 12),
            for (final d in premium ? plan.days : plan.days.take(1))
              _DayCard(day: d, lastSource: last?.source),
            if (!premium && plan.days.length > 1)
              _LockedRest(
                days: plan.days.length - 1,
                onUnlock: () =>
                    requirePremium(context, ref, PremiumFeature.errorAnalytics, placement: goalPlanPlacement),
              ),
            if (plan.daysLeft > maxCountdownDays)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Plan ilk $maxCountdownDays günü gösterir ve her gün yeniden kurulur.',
                  style: TextStyle(color: Brand.muted, fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.plan});
  final CountdownPlan plan;

  @override
  Widget build(BuildContext context) {
    final focus = plan.focusDays.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final mocks = plan.days.where((d) => d.kind == CountdownDayKind.mock).length;
    return TapCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sınava kadar şu konuları çalış', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final e in focus.take(4))
            Text('• ${e.key.label}: ${e.value} gün', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('• Tam deneme: $mocks gün', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

String _date(DateTime d) {
  const days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
  return '${d.day}.${d.month} ${days[d.weekday - 1]}';
}

class _DayCard extends ConsumerWidget {
  const _DayCard({required this.day, this.lastSource});
  final CountdownDay day;
  final String? lastSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = switch (day.kind) {
      CountdownDayKind.mock => 'Deneme günü',
      CountdownDayKind.analysis => 'Deneme analizi${day.focus == null ? '' : ' + ${day.focus!.label}'}',
      CountdownDayKind.eve => 'Sınav arifesi: hafif tekrar, erken uyu',
      CountdownDayKind.study => day.focus?.label ?? 'Karışık tekrar',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TapCard(
        key: ValueKey('countdown-day-${day.index}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  day.index == 0 ? 'Bugün' : '${day.index + 1}. gün',
                  style: TextStyle(color: Brand.primary, fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 8),
                Text(_date(day.date), style: TextStyle(color: Brand.muted, fontSize: 13)),
              ],
            ),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final item in day.items)
              InkWell(
                onTap: () => openPlanLink(context, ref, item, lastSource: lastSource),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(_icon(item.kind), size: 20, color: Brand.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item.title)),
                      Icon(Icons.chevron_right_rounded, color: Brand.muted),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(PlanItemKind k) => switch (k) {
    PlanItemKind.lesson => Icons.menu_book_rounded,
    PlanItemKind.practice => Icons.quiz_rounded,
    PlanItemKind.mock => Icons.timer_rounded,
    PlanItemKind.report => Icons.insights_rounded,
    PlanItemKind.notebook => Icons.edit_note_rounded,
    PlanItemKind.review => Icons.replay_rounded,
  };
}

class _LockedRest extends StatelessWidget {
  const _LockedRest({required this.days, required this.onUnlock});
  final int days;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('countdown-locked'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Brand.accentBg, borderRadius: BorderRadius.circular(16)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lock_rounded, color: Brand.ink),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Kalan $days günün planı Premium\'da',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Bugünün planı ücretsiz. Premium ile sınava kadar her gün, zayıf soru tiplerine göre güncellenen '
          'planın ve sınırsız tam deneme açılır.',
          style: TextStyle(height: 1.35),
        ),
        const SizedBox(height: 10),
        FilledButton(onPressed: onUnlock, child: const Text('Planın tamamını aç')),
      ],
    ),
  );
}

/// Opens what a plan item points at, with the app's existing screens.
Future<void> openPlanLink(BuildContext context, WidgetRef ref, PlanLink item, {String? lastSource}) async {
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  switch (item.kind) {
    case PlanItemKind.lesson:
      final path = await ref.read(examPathProvider('yds').future);
      final unit = path?.units.where((u) => u.id == item.ref).firstOrNull;
      final lessons = unit?.nodes.where((n) => n.type == NodeType.lesson).toList() ?? const <PathNode>[];
      if (unit == null || lessons.isEmpty) return;
      final p = ref.read(progressProvider);
      final node = lessons.where((n) => !p.isDone(n.id)).firstOrNull ?? lessons.first;
      await nav.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => LessonScreen.forNode(node, Brand.tone(unit.color)),
        ),
      );
    case PlanItemKind.practice:
      final exam = await ref.read(examProvider('yds').future);
      final section = exam.sections.where((s) => s.id == item.ref).firstOrNull;
      if (section == null) return;
      await nav.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ExamSessionScreen(
            exam: exam,
            questions: ([...section.questions]..shuffle()).take(10).toList(),
            mock: false,
            title: section.title,
          ),
        ),
      );
    case PlanItemKind.mock:
      if (!context.mounted) return;
      PracticeHubScreen.openPage(
        context,
        'Deneme sınavları',
        const ExamHomeScreen(examId: 'yds', view: ExamHomeView.mocks),
      );
    case PlanItemKind.report:
      if (lastSource == null) {
        messenger.showSnackBar(const SnackBar(content: Text('Önce bir tam deneme çöz.')));
        return;
      }
      await nav.push(MaterialPageRoute<void>(builder: (_) => MockReportScreen(source: lastSource)));
    case PlanItemKind.notebook:
      if (!context.mounted) return;
      openNotebook(context);
    case PlanItemKind.review:
      if (!context.mounted) return;
      await openReviewCards(context);
  }
}
