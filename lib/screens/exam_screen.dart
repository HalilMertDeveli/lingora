import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/text.dart';
import '../data/course_repository.dart';
import '../data/progress.dart';
import '../models/exam.dart';
import '../models/exam_pack.dart';
import '../services/billing/premium.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import 'exam_pack_screen.dart';
import 'paywall_screen.dart';

const _letters = ['A', 'B', 'C', 'D', 'E'];

/// Home of an exam track: mini mock exam plus practice by topic.
class ExamHomeScreen extends ConsumerWidget {
  const ExamHomeScreen({super.key, required this.examId});
  final String examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exam = ref.watch(examProvider(examId));
    return exam.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Sınav yüklenemedi: $e')),
      data: (e) => _ExamHome(exam: e),
    );
  }
}

class _ExamHome extends ConsumerWidget {
  const _ExamHome({required this.exam});
  final Exam exam;

  void _open(BuildContext context, List<ExamQuestion> qs, {required bool mock, String? title}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ExamSessionScreen(exam: exam, questions: qs, mock: mock, title: title ?? exam.title),
      ),
    );
  }

  /// Mini mock exams: [freeMockExamsPerDay] a day for free, unlimited with
  /// Premium. Topic practice is always free.
  Future<void> _startMock(BuildContext context, WidgetRef ref) async {
    if (!canStartMockExam(ref)) {
      final gate = await requirePremium(context, ref, PremiumFeature.unlimitedMockExams);
      if (gate != GateResult.premium || !context.mounted) return;
    }
    if (!ref.read(premiumProvider)) ref.read(mockExamQuotaProvider.notifier).recordStart();
    _open(context, _mockQuestions(), mock: true, title: 'Mini deneme');
  }

  /// A mock exam samples every section in proportion to its size.
  List<ExamQuestion> _mockQuestions() {
    final r = Random();
    final pools = [
      for (final s in exam.sections) [...s.questions]..shuffle(r),
    ];
    final picked = <ExamQuestion>[];
    for (var round = 0; picked.length < exam.mockSize; round++) {
      var added = false;
      for (final pool in pools) {
        if (round < pool.length && picked.length < exam.mockSize) {
          picked.add(pool[round]);
          added = true;
        }
      }
      if (!added) break;
    }
    return picked;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final best = ref.watch(progressProvider.select((p) => p.examBest[exam.id]));
    final premium = ref.watch(premiumProvider);
    final freeLeft = (freeMockExamsPerDay - ref.watch(mockExamQuotaProvider)).clamp(0, freeMockExamsPerDay);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: context.lingora.hero(Brand.primary, from: const Color(0xFF3B2FA8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exam.title,
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(exam.description, style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                      ],
                    ),
                  ),
                  const Mascot(mood: Mood.think, size: 76, decorative: true),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _Pill(Icons.quiz_rounded, '${exam.mockSize} soru'),
                  const SizedBox(width: 8),
                  _Pill(Icons.timer_rounded, '${exam.mockMinutes} dk'),
                  const SizedBox(width: 8),
                  if (best != null) _Pill(Icons.emoji_events_rounded, 'En iyi %$best'),
                ],
              ),
              const SizedBox(height: 14),
              PressableButton(
                label: 'MİNİ DENEME BAŞLAT',
                color: Brand.accent,
                foreground: Brand.ink,
                onPressed: () => _startMock(context, ref),
              ),
              if (!premium) ...[
                const SizedBox(height: 8),
                Text(
                  freeLeft > 0
                      ? 'Bugün $freeLeft ücretsiz deneme hakkın var. Konu çalışması her zaman ücretsiz.'
                      : 'Bugünkü ücretsiz denemeni kullandın. Yarın yenilenir; Premium ile sınırsız.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        if (ExamPack.forExam(exam.id) case final pack?) ...[
          const SizedBox(height: 22),
          ExamPackSection(exam: exam, pack: pack),
        ],
        const SizedBox(height: 22),
        Text('Konu çalış', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Her sorudan sonra Türkçe açıklama gösterilir.', style: TextStyle(color: Brand.muted)),
        const SizedBox(height: 12),
        for (final s in exam.sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TapCard(
              onTap: () => _open(context, [...s.questions]..shuffle(), mock: false, title: s.title),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title, style: Theme.of(context).textTheme.titleMedium),
                        if (s.description.isNotEmpty)
                          Text(s.description, style: TextStyle(color: Brand.muted, fontSize: 13)),
                      ],
                    ),
                  ),
                  Text(
                    '${s.questions.length} soru',
                    style: TextStyle(color: Brand.primary, fontWeight: FontWeight.w800),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Brand.muted),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Sorular Lingora tarafından sınav formatına uygun olarak hazırlanmıştır; '
          'resmî sınav soruları değildir.',
          style: TextStyle(color: Brand.muted, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 16),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ],
    ),
  );
}

/// Answers given in a session: question index → chosen option.
typedef ExamAnswers = Map<int, int>;

