import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tr_errors.dart';
import '../data/break_reminder.dart';
import '../data/practice.dart';
import '../data/progress.dart';
import '../data/quests.dart';
import '../exercises/common.dart';
import '../exercises/fill_blank_exercise.dart';
import '../exercises/listen_exercise.dart';
import '../exercises/match_exercise.dart';
import '../exercises/select_exercise.dart';
import '../exercises/speak_exercise.dart';
import '../exercises/translate_exercise.dart';
import '../models/course.dart';
import '../services/growth/analytics.dart';
import '../services/growth/paywall_trigger.dart';
import '../theme.dart';
import '../ui/motion.dart';
import '../ui/session.dart';
import '../ui/why_wrong.dart';
import '../nav/flow.dart';
import 'lesson_result_screen.dart';
import 'paywall_screen.dart';

const baseLessonXp = 10;
const perfectBonusXp = 5;

const _praise = ['Harika!', 'Süper!', 'Doğru!', 'Çok iyi!', 'Mükemmel!', 'Tam isabet!'];

/// Runs a lesson, unit test or mistakes review.
///
/// * lesson: wrong answers come back at the end (no hearts, no penalty).
/// * test: one try per question, pass with [testPassPercent].
/// * practice: wrong answers come back, correct ones clear the
///   saved mistake.
class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({
    super.key,
    required this.nodeId,
    required this.title,
    required this.items,
    required this.color,
    this.mode = LessonMode.lesson,
    this.rewardXp = 0,
    this.retry,
    this.badge,
    this.passHeadline,
  });

  /// Lesson for a path node.
  factory LessonScreen.forNode(PathNode node, Color color) =>
      LessonScreen(nodeId: node.id, title: node.title, items: lessonItems(node), color: color);

  final String nodeId;
  final String title;
  final List<LessonItem> items;
  final Color color;
  final LessonMode mode;

  /// XP for passing a test.
  final int rewardXp;

  /// Builds a fresh attempt (tests reshuffle their questions).
  final LessonScreen Function()? retry;

  /// Label above a test's questions; "ÜNİTE SINAVI" when null.
  final String? badge;

  /// Result headline after passing a test; "Ünite sınavını geçtin!" when null.
  final String? passHeadline;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  late final List<LessonItem> _queue = [...widget.items];
  late final int _total = _queue.length;
  final _started = DateTime.now();

  int _pos = 0;
  int _solved = 0;
  int _answered = 0;
  int _mistakes = 0;
  int _combo = 0;
  int _bestCombo = 0;
  int _shake = 0;
  final Map<QuestMetric, int> _questStats = {};
  Grader? _grader;

  /// null while answering; true/false after "Kontrol et".
  bool? _lastCorrect;

  /// English sentence the user built or typed (translate, listen).
  String _answerText = '';

  /// "Neden yanlış?" content after a wrong English answer.
  WhyWrongSection? _why;

  @override
  void initState() {
    super.initState();
    logEvent(ref, AnalyticsEvent.lessonStart(widget.nodeId, mode: widget.mode.name));
  }

  LessonItem get _current => _queue[_pos];
  bool get _requeues => widget.mode != LessonMode.test;

  /// Runs the Türk hata dedektörü on a wrong English answer.
  WhyWrongSection? _explain(Exercise ex) {
    final english = ex.type == ExerciseType.listen || (ex.type == ExerciseType.translate && ex.lang == 'tr');
    if (!english || _answerText.trim().isEmpty || ex.answers.isEmpty) return null;
    final expected = closestAnswer(_answerText, ex.answers);
    final errors = detectTrErrors(_answerText, expected: expected);
    ref.read(progressProvider.notifier).recordTrErrors(errors);
    final diff = answerWordDiff(_answerText, expected);
    final why = WhyWrongSection(errors: errors, missing: diff.missing, extra: diff.extra);
    return why.isEmpty ? null : why;
  }

  void _check() {
    final correct = _grader!.call();
    final notifier = ref.read(progressProvider.notifier);
    final why = correct ? null : _explain(_current.ex);
    setState(() {
      _why = why;
      _answered++;
      _lastCorrect = correct;
      if (correct) {
        _solved++;
        _combo++;
        if (_combo > _bestCombo) _bestCombo = _combo;
        final metric = switch (_current.ex.type) {
          ExerciseType.listen => QuestMetric.listen,
          ExerciseType.translate => QuestMetric.translate,
          ExerciseType.match => QuestMetric.match,
          _ => null,
        };
        if (metric != null) _questStats[metric] = (_questStats[metric] ?? 0) + 1;
      } else {
        _mistakes++;
        _combo = 0;
        _shake++;
        if (_requeues) {
          _queue.add(_current);
        } else {
          _solved++; // a test moves on regardless
        }
      }
    });
    if (correct) {
      SessionFx.correct();
      if (widget.mode == LessonMode.practice) notifier.clearMistake(_current.key);
    } else {
      SessionFx.wrong();
      notifier.addMistake(_current.key);
    }
  }

  void _skip() {
    setState(() => _solved++);
    _advance();
  }

  void _continue() => _advance();

  void _advance() {
    if (_pos + 1 >= _queue.length) {
      _finish();
      return;
    }
    setState(() {
      _pos++;
      _grader = null;
      _lastCorrect = null;
      _answerText = '';
      _why = null;
    });
  }

  int get _accuracy => _answered == 0 ? 100 : ((_answered - _mistakes) * 100 / _answered).round();

  void _finish() {
    final notifier = ref.read(progressProvider.notifier);
    final nav = Navigator.of(context);
    final perfect = _mistakes == 0;

    if (widget.mode == LessonMode.test && _accuracy < testPassPercent) {
      nav.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TestFailedScreen(
            accuracy: _accuracy,
            onRetry: widget.retry == null
                ? null
                : () => nav.pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => widget.retry!(), fullscreenDialog: true),
                  ),
          ),
        ),
      );
      return;
    }

    final xp = switch (widget.mode) {
      LessonMode.lesson => baseLessonXp + (perfect ? perfectBonusXp : 0),
      LessonMode.test => widget.rewardXp + (perfect ? perfectBonusXp : 0),
      LessonMode.practice => practiceXp,
    };
    final reward = notifier.completeNode(
      widget.nodeId,
      xp: xp,
      correct: _answered - _mistakes,
      answered: _answered,
      perfect: perfect,
      stats: _questStats,
    );
    logEvent(
      ref,
      AnalyticsEvent.lessonFinish(
        widget.nodeId,
        mode: widget.mode.name,
        accuracy: _accuracy,
        xp: reward.xp,
        durationSec: DateTime.now().difference(_started).inSeconds,
      ),
    );
    // Remote Config: a closable paywall after every N lessons (never blocks learning).
    final autoPaywall =
        widget.mode == LessonMode.lesson && ref.read(paywallTriggerProvider).takeAfterLesson();
    final duration = DateTime.now().difference(_started);
    final takeBreak = ref.read(breakTrackerProvider).recordLesson(duration);
    // Result, then streak, then daily goal and quests, then (after a run of lessons) a break reminder,
    // then (sometimes) a closable paywall; the last
    // "Devam" goes straight back to the path.
    showEndSequence(nav, [
      (next) => LessonResultScreen(
        reward: reward,
        accuracy: _accuracy,
        duration: duration,
        perfect: perfect,
        bestCombo: _bestCombo,
        showStreak: !reward.streakExtended,
        showQuests: !hasQuestStep(reward),
        onContinue: next,
        headline: switch (widget.mode) {
          LessonMode.test => widget.passHeadline ?? 'Ünite sınavını geçtin!',
          LessonMode.practice => 'Tekrar tamamlandı!',
          LessonMode.lesson => null,
        },
      ),
      ...celebrationSteps(reward),
      if (takeBreak) (next) => BreakReminderScreen(onContinue: next),
      if (autoPaywall) (_) => const PaywallScreen(placement: PaywallPlacement.afterLessons),
    ]);
  }

  Future<void> _confirmQuit() async {
    final quit = await confirmQuitFlow(
      context,
      title: widget.mode == LessonMode.test ? 'Sınavdan çıkılsın mı?' : 'Dersten çıkılsın mı?',
      detail: 'Bu dersteki ilerleme kaydedilmez; istediğin zaman baştan başlayabilirsin.',
    );
    if (quit && mounted) Navigator.of(context).pop();
  }

  Widget _exercise() {
    final ex = _current.ex;
    final locked = _lastCorrect != null;
    void onReady(Grader? g) => setState(() => _grader = g);
    void onText(String t) => _answerText = t;
    // Key by position so a re-queued exercise starts fresh.
    final key = ValueKey('$_pos-${ex.type}');
    return switch (ex.type) {
      ExerciseType.select => SelectExercise(key: key, ex: ex, locked: locked, onReady: onReady),
      ExerciseType.translate => TranslateExercise(
        key: key,
        ex: ex,
        locked: locked,
        onReady: onReady,
        onText: onText,
      ),
      ExerciseType.fillBlank => FillBlankExercise(key: key, ex: ex, locked: locked, onReady: onReady),
      ExerciseType.listen => ListenExercise(
        key: key,
        ex: ex,
        locked: locked,
        onReady: onReady,
        onText: onText,
      ),
      ExerciseType.match => MatchExercise(key: key, ex: ex, locked: locked, onReady: onReady),
      ExerciseType.speak => SpeakExercise(key: key, ex: ex, locked: locked, onReady: onReady, onSkip: _skip),
    };
  }

  Widget _header() {
    final Widget badge = switch (widget.mode) {
      LessonMode.lesson => Text(
        '${min(_solved, _total)}/$_total',
        style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w800, fontSize: 15),
      ),
      LessonMode.test => Icon(Icons.workspace_premium_rounded, color: Brand.accent, size: 28),
      LessonMode.practice => Icon(Icons.fitness_center_rounded, color: Brand.primary, size: 26),
    };
    return SessionHeader(
      progress: _solved / _total,
      color: widget.color,
      combo: _combo,
      onClose: _confirmQuit,
      trailing: badge,
      caption: switch (widget.mode) {
        LessonMode.lesson => null,
        LessonMode.test => widget.badge ?? 'ÜNİTE SINAVI',
        LessonMode.practice => 'HATALARINI ÇALIŞ',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 500),
                  switchInCurve: Curves.fastOutSlowIn,
                  switchOutCurve: Curves.fastOutSlowIn,
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                  transitionBuilder: (child, anim) {
                    final incoming = child.key == ValueKey(_pos);
                    final slide = Tween(begin: Offset(incoming ? 1 : -1, 0), end: Offset.zero).animate(anim);
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: SingleChildScrollView(
                    key: ValueKey(_pos),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Shake(trigger: _shake, child: _exercise()),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                child: _lastCorrect == null
                    ? CheckBar(key: const ValueKey('check'), onCheck: _grader != null ? _check : null)
                    : AnswerFeedbackPanel(
                        key: ValueKey('fb$_answered'),
                        correct: _lastCorrect!,
                        title: _lastCorrect!
                            ? (_combo >= comboThreshold
                                  ? '$_combo doğru üst üste!'
                                  : _praise[_answered % _praise.length])
                            : 'Doğru cevap:',
                        answer: _lastCorrect! ? null : _current.ex.displayAnswer,
                        detail: _lastCorrect! ? null : _why,
                        onContinue: _continue,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
