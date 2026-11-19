import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress.dart';
import '../../data/rehearsal.dart';
import '../../services/billing/premium.dart';
import '../../theme.dart';
import '../paywall_screen.dart';
import 'rehearsal_analysis_screen.dart';
import 'rehearsal_answer_screen.dart';
import 'rehearsal_exercise_screen.dart';

/// Route name of the Mülakat Provası home (for entry points elsewhere, e.g.
/// the interview goal in onboarding).
const rehearsalRouteName = '/prova';

/// Opens the Mülakat Provası home.
Future<void> openRehearsal(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    settings: const RouteSettings(name: rehearsalRouteName),
    builder: (_) => const RehearsalHomeScreen(),
  ),
);

/// Lets Premium users through; others see the paywall.
Future<bool> _premium(BuildContext context, WidgetRef ref) async =>
    await requirePremium(context, ref, PremiumFeature.interviewRehearsal, placement: rehearsalPlacement) ==
    GateResult.premium;

Future<void> _startFirst(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => const RehearsalAnswerScreen(
      kind: RehearsalKind.first,
      questions: firstRehearsalQuestions,
      title: 'İlk prova',
    ),
  ),
);

Future<void> startNewInterview(BuildContext context, WidgetRef ref) async {
  if (!await _premium(context, ref) || !context.mounted) return;
  final state = ref.read(rehearsalProvider);
  final questions = pickNewQuestions(state.askedQuestions, seed: state.sessions.length);
  if (questions.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Soru bankasındaki bütün soruları cevapladın. Yeni sorular yakında!')),
    );
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          RehearsalAnswerScreen(kind: RehearsalKind.interview, questions: questions, title: 'Yeni mülakat'),
    ),
  );
}

/// The Mülakat Provası home: start the first rehearsal (free), or continue
/// with today's study, a new interview and the first ↔ latest comparison.
class RehearsalHomeScreen extends ConsumerWidget {
  const RehearsalHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rehearsalProvider);
    final p = context.palette;
    final premium = ref.watch(premiumProvider);
    final source = state.source;
    final pending = state.latest != null && state.latest!.analysis == null ? state.latest : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Mülakat provası')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (state.sessions.isEmpty) ...[
            Text(
              'İngilizce mülakata kendi cümlelerinle hazırlan',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Kendini ve bir projeni İngilizce anlat: sesli ya da yazarak. Çenebaz nerede takıldığını, '
              'hangi hatayı tekrarladığını gösterir; ertesi günün çalışması senin cevabından çıkar.',
            ),
            const SizedBox(height: 12),
            for (final s in const [
              '1. İlk prova: kendini ve bir projeni anlat (ücretsiz)',
              '2. Takıldığın yerler: eksik içerik ve tekrarlayan hatalar',
              '3. Bugünün provası: kendi cümlelerinden alıştırmalar',
              '4. Yeni mülakat: farklı sorularla aynı beceri',
              '5. İlk ↔ son prova: kayıtlarını yan yana dinle',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(s, style: TextStyle(color: p.muted)),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('prova-start'),
              icon: const Icon(Icons.mic_rounded),
              label: const Text('İlk provayı başlat'),
              onPressed: () => _startFirst(context),
            ),
            const SizedBox(height: 8),
            Text(
              'Ses kaydın yalnızca bu telefonda kalır (hesaptan çıkınca silinir); Çenebaz sunucusuna '
              'sadece yazıya dökülmüş metin gider. Konuşmayı telefonunun konuşma tanıma hizmeti '
              '(genellikle Google) yazıya çevirir.',
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          ] else ...[
            if (pending != null)
              _ActionTile(
                key: const Key('prova-pending'),
                icon: Icons.hourglass_bottom_rounded,
                title: 'Analiz bekleyen prova',
                subtitle: 'Cevabın kaydedildi; analiz edilemedi. Tekrar dene.',
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => _RetryAnalysis(session: pending))),
              ),
            if (source != null) ...[
              const RehearsalTodayCard(),
              const SizedBox(height: 8),
              _ActionTile(
                key: const Key('prova-last-analysis'),
                icon: Icons.insights_rounded,
                title: 'Son analiz',
                subtitle: source.analysis!.summaryTr,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => RehearsalAnalysisScreen(sessionId: source.id)),
                ),
              ),
            ],
            _ActionTile(
              key: const Key('prova-new-interview'),
              icon: Icons.record_voice_over_rounded,
              title: 'Yeni mülakat',
              subtitle: 'Hiç sorulmamış $followUpQuestionCount soru: öğrendiğini yeni durumda kullan.',
              locked: !premium,
              onTap: () => startNewInterview(context, ref),
            ),
            _ActionTile(
              key: const Key('prova-compare'),
              icon: Icons.compare_arrows_rounded,
              title: 'İlk ↔ son prova',
              subtitle: state.sessions.length < 2
                  ? 'İkinci provandan sonra kayıtlarını yan yana dinle.'
                  : 'Kayıtlarını dinle, metinleri ve hata sayılarını karşılaştır.',
              locked: !premium,
              onTap: state.sessions.length < 2
                  ? null
                  : () async {
                      if (!await _premium(context, ref) || !context.mounted) return;
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const RehearsalCompareScreen()));
                    },
            ),
          ],
        ],
      ),
    );
  }
}

