import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../theme.dart';
import 'lesson_result_screen.dart';
import 'path_screen.dart' show formatWait;

const baseLessonXp = 10;
const perfectBonusXp = 5;

const _praise = ['Harika!', 'Süper!', 'Doğru!', 'Çok iyi!', 'Mükemmel!'];

/// Runs one lesson: shows exercises in order, re-queues wrong answers at the
/// end, costs a heart per mistake and awards XP when every exercise is solved.
class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({super.key, required this.node, required this.color});
  final PathNode node;
  final Color color;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  late final List<Exercise> _queue = [...widget.node.exercises];
  late final int _total = _queue.length;
  final _started = DateTime.now();

  int _pos = 0;
  int _solved = 0;
  int _answered = 0;
  int _mistakes = 0;
  final Map<QuestMetric, int> _questStats = {};
  Grader? _grader;

  /// null while answering; true/false after "Kontrol et".
  bool? _lastCorrect;

  Exercise get _current => _queue[_pos];

  void _check() {
    final correct = _grader!.call();
    setState(() {
      _answered++;
      _lastCorrect = correct;
      if (correct) {
        _solved++;
        final metric = switch (_current.type) {
          ExerciseType.listen => QuestMetric.listen,
          ExerciseType.translate => QuestMetric.translate,
          ExerciseType.match => QuestMetric.match,
          _ => null,
        };
        if (metric != null) _questStats[metric] = (_questStats[metric] ?? 0) + 1;
      } else {
        _mistakes++;
        _queue.add(_current);
      }
    });
    if (!correct) ref.read(progressProvider.notifier).loseHeart();
  }

  void _skip() {
    setState(() => _solved++);
    _advance();
  }

  Future<void> _continue() async {
    if (_lastCorrect == false) {
      final now = ref.read(clockProvider)();
      final p = ref.read(progressProvider);
      if (p.heartsAt(now) == 0) {
        await _outOfHearts(p.nextHeartIn(now));
        return;
      }
    }
    _advance();
  }

  void _advance() {
    if (_pos + 1 >= _queue.length) {
      _finish();
      return;
    }
    setState(() {
      _pos++;
      _grader = null;
      _lastCorrect = null;
    });
  }

  void _finish() {
    final xp = baseLessonXp + (_mistakes == 0 ? perfectBonusXp : 0);
    final reward = ref.read(progressProvider.notifier).completeNode(
          widget.node.id,
          xp: xp,
          correct: _answered - _mistakes,
          answered: _answered,
          perfect: _mistakes == 0,
          stats: _questStats,
        );
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => LessonResultScreen(
        reward: reward,
        accuracy: _answered == 0 ? 100 : ((_answered - _mistakes) * 100 / _answered).round(),
        duration: DateTime.now().difference(_started),
        perfect: _mistakes == 0,
      ),
    ));
  }

  Future<void> _outOfHearts(Duration? wait) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('💔 Canın bitti', textAlign: TextAlign.center),
        content: Text(
          wait == null
              ? 'Biraz ara ver ve tekrar dene.'
              : 'Yeni can ${formatWait(wait)} sonra dolacak. Bu ders kaydedilmedi.',
          textAlign: TextAlign.center,
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam'))],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmQuit() async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Dersten çıkılsın mı?'),
        content: const Text('Bu dersteki ilerlemen kaydedilmeyecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Çık')),
          FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Devam et')),
        ],
      ),
    );
    if (quit == true && mounted) Navigator.of(context).pop();
  }

  Widget _exercise() {
    final ex = _current;
    final locked = _lastCorrect != null;
    void onReady(Grader? g) => setState(() => _grader = g);
    // Key by position so a re-queued exercise starts fresh.
    final key = ValueKey('$_pos-${ex.type}');
    return switch (ex.type) {
      ExerciseType.select => SelectExercise(key: key, ex: ex, locked: locked, onReady: onReady),
      ExerciseType.translate => TranslateExercise(key: key, ex: ex, locked: locked, onReady: onReady),
      ExerciseType.fillBlank => FillBlankExercise(key: key, ex: ex, locked: locked, onReady: onReady),
      ExerciseType.listen => ListenExercise(key: key, ex: ex, locked: locked, onReady: onReady),
      ExerciseType.match => MatchExercise(key: key, ex: ex, locked: locked, onReady: onReady),
      ExerciseType.speak =>
        SpeakExercise(key: key, ex: ex, locked: locked, onReady: onReady, onSkip: _skip),
    };
  }

  @override
  Widget build(BuildContext context) {
    final hearts = ref.watch(progressProvider).heartsAt(ref.watch(clockProvider)());
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.close, color: Brand.muted), onPressed: _confirmQuit),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: _solved / _total),
                          duration: const Duration(milliseconds: 300),
                          builder: (_, v, _) => LinearProgressIndicator(
                            value: v,
                            minHeight: 14,
                            color: widget.color,
                            backgroundColor: Brand.line,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Icon(Icons.favorite, color: Brand.heart),
                    const SizedBox(width: 4),
                    Text('$hearts',
                        style: const TextStyle(color: Brand.heart, fontWeight: FontWeight.w800, fontSize: 16)),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: _exercise(),
                ),
              ),
              _BottomPanel(
                correct: _lastCorrect,
                answer: _current.displayAnswer,
                praise: _praise[_answered % _praise.length],
                canCheck: _grader != null,
                onCheck: _check,
                onContinue: _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.correct,
    required this.answer,
    required this.praise,
    required this.canCheck,
    required this.onCheck,
    required this.onContinue,
  });

  final bool? correct;
  final String answer;
  final String praise;
  final bool canCheck;
  final VoidCallback onCheck;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    if (correct == null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.line, width: 2))),
        child: FilledButton(
          onPressed: canCheck ? onCheck : null,
          child: const Text('KONTROL ET'),
        ),
      );
    }
    final ok = correct!;
    final fg = ok ? Brand.success : Brand.error;
    return Container(
      width: double.infinity,
      color: ok ? Brand.successBg : Brand.errorBg,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, color: fg, size: 30),
              const SizedBox(width: 10),
              Text(ok ? praise : 'Doğru cevap:',
                  style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w900)),
            ],
          ),
          if (!ok && answer.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 40),
              child: Text(answer, style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: fg),
            onPressed: onContinue,
            child: const Text('DEVAM'),
          ),
        ],
      ),
    );
  }
}
