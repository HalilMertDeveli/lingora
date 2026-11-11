import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';
import '../data/course_repository.dart';
import '../data/placement.dart';
import '../data/progress.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import 'grammar_path_screen.dart' show grammarLessonsProvider, levelColor;

/// Called when the user picks a plan on the result screen.
typedef PlacementDone = void Function(BuildContext context, PlacementRecommendation plan);

/// General-course units as node-id lists, for the recommendation.
final placementCourseUnitsProvider = FutureProvider<List<List<String>>>((ref) async {
  final course = await loadCourse(rootBundle, defaultTrackId);
  return [
    for (final u in course.units) [for (final n in u.nodes) n.id],
  ];
});

/// "Neden İngilizce öğreniyorsun?" choices.
class ReasonPicker extends StatelessWidget {
  const ReasonPicker({super.key, required this.selected, required this.onChanged});
  final LearnReason selected;
  final ValueChanged<LearnReason> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        for (final r in LearnReason.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TapCard(
              selected: r == selected,
              onTap: () => onChanged(r),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Text(r.emoji, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.title, style: t.titleMedium),
                        Text(r.subtitle, style: t.bodySmall?.copyWith(color: Brand.muted)),
                      ],
                    ),
                  ),
                  if (r == selected) Icon(Icons.check_circle, color: Brand.primary),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Re-take entry from the profile: pick a reason, then start the test.
class PlacementIntroScreen extends ConsumerStatefulWidget {
  const PlacementIntroScreen({super.key});

  @override
  ConsumerState<PlacementIntroScreen> createState() => _PlacementIntroScreenState();
}

class _PlacementIntroScreenState extends ConsumerState<PlacementIntroScreen> {
  late LearnReason _reason = ref.read(placementProvider)?.reason ?? LearnReason.general;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Seviye testi')),
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
                    Text('Neden İngilizce öğreniyorsun?', style: t.headlineSmall),
                    const SizedBox(height: 6),
                    Text(
                      'En fazla $placementMaxQuestions soru, yaklaşık 5 dakika. Sorular cevaplarına göre '
                      'kolaylaşır ya da zorlaşır. Hiçbir ders kilitlenmez.',
                      style: t.bodyMedium?.copyWith(color: Brand.muted),
                    ),
                    const SizedBox(height: 16),
                    ReasonPicker(selected: _reason, onChanged: (r) => setState(() => _reason = r)),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => PlacementTestScreen(reason: _reason, onDone: _applyFromProfile),
                  ),
                ),
                child: const Text('Teste başla'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _applyFromProfile(BuildContext context, PlacementRecommendation plan) {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  Navigator.of(context).popUntil((r) => r.isFirst);
  applyPlacement(container.read(progressProvider.notifier), plan);
  messenger.showSnackBar(SnackBar(content: Text('${trackById(plan.trackId).title} seçildi.')));
}

/// The adaptive test itself.
class PlacementTestScreen extends ConsumerStatefulWidget {
  const PlacementTestScreen({super.key, required this.reason, required this.onDone});
  final LearnReason reason;
  final PlacementDone onDone;

  @override
  ConsumerState<PlacementTestScreen> createState() => _PlacementTestScreenState();
}

class _PlacementTestScreenState extends ConsumerState<PlacementTestScreen> {
  PlacementSession? _session;
  PlacementQuestion? _shown;
  int? _picked;

  /// Set once the shown question has been answered.
  bool? _ok;

  void _check({bool unknown = false}) {
    final s = _session!;
    setState(() => _ok = s.answer(unknown ? -1 : _picked!));
    if (unknown) _picked = -1;
  }

  void _continue() {
    final s = _session!;
    if (s.isFinished) {
      final level = s.estimate;
      ref.read(placementProvider.notifier).save(level, widget.reason);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PlacementResultScreen(
            level: level,
            reason: widget.reason,
            correct: s.answers.where((a) => a.$2).length,
            total: s.answers.length,
            onDone: widget.onDone,
          ),
        ),
      );
      return;
    }
    setState(() {
      _shown = s.current;
      _picked = null;
      _ok = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bank = ref.watch(placementBankProvider);
    if (_session == null && bank.hasValue) {
      _session = PlacementSession(bank.requireValue);
      _shown = _session!.current;
    }
    final s = _session;
    final q = _shown;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Testi kapat',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: s == null ? 0 : s.answers.length / placementMaxQuestions,
            minHeight: 10,
            backgroundColor: Brand.line,
          ),
        ),
      ),
      body: SafeArea(
        child: s == null || q == null
            ? Center(
                child: bank.hasError ? const Text('Sorular yüklenemedi.') : const CircularProgressIndicator(),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  children: [
                    Expanded(child: _question(context, q)),
                    if (_ok == null) ...[
                      FilledButton(
                        onPressed: _picked == null ? null : _check,
                        child: const Text('Kontrol et'),
                      ),
                      TextButton(onPressed: () => _check(unknown: true), child: const Text('Bilmiyorum')),
                    ] else
                      _Feedback(question: q, ok: _ok!, onContinue: _continue),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _question(BuildContext context, PlacementQuestion q) {
    final t = Theme.of(context).textTheme;
    final skill = switch (q.skill) {
      PlacementSkill.grammar => 'DİL BİLGİSİ',
      PlacementSkill.vocabulary => 'KELİME',
      PlacementSkill.reading => 'OKUMA',
    };
    return ListView(
      children: [
        Text(
          skill,
          style: t.labelLarge?.copyWith(color: Brand.primary, fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        if (q.passage != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(14)),
            child: Text(q.passage!, style: t.bodyLarge?.copyWith(height: 1.4)),
          ),
          const SizedBox(height: 12),
        ],
        Text(q.prompt, style: t.titleLarge),
        const SizedBox(height: 16),
        for (var i = 0; i < q.choices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TapCard(
              key: ValueKey('placement_choice_$i'),
              selected: _ok == null ? _picked == i : (i == q.answer || i == _picked),
              color: _ok == null ? null : (i == q.answer ? Brand.success : Brand.error),
              onTap: _ok == null ? () => setState(() => _picked = i) : null,
              child: Text(q.choices[i], style: t.titleMedium),
            ),
          ),
      ],
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.question, required this.ok, required this.onContinue});
  final PlacementQuestion question;
  final bool ok;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final fg = ok ? Brand.success : Brand.error;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ok ? Brand.successBg : Brand.errorBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Mascot(mood: ok ? Mood.happy : Mood.think, size: 48),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ok ? 'Doğru!' : 'Doğrusu: ${question.choices[question.answer]}',
                  style: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(question.explanation, style: TextStyle(color: Brand.ink)),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: fg),
            onPressed: onContinue,
            child: const Text('Devam'),
          ),
        ],
      ),
    );
  }
}