class _RetryAnalysis extends StatelessWidget {
  const _RetryAnalysis({required this.session});
  final RehearsalSession session;

  @override
  Widget build(BuildContext context) => RehearsalAnswerScreen.retry(session: session);
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.locked = false,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool locked;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TapCard(
      onTap: onTap,
      child: Row(
        children: [
          IconBadge(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.palette.muted),
                ),
              ],
            ),
          ),
          ?trailing,
          if (locked && trailing == null) Icon(Icons.lock_rounded, size: 18, color: context.palette.muted),
        ],
      ),
    ),
  );
}

/// "Bugünün provası": the study built from the latest analysed answer. Shown
/// on the Pratik tab and the rehearsal home once there is an analysis.
class RehearsalTodayCard extends ConsumerWidget {
  const RehearsalTodayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rehearsalProvider);
    final source = state.source;
    if (source == null || context.isKid) return const SizedBox.shrink();
    final a = source.analysis!;
    final total = a.exercises.length + 1;
    final done = [
      for (var i = 0; i < a.exercises.length; i++) state.isDone(exerciseTaskId(source.id, i)),
      state.isDone(retellTaskId(source.id)),
    ].where((d) => d).length;
    final today = dayKey(ref.watch(clockProvider)()) == dayKey(source.at);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TapCard(
        key: const Key('prova-today-card'),
        onTap: () async {
          if (!await _premium(context, ref) || !context.mounted) return;
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RehearsalTodayScreen()));
        },
        child: Row(
          children: [
            const IconBadge(icon: Icons.work_outline_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bugünün provası', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    done == total
                        ? 'Hepsi tamam. Şimdi yeni bir mülakat dene.'
                        : '${today ? 'Yarının çalışması hazır' : 'Senin cevabından'}: ${a.exercises.length} alıştırma, '
                              '${lessonsForTags(a.tags).isEmpty ? '' : 'ilgili ders, '}yeniden anlat ($done/$total)',
                    style: TextStyle(color: context.palette.muted),
                  ),
                ],
              ),
            ),
            if (!ref.watch(premiumProvider)) Icon(Icons.lock_rounded, size: 18, color: context.palette.muted),
          ],
        ),
      ),
    );
  }
}

