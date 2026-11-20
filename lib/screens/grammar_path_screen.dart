import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/legacy_emoji.dart';
import '../data/formula_colors.dart';
import '../data/notes_practice.dart';
import '../data/practice.dart';
import '../data/progress.dart';
import '../models/grammar_lesson.dart';
import '../models/notes.dart';
import '../services/speech.dart';
import '../services/growth/analytics.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import '../ui/tea_art.dart' show LanePainter;
import '../ui/timeline.dart';
import 'lesson_result_screen.dart';
import 'lesson_screen.dart';
import 'path_map.dart' show laneOffset, laneSwing;
import 'notes_screen.dart' show TopicScreen;

Future<List<GrammarLesson>> loadLessons(AssetBundle bundle) async {
  final raw = jsonDecode(await bundle.loadString('assets/notes/lessons.json')) as List;
  return raw.map((l) => GrammarLesson.fromJson(l as Map<String, dynamic>)).toList();
}

final grammarLessonsProvider = FutureProvider<List<GrammarLesson>>((ref) => loadLessons(appBundle));

String lessonNodeId(GrammarLesson l) => 'gl_${l.id}';

const _levelColors = {
  'A1': Color(0xFF1FA971),
  'A2': Color(0xFF2F80ED),
  'B1': Color(0xFF6C4CF1),
  'B2': Color(0xFFE5484D),
  'C1': Color(0xFF475467),
};

Color levelColor(String level) => Brand.tone(_levelColors[level] ?? Brand.primary);

const roleColors = {
  PartRole.subject: Color(0xFF2F80ED),
  PartRole.aux: Color(0xFFFF7A1A),
  PartRole.verb: Color(0xFF1FA971),
  PartRole.object: Color(0xFF9B51E0),
  PartRole.negative: Color(0xFFE5484D),
  PartRole.question: Color(0xFFF2A900),
  PartRole.other: Color(0xFF8A8799),
};

const roleNames = {
  PartRole.subject: 'özne',
  PartRole.aux: 'yardımcı',
  PartRole.verb: 'fiil',
  PartRole.object: 'nesne/tümleç',
  PartRole.negative: 'olumsuz',
  PartRole.question: 'soru',
  PartRole.other: '',
};

/// Levels of the grammar path, in learning order.
const grammarLevels = ['A1', 'A2', 'B1', 'B2', 'C1'];

int _levelRank(String level) {
  final i = grammarLevels.indexOf(level);
  return i < 0 ? grammarLevels.length : i;
}

/// The lessons in learning order: by level (A1 → C1), keeping the file's
/// order inside a level. The order is derived here; lessons.json is not
/// reordered.
List<GrammarLesson> orderedLessons(List<GrammarLesson> all) {
  final indexed = all.indexed.toList()
    ..sort((a, b) {
      final byLevel = _levelRank(a.$2.level).compareTo(_levelRank(b.$2.level));
      return byLevel != 0 ? byLevel : a.$1.compareTo(b.$1);
    });
  return [for (final (_, l) in indexed) l];
}

/// One level of the path ("A1 · Temeller") with its lessons in order.
class GrammarLevelGroup {
  const GrammarLevelGroup({required this.level, required this.title, required this.lessons});
  final String level;
  final String title;
  final List<GrammarLesson> lessons;

  int doneCount(Progress p) => lessons.where((l) => p.isDone(lessonNodeId(l))).length;
}

/// [ordered] lessons (see [orderedLessons]) grouped by level. The group is
/// named after the level's own unit ("A1 · Temeller"), else the level.
List<GrammarLevelGroup> grammarLevelGroups(List<GrammarLesson> ordered) {
  final byLevel = <String, List<GrammarLesson>>{};
  for (final l in ordered) {
    byLevel.putIfAbsent(l.level, () => []).add(l);
  }
  return [
    for (final MapEntry(key: level, value: lessons) in byLevel.entries)
      GrammarLevelGroup(
        level: level,
        title: lessons.map((l) => l.unit).firstWhere((u) => u.startsWith(level), orElse: () => level),
        lessons: lessons,
      ),
  ];
}

