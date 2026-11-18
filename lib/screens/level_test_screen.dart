import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';
import '../data/course_repository.dart';
import '../data/level_report.dart';
import '../data/placement.dart';
import '../data/progress.dart';
import '../services/speech.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import 'level_report_screen.dart';

/// Questions of the monthly test: the placement bank (grammar, vocabulary,
/// reading) and one question of each listening dialogue of the general
/// course. Tests override this with a small bank.
final levelTestBankProvider = FutureProvider<List<LevelItem>>((ref) async {
  final placement = await ref.watch(placementBankProvider.future);
  final course = await loadCourse(rootBundle, defaultTrackId);
  return [
    for (final q in placement) LevelItem.fromPlacement(q),
    ...listeningItems([for (final s in course.sections) ...s.nodes]),
  ];
});

/// Where each skill's staircase starts: last month's level for the skill,
/// else the placement level, else A2.
Map<LevelSkill, Cefr> levelTestStart(List<LevelReport> reports) {
  if (reports.isEmpty) return const {};
  final last = sortedReports(reports).last;
  return {for (final e in last.skills.entries) e.key: e.value.level ?? Cefr.a1};
}

/// Intro before the monthly test: what it measures, how long, the gate.
class LevelTestIntroScreen extends ConsumerWidget {
  const LevelTestIntroScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final reports = ref.watch(progressProvider.select((p) => p.levelReports));
    final now = ref.watch(clockProvider)();
    final open = canTakeLevelTest(reports, now);
    return Scaffold(
      appBar: AppBar(title: const Text('Aylık seviye testi')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    const Center(child: Mascot(mood: Mood.think, size: 90, decorative: true)),
                    const SizedBox(height: 12),
                    Text('Bu ayın seviyesini ölçelim', style: t.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      'Yaklaşık 15 dakika, ${LevelSkill.values.length * levelTestPerSkill} soru. Her beceride sorular '
                      'cevaplarına göre kolaylaşır ya da zorlaşır. Sonunda tahmini CEFR seviyeni ve beceri '
                      'karneni görürsün.',
                      style: t.bodyMedium?.copyWith(color: Brand.muted),
                    ),
                    const SizedBox(height: 16),
                    for (final s in LevelSkill.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Text(s.emoji, style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(s.title, style: t.titleMedium)),
                            Text('$levelTestPerSkill soru', style: TextStyle(color: Brand.muted)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Dinleme için sesin açık olsun. Şu an dinleyemiyorsan o bölümü atlayabilirsin; '
                      'karnede "ölçülmedi" yazar. Test ayda bir kez çözülür; yarıda bırakırsan hakkın gitmez.',
                      style: t.bodySmall?.copyWith(color: Brand.muted),
                    ),
                  ],
                ),
              ),
              FilledButton(
                key: const Key('level-test-start'),
                onPressed: open
                    ? () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (_) => const LevelTestScreen(),
                        ),
                      )
                    : null,
                child: Text(open ? 'Teste başla' : 'Sonraki test: ${longDateTr(nextLevelTestDay(reports)!)}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The monthly test itself. Answers are not marked one by one (it is a
/// measurement, not a lesson); the result comes at the end.
class LevelTestScreen extends ConsumerStatefulWidget {
  const LevelTestScreen({super.key});

  @override
  ConsumerState<LevelTestScreen> createState() => _LevelTestScreenState();
}

class _LevelTestScreenState extends ConsumerState<LevelTestScreen> {
  LevelTestSession? _session;
  LevelItem? _shown;
  int? _picked;
  final DateTime _started = DateTime.now();

  // Listening playback.
  late final LinePlayer _player = ref.read(linePlayerProvider);
  int _run = 0;
  bool _playing = false;
  int _plays = 0;

  /// The last answer is in: further taps (a double tap on "Testi bitir") do nothing.
  bool _finishing = false;

  /// An answer was taken and the next question is not drawn yet: a second
  /// tap in the same frame would answer a question the learner never saw.
  bool _answering = false;

  void _holdUntilNextFrame() {
    _answering = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _answering = false);
  }

  static const _maxPlays = 2;

  @override
  void dispose() {
    _run++;
    _player.stopLine();
    super.dispose();
  }

  void _start(List<LevelItem> bank) {
    final p = ref.read(progressProvider);
    final now = ref.read(clockProvider)();
    _session = LevelTestSession(
      bank,
      start: levelTestStart(p.levelReports),
      fallbackStart: ref.read(placementProvider)?.level ?? Cefr.a2,
      // A new order on every start: quitting halfway (which keeps the
      // month's attempt) must not show the same questions again.
      seed: now.millisecondsSinceEpoch ~/ 1000,
    );
    _shown = _session!.current;
  }

  Future<void> _play(LevelItem q) async {
    final piece = q.listening!;
    final run = ++_run;
    setState(() {
      _playing = true;
      _plays++;
    });
    for (final l in piece.lines) {
      if (run != _run || !mounted) return;
      await _player.sayLine(l.text, pitch: pitchFor(female: piece.speaker(l.speaker)?.female ?? true));
      if (run != _run || !mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (run != _run || !mounted) return;
    setState(() => _playing = false);
  }

  void _stopAudio() {
    _run++;
    _player.stopLine();
    _playing = false;
  }

  void _next() {
    final s = _session!;
    if (_finishing || _answering || s.isFinished) return;
    _holdUntilNextFrame();
    _stopAudio();
    s.answer(_picked ?? -1);
    _advance();
  }

  void _skipListening() {
    if (_finishing || _answering || _session!.isFinished) return;
    _holdUntilNextFrame();
    _stopAudio();
    _session!.skip(LevelSkill.listening);
    _advance();
  }

  void _advance() {
    final s = _session!;
    if (s.isFinished) {
      _finish();
      return;
    }
    setState(() {
      _shown = s.current;
      _picked = null;
      _plays = 0;
    });
  }

  void _finish() {
    if (_finishing) return;
    _finishing = true;
    final s = _session!;
    final now = ref.read(clockProvider)();
    final report = s.report(dayKey(now), seconds: DateTime.now().difference(_started).inSeconds);
    if (!ref.read(progressProvider.notifier).addLevelReport(report)) {
      // E.g. this month's test was already synced from another phone.
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Bu ayın testi zaten çözülmüş; bu sonuç karneye eklenmedi.')),
      );
    }
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute<void>(builder: (_) => const LevelReportScreen(justFinished: true)));
  }

  @override
  Widget build(BuildContext context) {
    final bank = ref.watch(levelTestBankProvider);
    if (_session == null && bank.hasValue) _start(bank.requireValue);
    final s = _session;
    final q = _shown;
    final started = s != null && s.answers.isNotEmpty && !_finishing;
    return PopScope(
      canPop: !started,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Testi kapat',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: s == null || s.planned == 0 ? 0 : s.answers.length / s.planned,
              minHeight: 10,
              backgroundColor: Brand.line,
            ),
          ),
        ),
        body: SafeArea(
          child: s == null || q == null
              ? Center(
                  child: bank.hasError
                      ? const Text('Sorular yüklenemedi.')
                      : const CircularProgressIndicator(),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    children: [
                      Expanded(child: _question(context, s, q)),
                      FilledButton(
                        key: const Key('level-next'),
                        onPressed: _picked == null ? null : _next,
                        child: Text(s.answers.length + 1 >= s.planned ? 'Testi bitir' : 'Devam'),
                      ),
                      TextButton(
                        onPressed: () {
                          if (_answering) return;
                          _picked = -1;
                          _next();
                        },
                        child: const Text('Bilmiyorum'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  /// Leaving halfway loses the answers (the month's attempt stays).
  Future<bool> _confirmLeave() async {
    _stopAudio();
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Testten çıkılsın mı?'),
        content: const Text(
          'Cevapların kaydedilmez. Bu ayın hakkın gitmez; testi sonra baştan çözebilirsin.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Devam et')),
          TextButton(
            key: const Key('level-leave'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Çık'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Widget _question(BuildContext context, LevelTestSession s, LevelItem q) {
    final t = Theme.of(context).textTheme;
    return ListView(
      children: [
        Row(
          children: [
            Text(
              '${q.skill.emoji}  ${q.skill.caps}',
              style: t.labelLarge?.copyWith(
                color: Brand.primary,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            Text('${s.answers.length + 1} / ${s.planned}', style: TextStyle(color: Brand.muted)),
          ],
        ),
        const SizedBox(height: 10),
        if (q.passage != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(14)),
            child: Text(q.passage!, style: t.bodyLarge?.copyWith(height: 1.4)),
          ),
          const SizedBox(height: 12),
        ],
        if (q.listening != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Diyaloğu dinle, sonra soruyu cevapla. En fazla $_maxPlays kez dinleyebilirsin.',
                  style: TextStyle(color: Brand.muted),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  key: const Key('level-play'),
                  onPressed: _playing || _plays >= _maxPlays ? null : () => _play(q),
                  icon: Icon(_playing ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded),
                  label: Text(
                    _playing
                        ? 'Çalıyor…'
                        : (_plays == 0 ? 'Dinle' : 'Bir kez daha dinle (${_maxPlays - _plays})'),
                  ),
                ),
                TextButton(
                  key: const Key('level-skip-listening'),
                  onPressed: _skipListening,
                  child: const Text('Şu an dinleyemiyorum, dinlemeyi atla'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(q.prompt, style: t.titleLarge),
        const SizedBox(height: 16),
        for (var i = 0; i < q.choices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TapCard(
              key: ValueKey('level_choice_$i'),
              selected: _picked == i,
              onTap: () => setState(() => _picked = i),
              child: Text(q.choices[i], style: t.titleMedium),
            ),
          ),
      ],
    );
  }
}