/// Level badge, explanation and the suggested plan.
class PlacementResultScreen extends ConsumerWidget {
  const PlacementResultScreen({
    super.key,
    required this.level,
    required this.reason,
    required this.correct,
    required this.total,
    required this.onDone,
  });

  final Cefr? level;
  final LearnReason reason;
  final int correct;
  final int total;
  final PlacementDone onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final units = ref.watch(placementCourseUnitsProvider);
    final lessons = ref.watch(grammarLessonsProvider);
    final ready = !units.isLoading && !lessons.isLoading;
    PlacementRecommendation planFor(Cefr? l) => recommend(
      level: l,
      reason: reason,
      courseUnits: units.value ?? const [],
      lessons: lessons.value ?? const [],
    );
    final plan = planFor(level);
    final track = trackById(plan.trackId);
    final color = level == null ? Brand.success : levelColor(level!.code);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Mascot(mood: level == null ? Mood.happy : Mood.cheer, size: 110),
                        const SizedBox(width: 12),
                        Container(
                          width: 92,
                          height: 92,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              if (Brand.isKid)
                                if (Brand.isKid)
                                  BoxShadow(color: color.withValues(alpha: 0.4), offset: const Offset(0, 5)),
                            ],
                          ),
                          child: Text(
                            level?.code ?? (Brand.isKid ? '🌱' : 'A0'),
                            style: TextStyle(
                              color: onColor(color),
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      level == null
                          ? 'Sıfırdan başlıyoruz'
                          : 'Tahmini seviyen: ${level!.code} · ${level!.name}',
                      textAlign: TextAlign.center,
                      style: t.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$total sorudan $correct doğru',
                      textAlign: TextAlign.center,
                      style: t.bodyMedium?.copyWith(color: Brand.muted),
                    ),
                    const SizedBox(height: 14),
                    Text(levelSummary(level), textAlign: TextAlign.center, style: t.bodyLarge),
                    const SizedBox(height: 20),
                    Text('Önerimiz', style: t.titleLarge),
                    const SizedBox(height: 10),
                    TapCard(
                      selected: true,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Text(track.emoji, style: const TextStyle(fontSize: 32)),
                        title: Text(track.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('${reason.emoji} ${reason.title} hedefin için buradan başla'),
                      ),
                    ),
                    if (plan.nextTrackId != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Temeller oturunca ${trackById(plan.nextTrackId!).title} bölümüne geçebilirsin.',
                        style: t.bodyMedium?.copyWith(color: Brand.muted),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (ready && (plan.knownUnits > 0 || plan.knownLessons > 0))
                      Text(
                        '${knownSummary(plan)} biliyor sayıyoruz. Hiçbir şey kilitlenmez; '
                        'istediğin an geri dönüp tekrar edebilirsin.',
                        style: t.bodyMedium,
                      ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: ready ? () => onDone(context, plan) : null,
                child: const Text('Bu planla başla'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: ready ? () => onDone(context, planFor(null)) : null,
                child: const Text('Sıfırdan başla'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String knownSummary(PlacementRecommendation plan) => [
  if (plan.knownUnits > 0) "Genel İngilizce'de ilk ${plan.knownUnits} üniteyi",
  if (plan.knownLessons > 0) "Gramer Yolu'nda ${plan.knownLessons} dersi",
].join(' ve ');

/// Profile card: last result and a button to take the test again.
class PlacementProfileCard extends ConsumerWidget {
  const PlacementProfileCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(placementProvider);
    final t = Theme.of(context).textTheme;
    final last = record == null
        ? 'Henüz test çözmedin.'
        : 'Son sonuç: ${record.level == null ? 'Başlangıç' : '${record.level!.code} · ${record.level!.name}'}';
    return TapCard(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const PlacementIntroScreen())),
      child: Row(
        children: [
          Icon(Icons.speed_rounded, color: Brand.primary, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Seviyeni ölç', style: t.titleMedium),
                Text(last, style: t.bodySmall?.copyWith(color: Brand.muted)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Brand.muted),
        ],
      ),
    );
  }
}
