import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/course_repository.dart';
import '../data/practice.dart';
import '../data/progress.dart';
import '../data/sections.dart';
import '../goals/learn_goal.dart';
import '../models/course.dart';
import '../study/review_queue.dart';
import '../study/study_state.dart';
import '../study/today_sequence.dart';
import '../theme.dart';
import '../ui/motion.dart';
import 'lesson_screen.dart';
import 'listening_screen.dart';
import 'reading_screen.dart';
import 'story_screen.dart';
import 'study/srs_review_screen.dart';
import 'study/today_screen.dart';

/// How many times each node had been completed when the day began, so the
/// card counts what was finished TODAY (Progress keeps only totals).
class DayBaseline {
  const DayBaseline(this.day, this.completed);
  final String day;
  final Map<String, int> completed;
}

const _baselineKey = 'today_baseline_v1';

class DayBaselineNotifier extends Notifier<DayBaseline?> {
  @override
  DayBaseline? build() {
    final raw = ref.read(prefsProvider).getString(_baselineKey);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return DayBaseline(j['day'] as String, Map<String, int>.from(j['completed'] as Map));
    } catch (_) {
      return null;
    }
  }

  /// Starts [day] from the current totals, once per day.
  void ensure(String day, Map<String, int> completed) {
    if (state?.day == day) return;
    state = DayBaseline(day, completed);
    ref.read(prefsProvider).setString(_baselineKey, jsonEncode({'day': day, 'completed': completed}));
  }
}

final dayBaselineProvider = NotifierProvider<DayBaselineNotifier, DayBaseline?>(DayBaselineNotifier.new);

/// Node ids finished today (their completion count grew since the start of
/// the day).
Set<String> finishedToday(Progress p, DayBaseline? base, String today) {
  if (base == null || base.day != today) return const {};
  return {
    for (final e in p.completed.entries)
      if (e.value > (base.completed[e.key] ?? 0)) e.key,
  };
}

/// New words a day: the study plan's, else the default.
final _newPerDayProvider = Provider<int>((ref) {
  final hasPlan = ref.watch(progressProvider.select((p) => p.studyPlan != null));
  if (!hasPlan) return defaultNewWordsPerDay;
  final plan = ref.watch(todayPlanProvider);
  return plan == null ? defaultNewWordsPerDay : newWordsPerDay(plan.week, plan.year);
});

/// The nodes the sequence would open: the next lesson and a listening piece.
typedef TodayTargets = ({PathNode? lesson, PathNode? listening});

TodayTargets todayTargets(Course course, Progress p, {PathNode? planNext}) {
  final lesson = planNext ?? currentNode(course, p);
  PathNode? listening;
  for (final n in course.allNodes) {
    if (n.type != NodeType.listening || p.isDone(n.id) || n.id == lesson?.id) continue;
    final open = activeNodes(course, p).values.any((a) => a.id == n.id) || listeningCatchUp(course, n, p);
    if (open) {
      listening = n;
      break;
    }
  }
  return (lesson: lesson, listening: listening);
}

final _targetsProvider = Provider<TodayTargets?>((ref) {
  final course = ref.watch(courseOutlineProvider).value;
  if (course == null) return null;
  final p = ref.watch(progressProvider);
  final planNext = p.studyPlan == null ? null : ref.watch(todayPlanProvider)?.next?.$2;
  return todayTargets(course, p, planNext: planNext);
});

/// Today's inputs from real data; null while the course loads.
final todayInputsProvider = Provider<TodayInputs?>((ref) {
  final targets = ref.watch(_targetsProvider);
  final course = ref.watch(courseOutlineProvider).value;
  if (targets == null || course == null) return null;
  final p = ref.watch(progressProvider);
  final today = dayKey(ref.watch(clockProvider)());
  final queue = ref.watch(reviewQueueProvider(ref.watch(_newPerDayProvider)));
  final log = ref.watch(studyLogProvider);
  final done = finishedToday(p, ref.watch(dayBaselineProvider), today);
  final types = {for (final n in course.allNodes) n.id: n.type};
  const lessonTypes = {NodeType.lesson, NodeType.test, NodeType.story};
  return TodayInputs(
    cardsDue: queue?.due.length ?? 0,
    mistakesDue: queue?.mistakes.length ?? 0,
    reviewedToday:
        p.wordLast.values.where((d) => d == today).length +
        log.answers.where((a) => a.day == today && a.source == 'practice').length,
    nextLesson: targets.lesson?.title,
    lessonsToday: done.where((id) => lessonTypes.contains(types[id])).length,
    listening: targets.listening?.title,
    listenedToday: done.any((id) => types[id] == NodeType.listening),
    readingWordsToday: p.readingWordsOn(today),
    goal: ref.watch(learnGoalProvider)?.kind,
  );
});