/// The first unfinished lesson in learning order, or null when all are done.
GrammarLesson? nextGrammarLesson(List<GrammarLesson> ordered, Progress p) =>
    ordered.where((l) => !p.isDone(lessonNodeId(l))).firstOrNull;

/// The lesson to suggest after [lesson]: the next unfinished one further on,
/// else the first unfinished one before it.
GrammarLesson? lessonAfter(List<GrammarLesson> ordered, GrammarLesson lesson, Progress p) {
  final i = ordered.indexWhere((l) => l.id == lesson.id);
  bool open(GrammarLesson l) => l.id != lesson.id && !p.isDone(lessonNodeId(l));
  return ordered.skip(i + 1).where(open).firstOrNull ?? ordered.take(max(0, i)).where(open).firstOrNull;
}

/// All lessons as a path from A1 to C1: numbered steps on a winding lane,
/// one section per level with its progress. Nothing is locked; the next
/// unfinished lesson is highlighted and the screen opens on it.
class GrammarPathScreen extends ConsumerStatefulWidget {
  const GrammarPathScreen({super.key, required this.notes});
  final NotesBundle notes;

  @override
  ConsumerState<GrammarPathScreen> createState() => _GrammarPathScreenState();
}

class _GrammarPathScreenState extends ConsumerState<GrammarPathScreen> {
  final _nextKey = GlobalKey();
  bool _scrolled = false;

  /// The lesson just finished here: the "Sıradaki konu" card then says so
  /// and suggests the step after it.
  GrammarLesson? _justDone;