/// Practice (instant feedback + explanation) or timed mock exam (results at
/// the end).
class ExamSessionScreen extends ConsumerStatefulWidget {
  const ExamSessionScreen({
    super.key,
    required this.exam,
    required this.questions,
    required this.mock,
    required this.title,
    this.minutes,
    this.pack,
    this.fullMock,
  });

  final Exam exam;
  final List<ExamQuestion> questions;
  final bool mock;
  final String title;

  /// Time limit of a mock exam; defaults to the mini mock's.
  final int? minutes;

  /// Set for a full-length mock exam from a paid pack.
  final ExamPackContent? pack;
  final FullMock? fullMock;

  @override
  ConsumerState<ExamSessionScreen> createState() => _ExamSessionScreenState();
}

class _ExamSessionScreenState extends ConsumerState<ExamSessionScreen> {
  final ExamAnswers _answers = {};
  final _started = DateTime.now();
  int _pos = 0;
  int? _picked;
  bool _revealed = false;
  int _shake = 0;
  Timer? _timer;
  late int _secondsLeft = (widget.minutes ?? widget.exam.mockMinutes) * 60;

  ExamQuestion get _q => widget.questions[_pos];

  @override
  void initState() {
    super.initState();
    if (widget.mock) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _secondsLeft--);
        if (_secondsLeft <= 0) _finish();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _pick(int i) {
    if (_revealed) return;
    Haptics.tap();
    setState(() {
      // In a mock exam tapping the chosen option again clears it (blank).
      _picked = widget.mock && _picked == i ? null : i;
      if (widget.mock) {
        _picked == null ? _answers.remove(_pos) : _answers[_pos] = _picked!;
      }
    });
  }

  /// Mock exams: move freely between questions; blanks are allowed.
  void _goTo(int pos) {
    if (pos < 0 || pos >= widget.questions.length) return;
    setState(() {
      _pos = pos;
      _picked = _answers[pos];
    });
  }

  void _check() {
    final right = _picked == _q.answer;
    _answers[_pos] = _picked!;
    setState(() {
      _revealed = true;
      if (!right) _shake++;
    });
    right ? Haptics.success() : Haptics.error();
  }

  void _next() {
    if (widget.mock && _pos + 1 < widget.questions.length) {
      _goTo(_pos + 1);
      return;
    }
    if (_pos + 1 >= widget.questions.length) {
      _finish();
      return;
    }
    setState(() {
      _pos++;
      _picked = null;
      _revealed = false;
    });
  }

  void _finish() {
    if (_timer == null && widget.mock) return; // already finished
    _timer?.cancel();
    _timer = null;
    final qs = widget.questions;
    final correct = [
      for (final e in _answers.entries)
        if (qs[e.key].answer == e.value) e.key,
    ].length;
    final percent = qs.isEmpty ? 0 : (correct * 100 / qs.length).round();
    final notifier = ref.read(progressProvider.notifier);
    if (widget.mock) notifier.recordExam(widget.fullMock?.id ?? widget.exam.id, percent);
    final reward = notifier.completeNode(
      'exam_${widget.exam.id}',
      xp: max(5, correct),
      answered: _answers.length,
      correct: correct,
      perfect: correct == qs.length,
    );
    final pack = widget.pack, full = widget.fullMock;
    if (pack != null && full != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => FullMockResultScreen(
            pack: pack,
            mock: full,
            answers: _answers,
            xp: reward.xp,
            duration: DateTime.now().difference(_started),
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ExamResultScreen(
          exam: widget.exam,
          questions: qs,
          answers: _answers,
          xp: reward.xp,
          mock: widget.mock,
          duration: DateTime.now().difference(_started),
        ),
      ),
    );
  }