final todaySequenceProvider = Provider<TodaySequence?>((ref) {
  final inputs = ref.watch(todayInputsProvider);
  return inputs == null ? null : buildTodaySequence(inputs);
});

/// Opens [kind]'s activity. Returns false when there is nothing to open.
Future<bool> launchTodayStep(BuildContext context, WidgetRef ref, TodayStepKind kind) async {
  final nav = Navigator.of(context, rootNavigator: true);
  Future<void> full(Widget screen) =>
      nav.push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => screen));
  final p = ref.read(progressProvider);
  final today = dayKey(ref.read(clockProvider)());
  switch (kind) {
    case TodayStepKind.review:
      final queue = ref.read(reviewQueueProvider(ref.read(_newPerDayProvider)));
      if (queue != null && queue.due.isNotEmpty) {
        await openReviewCards(context, newPerDay: ref.read(_newPerDayProvider));
        return true;
      }
      final course = await ref.read(courseProvider.future);
      final items = mistakeItems(course, p.mistakesDue(today));
      if (items.isEmpty) return false;
      await full(
        LessonScreen(
          nodeId: 'practice',
          title: 'Hatalarını çalış',
          items: items,
          color: Brand.primary,
          mode: LessonMode.practice,
        ),
      );
      return true;
    case TodayStepKind.lesson || TodayStepKind.listening:
      final targets = ref.read(_targetsProvider);
      final id = (kind == TodayStepKind.lesson ? targets?.lesson : targets?.listening)?.id;
      if (id == null) return false;
      final course = await ref.read(courseProvider.future);
      for (final unit in course.units) {
        final node = unit.nodes.where((n) => n.id == id).firstOrNull;
        if (node == null) continue;
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
          case NodeType.listening:
            await full(ListeningScreen(node: node, color: color));
          case NodeType.chest:
            ref.read(progressProvider.notifier).completeNode(node.id, xp: node.rewardXp);
          case NodeType.mock:
            return false;
        }
        return true;
      }
      return false;
    case TodayStepKind.reading:
      await nav.push(MaterialPageRoute<void>(builder: (_) => const ReadingLibraryScreen()));
      return true;
  }
}