  void _scrollToNext({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _nextKey.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: animate ? const Duration(milliseconds: 350) : Duration.zero,
      );
    });
  }

  Future<void> _open(GrammarLesson lesson, List<GrammarLesson> ordered) async {
    logEventFrom(context, AnalyticsEvent.featureUse(AppFeature.grammar));
    final wasDone = ref.read(progressProvider).isDone(lessonNodeId(lesson));
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => GrammarLessonScreen(lesson: lesson, notes: widget.notes),
      ),
    );
    if (!mounted) return;
    final p = ref.read(progressProvider);
    if (wasDone || !p.isDone(lessonNodeId(lesson))) return;
    setState(() => _justDone = lesson);
    _scrollToNext();
  }

  @override
  Widget build(BuildContext context) {
    final lessons = ref.watch(grammarLessonsProvider);
    final p = ref.watch(progressProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Gramer Yolu')),
      body: lessons.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Dersler yüklenemedi: $e')),
        data: (all) {
          final ordered = orderedLessons(all);
          final groups = grammarLevelGroups(ordered);
          final done = ordered.where((l) => p.isDone(lessonNodeId(l))).length;
          final justDone = _justDone;
          final next = justDone != null && p.isDone(lessonNodeId(justDone))
              ? lessonAfter(ordered, justDone, p)
              : nextGrammarLesson(ordered, p);
          final stepOf = {for (final (i, l) in ordered.indexed) l.id: i + 1};
          if (!_scrolled && next != null) {
            _scrolled = true;
            _scrollToNext(animate: false);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Row(
                children: [
                  const Mascot(mood: Mood.think, size: 70, decorative: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$done / ${all.length} ders', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 6),
                        GlossyProgress(
                          value: all.isEmpty ? 0 : done / all.length,
                          color: Brand.primary,
                          height: 12,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ders notlarından hazırlanan, A1\'den C1\'e sıralı dersler. '
                          'Sırayla ilerle; istediğin adımı yine de açabilirsin.',
                          style: TextStyle(color: Brand.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (next != null) ...[
                const SizedBox(height: 14),
                _ContinueCard(
                  lesson: next,
                  step: stepOf[next.id]!,
                  justDone: justDone,
                  onTap: () => _open(next, ordered),
                ),
              ],
              for (final g in groups) ...[
                const SizedBox(height: 18),
                _UnitBanner(
                  key: ValueKey('grammar-level-${g.level}'),
                  unit: g.title,
                  level: g.level,
                  progress: '${g.doneCount(p)}/${g.lessons.length}',
                ),
                const SizedBox(height: 10),
                _GrammarLane(
                  lessons: g.lessons,
                  level: g.level,
                  stepOf: stepOf,
                  isDone: (l) => p.isDone(lessonNodeId(l)),
                  next: next,
                  nextKey: _nextKey,
                  onTap: (l) => _open(l, ordered),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// "Sıradaki konu": the next unfinished step, one tap away.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.lesson, required this.step, required this.onTap, this.justDone});
  final GrammarLesson lesson;
  final int step;
  final VoidCallback onTap;

  /// The lesson just finished, if any: named above the suggestion.
  final GrammarLesson? justDone;

  @override
  Widget build(BuildContext context) {
    final c = levelColor(lesson.level);
    return TapCard(
      key: const ValueKey('grammar-continue'),
      selected: true,
      color: c,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (justDone != null) ...[
                  Text(
                    '${justDone!.title} tamam!',
                    key: const ValueKey('grammar-just-done'),
                    style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  'SIRADAKİ KONU · ADIM $step',
                  style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.1),
                ),
                const SizedBox(height: 2),
                Text(lesson.title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.play_circle_fill_rounded, color: c, size: 34),
        ],
      ),
    );
  }
}

class _UnitBanner extends StatelessWidget {
  const _UnitBanner({super.key, required this.unit, required this.level, required this.progress});
  final String unit;
  final String level;

  /// "6/16": finished lessons of the level.
  final String progress;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: context.lingora.hero(_levelColors[level] ?? Brand.primary),
    child: Row(
      children: [
        Expanded(
          child: Text(
            unit,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ),
        Text(
          progress,
          key: ValueKey('grammar-level-progress-$level'),
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

/// The lessons of one level as numbered steps on a winding lane (the same
/// S-curve as the learning path). A lesson from another unit of the level
/// ("Çeviri Atölyesi") gets a small label over its first step.
class _GrammarLane extends StatelessWidget {
  const _GrammarLane({
    required this.lessons,
    required this.level,
    required this.stepOf,
    required this.isDone,
    required this.next,
    required this.nextKey,
    required this.onTap,
  });

  final List<GrammarLesson> lessons;
  final String level;
  final Map<String, int> stepOf;
  final bool Function(GrammarLesson) isDone;
  final GrammarLesson? next;
  final GlobalKey nextKey;
  final void Function(GrammarLesson) onTap;

  static const _node = 60.0;
  static const _colWidth = 170.0;

  @override
  Widget build(BuildContext context) {
    final c = levelColor(level);
    final p = context.palette;
    final scaler = MediaQuery.textScalerOf(context);
    final titleRoom = scaler.scale(13) * 1.4 * 2 + 6;
    final tagRoom = scaler.scale(11) * 1.4 + 14;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final swing = laneSwing(w);
        final centres = <Offset>[];
        final rows = <Widget>[];
        var y = 0.0;
        for (final (i, l) in lessons.indexed) {
          final done = isDone(l);
          final isNext = next?.id == l.id;
          final newUnit = i > 0 && l.unit != lessons[i - 1].unit;
          final label = newUnit ? tagRoom : 0.0;
          final above = isNext ? tagRoom : 0.0;
          final height = label + above + _node + titleRoom + 10;
          final dx = laneOffset(i, mirror: _levelRank(level).isOdd) * swing;
          final left = (w / 2 + dx - _colWidth / 2).clamp(0.0, max(0.0, w - _colWidth)).toDouble();
          centres.add(Offset(w / 2 + dx, y + label + above + _node / 2));
          y += height;
          rows.add(
            SizedBox(
              key: isNext ? nextKey : null,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (newUnit)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: Text(
                        l.unit,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                    ),
                  Positioned(
                    left: left,
                    width: _colWidth,
                    top: label,
                    child: Column(
                      children: [
                        if (isNext)
                          Container(
                            height: tagRoom - 6,
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10)),
                            child: Text(
                              'SIRADAKİ',
                              style: TextStyle(color: onColor(c), fontWeight: FontWeight.w900, fontSize: 11),
                            ),
                          ),
                        _StepNode(
                          lesson: l,
                          step: stepOf[l.id]!,
                          done: done,
                          isNext: isNext,
                          color: c,
                          size: _node,
                          onTap: () => onTap(l),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          excludeFromSemantics: true,
                          onTap: () => onTap(l),
                          child: ExcludeSemantics(
                            // On the page colour, so the lane does not run through the words.
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Brand.background,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                l.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isNext ? FontWeight.w800 : FontWeight.w600,
                                  color: isNext ? c : Brand.ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: LanePainter(
                  points: centres,
                  lane: Color.alphaBlend(c.withValues(alpha: p.isDark ? 0.12 : 0.08), p.surface),
                  dash: c.withValues(alpha: 0.45),
                ),
              ),
            ),
            Column(children: rows),
          ],
        );
      },
    );
  }
}

/// One step of the grammar path: the step number in a circle (the lesson's
/// emoji in kid mode), a check when done, filled when it is next.
class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.lesson,
    required this.step,
    required this.done,
    required this.isNext,
    required this.color,
    required this.size,
    required this.onTap,
  });

  final GrammarLesson lesson;
  final int step;
  final bool done;
  final bool isNext;
  final Color color;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = color;
    final fill = done
        ? Brand.success
        : (isNext ? c : Color.alphaBlend(c.withValues(alpha: 0.12), Brand.card));
    final fg = done || isNext ? onColor(fill) : c;
    return Semantics(
      button: true,
      label: 'Adım $step: ${lesson.title}',
      value: done ? 'Bitti' : (isNext ? 'Sıradaki' : null),
      child: JellyPress(
        amount: 0.8,
        onTap: onTap,
        child: Pulse(
          enabled: isNext,
          child: Container(
            key: ValueKey('grammar-step-${lesson.id}'),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(color: isNext ? Brand.card : c.withValues(alpha: 0.35), width: 3),
              boxShadow: isNext ? [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 14)] : null,
            ),
            child: done
                ? Icon(Icons.check_rounded, color: fg, size: 30)
                : context.isKid
                ? Text(lesson.emoji, style: const TextStyle(fontSize: 24))
                : ExcludeSemantics(
                    child: Text(
                      '$step',
                      style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

enum _Step { intro, formula, timeline, compare, notes, examples, mistakes, quiz }

/// One guided lesson, step by step.
class GrammarLessonScreen extends ConsumerStatefulWidget {
  const GrammarLessonScreen({super.key, required this.lesson, required this.notes});
  final GrammarLesson lesson;
  final NotesBundle notes;

  @override
  ConsumerState<GrammarLessonScreen> createState() => _GrammarLessonScreenState();
}

class _GrammarLessonScreenState extends ConsumerState<GrammarLessonScreen> {
  final _started = DateTime.now();
  late final List<GrammarTopic> _topics = [
    for (final id in widget.lesson.noteIds) ...widget.notes.topics.where((t) => t.id == id),
  ];
  late final List<NoteExample> _examples = () {
    final seen = <String>{};
    return [
      for (final t in _topics)
        for (final e in t.examples)
          if (seen.add(e.en)) e,
    ].take(8).toList();
  }();
  late final List<_Step> _steps = [
    _Step.intro,
    if (widget.lesson.formulas.isNotEmpty) _Step.formula,
    if (widget.lesson.timeline != null) _Step.timeline,
    _Step.compare,
    if (_topics.isNotEmpty) _Step.notes,
    if (_examples.isNotEmpty) _Step.examples,
    if (widget.lesson.mistakes.isNotEmpty) _Step.mistakes,
    if (widget.lesson.quiz.isNotEmpty) _Step.quiz,
  ];
  late final SpeechService _speech = ref.read(speechProvider);

  int _step = 0;
  int _formula = 0;
  final Set<int> _revealed = {};
  final Set<int> _flipped = {};

  // Quiz state.
  int _q = 0;
  int? _picked;
  int _correct = 0;
  int _shake = 0;

  GrammarLesson get l => widget.lesson;
  Color get _color => levelColor(l.level);
  bool get _onQuiz => _steps[_step] == _Step.quiz;

  void _next() {
    if (_onQuiz) {
      if (_picked == null) return;
      if (_q + 1 < l.quiz.length) {
        setState(() {
          _q++;
          _picked = null;
        });
        return;
      }
    }
    if (_step + 1 >= _steps.length) {
      _finish();
      return;
    }
    setState(() => _step++);
  }

  void _pick(int i) {
    if (_picked != null) return;
    final right = i == l.quiz[_q].answer;
    setState(() {
      _picked = i;
      if (right) {
        _correct++;
      } else {
        _shake++;
      }
    });
    right ? Haptics.success() : Haptics.error();
  }

  void _finish() {
    final total = l.quiz.length;
    final reward = ref
        .read(progressProvider.notifier)
        .completeNode(
          lessonNodeId(l),
          xp: 10 + _correct,
          answered: total,
          correct: _correct,
          perfect: _correct == total,
        );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LessonResultScreen(
          reward: reward,
          accuracy: total == 0 ? 100 : (_correct * 100 / total).round(),
          duration: DateTime.now().difference(_started),
          perfect: _correct == total,
          headline: '${l.title} tamam!',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final quizWaiting = _onQuiz && _picked == null;
    final isLast = _step == _steps.length - 1 && (!_onQuiz || _q == l.quiz.length - 1);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Kapat',
                    icon: Icon(Icons.close, color: Brand.muted),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: GlossyProgress(value: (_step + 1) / _steps.length, color: _color),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0.15, 0), end: Offset.zero).animate(a),
                    child: child,
                  ),
                ),
                layoutBuilder: (c, prev) => Stack(alignment: Alignment.topCenter, children: [...prev, ?c]),
                child: ListView(
                  key: ValueKey('$_step-${_onQuiz ? _q : 0}'),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [_stepView(step)],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Brand.line, width: 2)),
              ),
              child: PressableButton(
                label: isLast ? 'BİTİR' : (_onQuiz ? 'SONRAKİ SORU' : 'DEVAM'),
                color: _color,
                onPressed: quizWaiting ? null : _next,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(String kicker, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kicker,
          style: TextStyle(color: _color, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2),
        ),
        const SizedBox(height: 4),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
      ],
    ),
  );

  Widget _stepView(_Step s) => switch (s) {
    _Step.intro => _intro(),
    _Step.formula => _formulas(),
    _Step.timeline => _timeline(),
    _Step.compare => _compare(),
    _Step.notes => _notes(),
    _Step.examples => _examplesView(),
    _Step.mistakes => _mistakes(),
    _Step.quiz => _quiz(),
  };

  Widget _intro() => Column(
    children: [
      const SizedBox(height: 12),
      PopIn(
        child: context.isKid
            ? Text(l.emoji, style: const TextStyle(fontSize: 72))
            : IconBadge(icon: Icons.menu_book_outlined, color: _color, size: 64),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(8)),
        child: Text(
          l.level,
          style: TextStyle(color: onColor(_color), fontWeight: FontWeight.w900),
        ),
      ),
      const SizedBox(height: 10),
      Text(l.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 14),
      Text(l.summary, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, height: 1.45)),
      const SizedBox(height: 22),
      const Mascot(mood: Mood.happy, size: 110, decorative: true),
      if (l.tip != null) ...[
        const SizedBox(height: 16),
        _InfoBox(icon: legacyEmoji('🧠'), title: 'Hafıza ipucu', text: l.tip!, color: Brand.accent),
      ],
    ],
  );

  Widget _formulas() {
    final f = l.formulas[_formula];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('FORMÜL', 'Cümle nasıl kurulur?'),
        if (l.formulas.length > 1)
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < l.formulas.length; i++)
                ChoiceChip(
                  label: Text(l.formulas[i].label),
                  selected: i == _formula,
                  onSelected: (_) => setState(() => _formula = i),
                ),
            ],
          ),
        const SizedBox(height: 16),
        Wrap(
          key: ValueKey(_formula),
          spacing: 8,
          runSpacing: 14,
          children: [
            for (var i = 0; i < f.parts.length; i++)
              PopIn(
                delay: Duration(milliseconds: 120 * i),
                child: _Chip(part: f.parts[i]),
              ),
          ],
        ),
        if (f.example != null) ...[
          const SizedBox(height: 22),
          _ExampleLine(formula: f, onSpeak: () => _speech.say(f.example!)),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final r in {for (final p in f.parts) p.role}.where((r) => r != PartRole.other))
              // Text.rich (not a Row) so a long name wraps with large text.
              Text.rich(
                TextSpan(
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(color: roleColors[r], shape: BoxShape.circle),
                      ),
                    ),
                    TextSpan(text: roleNames[r]),
                  ],
                ),
                style: TextStyle(color: Brand.muted, fontSize: 12),
              ),
          ],
        ),
      ],
    );
  }

  Widget _timeline() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('ZAMAN ÇİZELGESİ', 'Eylem ne zaman oluyor?'),
      TenseTimeline(kind: l.timeline!, color: _color),
      if (l.timelineNote != null) ...[
        const SizedBox(height: 8),
        Text(l.timelineNote!, style: const TextStyle(fontSize: 16, height: 1.45)),
      ],
    ],
  );

  Widget _compare() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('TÜRKÇE İLE KARŞILAŞTIR', 'Biz nasıl söylüyoruz?'),
      // The TR ⇄ EN badges sit above the text so the text keeps the full
      // width on narrow screens and with large text; the badges only shrink
      // (never overflow) when even they do not fit.
      Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Lang('🇹🇷', 'TR'),
              const SizedBox(width: 6),
              Icon(Icons.compare_arrows_rounded, color: Brand.muted),
              const SizedBox(width: 6),
              const _Lang('🇬🇧', 'EN'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(l.compare, style: const TextStyle(fontSize: 17, height: 1.5)),
    ],
  );

  Widget _notes() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('DERS NOTLARINDAN', 'Bu konunun anlatımı'),
      for (final t in _topics)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TapCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TopicScreen(topic: t, all: widget.notes.topics),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.description_outlined, size: 16, color: Brand.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${t.category} · ${t.title}',
                        style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  t.body.split('\n\n').first,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, height: 1.45),
                ),
                for (final r in t.rules.take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $r', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 6),
                Text(
                  'Tamamını oku →',
                  style: TextStyle(color: _color, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _examplesView() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('ÖRNEKLER', 'Dokun, anlamını gör'),
      for (var i = 0; i < _examples.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TapCard(
            selected: _revealed.contains(i),
            color: _color,
            onTap: () {
              setState(() => _revealed.add(i));
              _speech.say(_examples[i].en);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_examples[i].en, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  child: _revealed.contains(i)
                      ? Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(_examples[i].tr, style: TextStyle(color: Brand.muted)),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _mistakes() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('YAYGIN HATALAR', 'Türklerin sık yaptığı hatalar'),
      for (var i = 0; i < l.mistakes.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => setState(() => _flipped.add(i)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _flipped.contains(i) ? Brand.successBg : Brand.errorBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.close_rounded, color: Brand.error, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l.mistakes[i].wrong,
                          style: TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: Brand.error,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_flipped.contains(i)) ...[
                    const SizedBox(height: 6),
                    PopIn(
                      from: 0.9,
                      child: Row(
                        children: [
                          Icon(Icons.check_rounded, color: Brand.success, size: 20),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l.mistakes[i].right,
                              style: TextStyle(
                                color: Brand.success,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(l.mistakes[i].why, style: const TextStyle(height: 1.4)),
                  ] else
                    Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Doğrusunu görmek için dokun',
                        style: TextStyle(color: Brand.muted, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  Widget _quiz() {
    final q = l.quiz[_q];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('MİNİ TEST · ${_q + 1}/${l.quiz.length}', q.q),
        Shake(
          trigger: _shake,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < q.options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TapCard(
                    selected: _picked != null && (i == q.answer || i == _picked),
                    color: _picked == null ? null : (i == q.answer ? Brand.success : Brand.error),
                    onTap: _picked == null ? () => _pick(i) : null,
                    child: Text(
                      q.options[i],
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_picked != null)
          PopIn(
            from: 0.9,
            child: _InfoBox(
              icon: _picked == q.answer ? '✅' : '💡',
              title: _picked == q.answer ? 'Doğru!' : 'Doğrusu: ${q.options[q.answer]}',
              text: q.why,
              color: _picked == q.answer ? Brand.success : Brand.error,
            ),
          ),
        if (_picked != null && _q == l.quiz.length - 1 && _topics.isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.fitness_center_rounded),
            label: const Text('Ders notlarından ekstra alıştırma'),
            onPressed: () {
              final items = <LessonItem>[for (final t in _topics) ...topicItems(t, widget.notes.topics)]
                ..shuffle(Random());
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => LessonScreen(
                    nodeId: 'gx_${l.id}',
                    title: l.title,
                    items: items.take(10).toList(),
                    color: _color,
                    mode: LessonMode.practice,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.part});
  final FormulaPart part;

  @override
  Widget build(BuildContext context) {
    final c = roleColors[part.role]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        border: Border.all(color: c, width: 2),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [if (Brand.isKid) BoxShadow(color: c.withValues(alpha: 0.5), offset: const Offset(0, 3))],
      ),
      child: Text(
        part.text,
        style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 17),
      ),
    );
  }
}

/// The formula's example sentence, each part painted with the same colour as
/// its chip above (subject blue, verb green…).
class _ExampleLine extends StatelessWidget {
  const _ExampleLine({required this.formula, required this.onSpeak});
  final Formula formula;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton.filledTonal(tooltip: 'Dinle', onPressed: onSpeak, icon: const Icon(Icons.volume_up_rounded)),
      const SizedBox(width: 8),
      Expanded(
        child: Text.rich(
          key: const ValueKey('formula-example'),
          TextSpan(
            children: [
              for (final s in colorExample(formula))
                TextSpan(
                  text: s.text,
                  style: s.role == null
                      ? null
                      : TextStyle(color: roleColors[s.role], fontWeight: FontWeight.w800),
                ),
            ],
          ),
          style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic),
        ),
      ),
    ],
  );
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.title, required this.text, required this.color});
  final String icon;
  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.isKid ? '$icon $title' : title,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(height: 1.4)),
      ],
    ),
  );
}

/// Flag in kid mode, a small language code chip in adult mode.
class _Lang extends StatelessWidget {
  const _Lang(this.flag, this.code);
  final String flag;
  final String code;

  @override
  Widget build(BuildContext context) {
    if (context.isKid) return Text(flag, style: const TextStyle(fontSize: 34));
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(6)),
      child: Text(
        code,
        style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}
