import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../ui/timeline.dart';
import 'lesson_result_screen.dart';
import 'lesson_screen.dart';
import 'notes_screen.dart' show TopicScreen;

Future<List<GrammarLesson>> loadLessons(AssetBundle bundle) async {
  final raw = jsonDecode(await bundle.loadString('assets/notes/lessons.json')) as List;
  return raw.map((l) => GrammarLesson.fromJson(l as Map<String, dynamic>)).toList();
}

final grammarLessonsProvider = FutureProvider<List<GrammarLesson>>((ref) => loadLessons(rootBundle));

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

/// All lessons as a path from A1 to C1. Nothing is locked; the next
/// unfinished lesson is highlighted.
class GrammarPathScreen extends ConsumerWidget {
  const GrammarPathScreen({super.key, required this.notes});
  final NotesBundle notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessons = ref.watch(grammarLessonsProvider);
    final p = ref.watch(progressProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Gramer Yolu')),
      body: lessons.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Dersler yüklenemedi: $e')),
        data: (all) {
          final done = all.where((l) => p.isDone(lessonNodeId(l))).length;
          final next = all.indexWhere((l) => !p.isDone(lessonNodeId(l)));
          final units = <String>{for (final l in all) l.unit}.toList();
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
                          'Notlarından hazırlanan, A1\'den C1\'e sıralı dersler.',
                          style: TextStyle(color: Brand.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              for (final unit in units) ...[
                const SizedBox(height: 18),
                _UnitBanner(unit: unit, level: all.firstWhere((l) => l.unit == unit).level),
                const SizedBox(height: 6),
                for (final l in all.where((l) => l.unit == unit))
                  _LessonTile(
                    lesson: l,
                    done: p.isDone(lessonNodeId(l)),
                    isNext: next >= 0 && all[next].id == l.id,
                    onTap: () {
                      logEventFrom(context, AnalyticsEvent.featureUse(AppFeature.grammar));
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (_) => GrammarLessonScreen(lesson: l, notes: notes),
                        ),
                      );
                    },
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _UnitBanner extends StatelessWidget {
  const _UnitBanner({required this.unit, required this.level});
  final String unit;
  final String level;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: context.lingora.hero(_levelColors[level] ?? Brand.primary),
    child: Text(
      unit,
      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
    ),
  );
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({required this.lesson, required this.done, required this.isNext, required this.onTap});
  final GrammarLesson lesson;
  final bool done;
  final bool isNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = levelColor(lesson.level);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TapCard(
        selected: isNext,
        color: c,
        onTap: onTap,
        child: Row(
          children: [
            Pulse(
              enabled: isNext,
              child: Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? Brand.success : c.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: done
                    ? Icon(Icons.check_rounded, color: onColor(Brand.success))
                    : context.isKid
                    ? Text(lesson.emoji, style: const TextStyle(fontSize: 22))
                    : Text(
                        lesson.level,
                        style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lesson.title, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    lesson.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Brand.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (isNext)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  'SIRADAKİ',
                  style: TextStyle(color: onColor(c), fontWeight: FontWeight.w900, fontSize: 11),
                ),
              ),
          ],
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
        _InfoBox(icon: '🧠', title: 'Hafıza ipucu', text: l.tip!, color: Brand.accent),
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
          _ExampleLine(en: f.example!, onSpeak: () => _speech.say(f.example!)),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final r in {for (final p in f.parts) p.role}.where((r) => r != PartRole.other))
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: roleColors[r], shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(roleNames[r]!, style: TextStyle(color: Brand.muted, fontSize: 12)),
                ],
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
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Lang('🇹🇷', 'TR'),
          const SizedBox(width: 6),
          Icon(Icons.compare_arrows_rounded, color: Brand.muted),
          const SizedBox(width: 6),
          const _Lang('🇬🇧', 'EN'),
          const SizedBox(width: 12),
          Expanded(child: Text(l.compare, style: const TextStyle(fontSize: 17, height: 1.5))),
        ],
      ),
    ],
  );

  Widget _notes() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('SENİN NOTUNDAN', 'Notion\'da böyle yazmıştın'),
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
                    Icon(
                      t.addedByApp ? Icons.auto_awesome_rounded : Icons.description_outlined,
                      size: 16,
                      color: Brand.muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${t.source} · ${t.title}',
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
            label: const Text('Notlarımdan ekstra alıştırma'),
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

class _ExampleLine extends StatelessWidget {
  const _ExampleLine({required this.en, required this.onSpeak});
  final String en;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton.filledTonal(onPressed: onSpeak, icon: const Icon(Icons.volume_up_rounded)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(en, style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic)),
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