/// "Bugün ne yapacağım?" on top of the Öğren path: the day's short sequence,
/// one big BAŞLA that runs it back to back, and today's progress. With a
/// YDS study plan it also opens the full weekly plan (it replaced the
/// "Bugün" card on Pratik, so the two do not compete).
class TodayStartCard extends ConsumerWidget {
  const TodayStartCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seq = ref.watch(todaySequenceProvider);
    // Start counting today's work from here (once a day).
    final today = dayKey(ref.watch(clockProvider)());
    if (ref.watch(dayBaselineProvider)?.day != today) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ref.read(dayBaselineProvider.notifier).ensure(today, ref.read(progressProvider).completed);
        }
      });
    }
    if (seq == null || seq.isEmpty) return const SizedBox.shrink();
    final showPlan =
        ref.watch(trackProvider).id == 'yds' ||
        ref.watch(progressProvider.select((p) => p.studyPlan != null));
    final t = Theme.of(context).textTheme;
    final kid = context.isKid;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TapCard(
        key: const Key('today-start-card'),
        selected: !seq.allDone,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Side by side when they fit; the count drops under the title
            // otherwise (the largest font broke "yapacağı / m?", QA).
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  seq.allDone
                      ? (kid ? 'Bugünlük tamam! 🎉' : 'Bugünlük tamam')
                      : (kid ? 'Bugün ne yapalım?' : 'Bugün ne yapacağım?'),
                  style: t.titleMedium,
                ),
                Text(
                  '${seq.doneCount}/${seq.steps.length}${seq.allDone ? '' : ' · ~${seq.minutesLeft} dk'}',
                  key: const Key('today-progress'),
                  style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (i, s) in seq.steps.indexed) ...[
                  if (i > 0) Icon(Icons.arrow_forward_rounded, size: 16, color: Brand.muted),
                  _StepChip(step: s),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // Compact: the path's next step must stay on screen below it.
            Row(
              children: [
                Expanded(
                  child: GlossyProgress(
                    value: seq.steps.isEmpty ? 0 : seq.doneCount / seq.steps.length,
                    height: 8,
                    color: seq.allDone ? Brand.success : Brand.primary,
                  ),
                ),
                if (showPlan)
                  TextButton(
                    key: const Key('today-weekly-plan'),
                    onPressed: () => openToday(context),
                    child: const Text('YDS planı'),
                  ),
                if (!seq.allDone) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    flex: 2,
                    child: FilledButton(
                      key: const Key('today-start'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(64, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onPressed: () => Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (_) => const TodayRunScreen(),
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(seq.doneCount == 0 ? 'BAŞLA' : 'DEVAM ET', maxLines: 1),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.step});
  final TodayStep step;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('today-step-${step.kind.name}'),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: step.done ? Brand.successBg : Brand.line.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (step.done) ...[
          Icon(Icons.check_rounded, size: 16, color: Brand.success),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            step.title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: step.done ? Brand.success : null,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Runs today's steps one after another: each opens, and when it closes
/// done the next one opens by itself. A step left unfinished pauses the run.
class TodayRunScreen extends ConsumerStatefulWidget {
  const TodayRunScreen({super.key});

  @override
  ConsumerState<TodayRunScreen> createState() => _TodayRunScreenState();
}

class _TodayRunScreenState extends ConsumerState<TodayRunScreen> {
  /// The step that is open on top of this screen.
  TodayStepKind? _running;
  bool _paused = false;
  bool _wasCurrent = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runNext());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Rebuilt when this route becomes the top one again: the step closed.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current && !_wasCurrent && _running != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _stepClosed());
    }
    _wasCurrent = current;
  }

  void _stepClosed() {
    if (!mounted) return;
    final kind = _running;
    _running = null;
    final seq = ref.read(todaySequenceProvider);
    final step = seq?.steps.where((s) => s.kind == kind).firstOrNull;
    if (step != null && step.done) {
      // Done: a moment to see the tick, then the next one.
      setState(() => _message = null);
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted) _runNext();
      });
    } else {
      setState(() {
        _paused = true;
        _message = 'Yarıda kaldı. Hazır olunca devam et.';
      });
    }
  }

  Future<void> _runNext() async {
    if (!mounted) return;
    final seq = ref.read(todaySequenceProvider);
    final next = seq?.next;
    if (next == null) {
      setState(() => _paused = false);
      return;
    }
    setState(() {
      _paused = false;
      _running = next.kind;
      _message = null;
    });
    final opened = await launchTodayStep(context, ref, next.kind);
    if (!opened && mounted) {
      setState(() {
        _running = null;
        _paused = true;
        _message = 'Bu adımda şu an yapılacak bir şey yok.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final seq = ref.watch(todaySequenceProvider);
    final t = Theme.of(context).textTheme;
    final allDone = seq?.allDone ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Bugün')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                allDone ? 'Bugünlük tamam!' : 'Sırayla gidiyoruz',
                style: t.headlineSmall,
                key: const Key('today-run-title'),
              ),
              const SizedBox(height: 16),
              for (final s in seq?.steps ?? const <TodayStep>[])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TapCard(
                    key: Key('today-run-${s.kind.name}'),
                    selected: s.kind == _running || (!s.done && s.kind == seq?.next?.kind),
                    child: Row(
                      children: [
                        Icon(
                          s.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                          color: s.done ? Brand.success : Brand.muted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.kind.label, style: t.titleMedium),
                              if (s.detail.isNotEmpty)
                                Text(s.detail, style: TextStyle(color: Brand.muted, fontSize: 13)),
                            ],
                          ),
                        ),
                        Text('~${s.kind.minutes} dk', style: TextStyle(color: Brand.muted)),
                      ],
                    ),
                  ),
                ),
              if (_message case final m?)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(m, style: TextStyle(color: Brand.muted)),
                ),
              const Spacer(),
              if (allDone)
                PressableButton(
                  key: const Key('today-run-finish'),
                  label: 'BİTİR',
                  onPressed: () => Navigator.of(context).pop(),
                )
              else if (_paused)
                PressableButton(key: const Key('today-run-continue'), label: 'DEVAM ET', onPressed: _runNext),
            ],
          ),
        ),
      ),
    );
  }
}