  Future<void> _confirmFinish() async {
    final blank = widget.questions.length - _answers.length;
    if (blank > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Deneme bitirilsin mi?'),
          content: Text('$blank soru boş. Bitirirsen boş sorular puanlanmaz.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Geri dön')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Bitir')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _finish();
  }

  Future<void> _quit() async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Çıkılsın mı?'),
        content: Text(
          widget.mock ? 'Deneme yarıda kalacak ve puanlanmayacak.' : 'Bu oturum kaydedilmeyecek.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Çık')),
          FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Devam et')),
        ],
      ),
    );
    if (quit == true && mounted) {
      _timer?.cancel();
      Navigator.of(context).pop();
    }
  }

  Color? _optionColor(int i) {
    if (!_revealed) return _picked == i ? Brand.primary : null;
    if (i == _q.answer) return Brand.success;
    if (i == _picked) return Brand.error;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    final mm = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final ss = (_secondsLeft % 60).toString().padLeft(2, '0');
    final right = _picked == q.answer;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _quit();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.close, color: Brand.muted),
                      onPressed: _quit,
                    ),
                    Expanded(
                      child: GlossyProgress(value: _pos / widget.questions.length, color: Brand.primary),
                    ),
                    const SizedBox(width: 12),
                    if (widget.mock)
                      Text(
                        '$mm:$ss',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: _secondsLeft < 60 ? Brand.error : Brand.ink,
                        ),
                      )
                    else
                      Text(
                        '${_pos + 1}/${widget.questions.length}',
                        style: TextStyle(fontWeight: FontWeight.w800, color: Brand.muted),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                  child: ListView(
                    key: ValueKey(_pos),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    children: [
                      Text(
                        widget.mock
                            ? '${trUpper(widget.title)} · SORU ${_pos + 1}/${widget.questions.length}'
                            : trUpper(widget.title),
                        style: TextStyle(
                          color: Brand.muted,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (q.passage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Brand.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(q.passage!, style: const TextStyle(fontSize: 15, height: 1.5)),
                        ),
                      Text(
                        q.text,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      Shake(
                        trigger: _shake,
                        child: Column(
                          children: [
                            for (var i = 0; i < q.options.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: TapCard(
                                  selected: _optionColor(i) != null,
                                  color: _optionColor(i),
                                  onTap: _revealed ? null : () => _pick(i),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 30,
                                        height: 30,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: (_optionColor(i) ?? Brand.line).withValues(alpha: 0.25),
                                        ),
                                        child: Text(
                                          _letters[i],
                                          style: const TextStyle(fontWeight: FontWeight.w900),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          q.options[i],
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_revealed)
                        PopIn(
                          from: 0.9,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: right ? Brand.successBg : Brand.errorBg,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  right ? 'Doğru!' : 'Doğru cevap: ${_letters[q.answer]}',
                                  style: TextStyle(
                                    color: right ? Brand.success : Brand.error,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(q.explanation, style: const TextStyle(height: 1.4)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Brand.line, width: 2)),
                ),
                child: widget.mock
                    ? Row(
                        children: [
                          if (_pos > 0) ...[
                            Expanded(
                              flex: 2,
                              child: PressableButton(
                                label: 'ÖNCEKİ',
                                outlined: true,
                                color: Brand.primary,
                                foreground: Brand.primary,
                                onPressed: () => _goTo(_pos - 1),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            flex: 3,
                            child: PressableButton(
                              label: _pos + 1 == widget.questions.length
                                  ? 'DENEMEYİ BİTİR'
                                  : (_picked == null ? 'BOŞ BIRAK' : 'SONRAKİ'),
                              onPressed: _pos + 1 == widget.questions.length ? _confirmFinish : _next,
                            ),
                          ),
                        ],
                      )
                    : PressableButton(
                        label: _revealed ? 'DEVAM' : 'KONTROL ET',
                        color: _revealed ? (right ? Brand.success : Brand.error) : Brand.success,
                        onPressed: _picked == null ? null : (_revealed ? _next : _check),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExamResultScreen extends StatelessWidget {
  const ExamResultScreen({
    super.key,
    required this.exam,
    required this.questions,
    required this.answers,
    required this.xp,
    required this.mock,
    required this.duration,
  });

  final Exam exam;
  final List<ExamQuestion> questions;
  final ExamAnswers answers;
  final int xp;
  final bool mock;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final correct = [
      for (var i = 0; i < questions.length; i++)
        if (answers[i] == questions[i].answer) i,
    ].length;
    final blank = questions.length - answers.length;
    final percent = questions.isEmpty ? 0 : (correct * 100 / questions.length).round();
    final good = percent >= 70;
    return Scaffold(
      body: Confetti(
        active: good,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(child: Mascot(mood: good ? Mood.cheer : Mood.think, size: 120)),
                    const SizedBox(height: 8),
                    Center(
                      child: CountUp(
                        value: percent,
                        prefix: '%',
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          color: good ? Brand.success : Brand.primary,
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        '$correct doğru · ${answers.length - correct} yanlış · $blank boş · +$xp XP',
                        style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        good ? 'Çok iyi gidiyorsun!' : 'Açıklamaları okuyup tekrar dene.',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (mock) ...[
                      Text('Cevap anahtarı', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      for (var i = 0; i < questions.length; i++)
                        _ReviewTile(index: i, q: questions[i], picked: answers[i]),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: PressableButton(label: 'DEVAM', onPressed: () => Navigator.of(context).pop()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.index, required this.q, required this.picked});
  final int index;
  final ExamQuestion q;
  final int? picked;

  @override
  Widget build(BuildContext context) {
    final ok = picked == q.answer;
    final color = picked == null ? Brand.muted : (ok ? Brand.success : Brand.error);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TapCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          shape: const Border(),
          leading: CircleAvatar(
            radius: 15,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(
              picked == null ? Icons.remove : (ok ? Icons.check : Icons.close),
              color: color,
              size: 18,
            ),
          ),
          title: Text('${index + 1}. ${q.text}', maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            picked == null
                ? 'Boş · doğru: ${_letters[q.answer]}'
                : 'Senin: ${_letters[picked!]} · doğru: ${_letters[q.answer]}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_letters[q.answer]}) ${q.options[q.answer]}',
              style: TextStyle(fontWeight: FontWeight.w800, color: Brand.success),
            ),
            const SizedBox(height: 6),
            Text(q.explanation, style: const TextStyle(height: 1.4)),
          ],
        ),
      ),
    );
  }
}