/// Today's study (Premium): exercises from the learner's own answer, the
/// related existing grammar lessons, and a retell of the same project.
class RehearsalTodayScreen extends ConsumerWidget {
  const RehearsalTodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rehearsalProvider);
    final source = state.source;
    final p = context.palette;
    if (source == null) return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    final a = source.analysis!;
    final project = source.answers.where((x) => x.questionId == 'project').firstOrNull;
    Widget mark(String taskId) {
      final t = state.tasks.where((t) => t.id == taskId).firstOrNull;
      if (t == null) return Icon(Icons.chevron_right_rounded, color: p.muted);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (t.unaided) Text('yardımsız ', style: TextStyle(color: p.success, fontSize: 12)),
          Icon(Icons.check_circle_rounded, color: p.success),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Bugünün provası')),
      body: ListView(
        key: const Key('prova-today'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text('Senin cevabından çıkan çalışma', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          const SectionLabel('1 · KENDİ CÜMLELERİN'),
          const SizedBox(height: 8),
          for (var i = 0; i < a.exercises.length; i++)
            _ActionTile(
              key: Key('prova-ex-$i'),
              icon: switch (a.exercises[i].kind) {
                ExerciseKind.fixSentence => Icons.build_rounded,
                ExerciseKind.fillBlank => Icons.short_text_rounded,
                ExerciseKind.reorder => Icons.swap_horiz_rounded,
              },
              title: a.exercises[i].instructionTr,
              subtitle: a.exercises[i].kind == ExerciseKind.reorder
                  ? a.exercises[i].words.join(' / ')
                  : a.exercises[i].prompt,
              trailing: mark(exerciseTaskId(source.id, i)),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RehearsalExerciseScreen(
                    taskId: exerciseTaskId(source.id, i),
                    exercise: a.exercises[i],
                    index: i,
                  ),
                ),
              ),
            ),
          if (lessonsForTags(a.tags).isNotEmpty) ...[
            const SizedBox(height: 12),
            const SectionLabel('2 · İLGİLİ DERS'),
            const SizedBox(height: 8),
            LessonLinks(tags: a.tags),
          ],
          const SizedBox(height: 16),
          const SectionLabel('3 · YENİDEN ANLAT'),
          const SizedBox(height: 8),
          _ActionTile(
            key: const Key('prova-retell'),
            icon: Icons.replay_rounded,
            title: 'Projeni yeniden anlat',
            subtitle: a.retellPromptTr,
            trailing: mark(retellTaskId(source.id)),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RehearsalAnswerScreen(
                  kind: RehearsalKind.retell,
                  title: 'Yeniden anlat',
                  taskId: retellTaskId(source.id),
                  questions: [
                    InterviewQuestion(
                      'retell',
                      QuestionCategory.technical,
                      project?.question ?? firstRehearsalQuestions.last.text,
                      a.retellChecklistTr.isEmpty ? a.retellPromptTr : a.retellChecklistTr.join(' · '),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (a.retellChecklistTr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text(
                'Kontrol listesi ipucunda: kullanırsan bu görev "yardımlı" sayılır.',
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// First vs latest rehearsal (Premium): both recordings, both transcripts and
/// only countable facts: repeated errors before and after, content gaps,
/// answer length and the tasks done without help.
class RehearsalCompareScreen extends ConsumerStatefulWidget {
  const RehearsalCompareScreen({super.key});

  @override
  ConsumerState<RehearsalCompareScreen> createState() => _RehearsalCompareScreenState();
}

class _RehearsalCompareScreenState extends ConsumerState<RehearsalCompareScreen> {
  AudioPlayer? _player;
  String? _playing;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _play(String path) async {
    final pl = _player ??= AudioPlayer();
    if (_playing == path) {
      await pl.stop();
      setState(() => _playing = null);
      return;
    }
    await pl.stop();
    setState(() => _playing = path);
    try {
      await pl.play(DeviceFileSource(path));
      pl.onPlayerComplete.first.then((_) {
        if (mounted && _playing == path) setState(() => _playing = null);
      });
    } catch (_) {
      if (mounted) setState(() => _playing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rehearsalProvider);
    final p = context.palette;
    if (state.sessions.length < 2) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Karşılaştırma için iki prova gerekli.')),
      );
    }
    final c = RehearsalComparison(state.first!, state.latest!, state.tasks);
    final unaidedAnswers = [
      // New interviews only: a retell is already a task above.
      for (final s in state.sessions.skip(1).where((s) => s.kind == RehearsalKind.interview))
        for (final a in s.answers)
          if (a.unaided) a,
    ];
    String date(DateTime d) => '${d.day}.${d.month}.${d.year}';

    Widget column(String label, RehearsalSession s, String key) => Expanded(
      child: Container(
        key: Key(key),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(date(s.at), style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 6),
            if (s.audioPath != null)
              OutlinedButton.icon(
                key: Key('$key-play'),
                icon: Icon(_playing == s.audioPath ? Icons.stop_rounded : Icons.play_arrow_rounded),
                label: Text(_playing == s.audioPath ? 'Durdur' : 'Dinle'),
                onPressed: () => _play(s.audioPath!),
              )
            else
              Text('Yazılı cevap', style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 6),
            Text('${s.wordCount} kelime', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final a in s.answers) ...[
              Text(a.question, style: TextStyle(color: p.muted, fontSize: 12)),
              Text(a.answer, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('İlk ↔ son prova')),
      body: ListView(
        key: const Key('prova-compare-screen'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              column('İlk prova', c.first, 'prova-first'),
              const SizedBox(width: 8),
              column('Son prova', c.latest, 'prova-latest'),
            ],
          ),
          const SizedBox(height: 20),
          const SectionLabel('SAYILARLA'),
          const SizedBox(height: 8),
          _Fact('Cevap uzunluğu', '${c.first.wordCount} → ${c.latest.wordCount} kelime'),
          _Fact('İçerik eksikleri', '${c.gapsBefore} → ${c.gapsAfter}'),
          for (final e in c.errorCounts)
            _Fact(grammarTagNames[e.tag] ?? e.tag, '${e.before} hata → ${e.after} hata'),
          for (final t in c.newTags)
            _Fact(grammarTagNames[t] ?? t, 'yeni: ${c.latest.analysis!.errorCount(t)} hata'),
          if (c.latest.analysis?.recurrenceNoteTr.isNotEmpty ?? false) ...[
            const SizedBox(height: 6),
            Text(c.latest.analysis!.recurrenceNoteTr),
          ],
          const SizedBox(height: 20),
          SectionLabel('YARDIMSIZ YAPTIKLARIN (${c.unaided.length + unaidedAnswers.length})'),
          const SizedBox(height: 4),
          Text(
            'İpucu, cevabı görme ya da ikinci deneme olmadan bitenler.',
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (c.unaided.isEmpty && unaidedAnswers.isEmpty)
            Text(
              'Henüz yok. Bugünün provasındaki alıştırmaları ilk denemede bitir.',
              style: TextStyle(color: p.muted),
            ),
          for (final t in c.unaided)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.check_rounded, color: p.success),
              title: Text(t.title),
              subtitle: Text(t.day),
            ),
          for (final a in unaidedAnswers)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.mic_rounded, color: p.success),
              title: Text('Cevap: ${a.question}'),
              subtitle: Text('${countWords(a.answer)} kelime, ipucusuz ve tek seferde'),
            ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
