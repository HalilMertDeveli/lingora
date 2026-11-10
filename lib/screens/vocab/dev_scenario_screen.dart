import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tr_errors.dart';
import '../../data/dev_scenarios.dart';
import '../../data/practice.dart';
import '../../data/progress.dart';
import '../../exercises/common.dart';
import '../../theme.dart';
import '../../ui/motion.dart';
import '../../ui/why_wrong.dart';
import '../conversation_screen.dart';
import 'vocab_home_screen.dart';

class DevScenarioListScreen extends ConsumerWidget {
  const DevScenarioListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('İş senaryoları')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Yaz, Türk hata dedektörüyle kontrol et, örnek cevapla karşılaştır. Ücretsiz. '
            'İstersen aynı senaryoyu yapay zekâyla canlı konuşarak da çalışabilirsin (Premium).',
            style: TextStyle(color: Brand.muted),
          ),
          const SizedBox(height: 12),
          for (final s in devScenarios)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TapCard(
                onTap: () => pushVocab(context, DevScenarioScreen(scenario: s)),
                child: Row(
                  children: [
                    Glyph(emoji: s.scenario.emoji, icon: devScenarioIcon(s.id), color: vocabColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.scenario.title, style: Theme.of(context).textTheme.titleMedium),
                          Text(s.scenario.goal, style: TextStyle(color: Brand.muted, fontSize: 13)),
                        ],
                      ),
                    ),
                    if (p.isDone(devScenarioNodeId(s.id)))
                      Icon(Icons.check_circle_rounded, color: Brand.success),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String devScenarioNodeId(String id) => 'sw_scn_$id';

/// Adult-mode icon per scenario (kid mode shows the scenario emoji).
IconData devScenarioIcon(String id) => switch (id) {
  'dev_standup' => Icons.groups_outlined,
  'dev_code_review' => Icons.rate_review_outlined,
  'dev_bug_ticket' => Icons.bug_report_outlined,
  'dev_commit' => Icons.commit_rounded,
  'dev_pr_description' => Icons.description_outlined,
  'dev_team_chat' => Icons.chat_bubble_outline_rounded,
  'dev_interview_intro' => Icons.record_voice_over_outlined,
  'dev_estimate' => Icons.timer_outlined,
  _ => Icons.forum_outlined,
};

/// Guided writing practice for one scenario.
class DevScenarioScreen extends ConsumerStatefulWidget {
  const DevScenarioScreen({super.key, required this.scenario});
  final DevScenario scenario;

  @override
  ConsumerState<DevScenarioScreen> createState() => _DevScenarioScreenState();
}

class _DevScenarioScreenState extends ConsumerState<DevScenarioScreen> {
  final _text = TextEditingController();
  List<TrError>? _errors;
  List<(String, bool)>? _checklist;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _check() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final errors = detectTrErrors(text);
    final notifier = ref.read(progressProvider.notifier)..recordTrErrors(errors);
    final first = _errors == null;
    setState(() {
      _errors = errors;
      _checklist = widget.scenario.review(text);
    });
    if (first) {
      notifier.completeNode(devScenarioNodeId(widget.scenario.id), xp: practiceXp, answered: 1, correct: 1);
    }
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scenario;
    return Scaffold(
      appBar: AppBar(title: Text('${kidEmoji(s.scenario.emoji)}${s.scenario.title}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(s.task, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.35)),
          const SizedBox(height: 12),
          const SectionLabel('İŞE YARAYAN KALIPLAR'),
          const SizedBox(height: 6),
          for (final ph in s.phrases)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: ph.en,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: '  ${ph.tr}',
                      style: TextStyle(color: Brand.muted),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('scenarioInput'),
            controller: _text,
            minLines: 4,
            maxLines: 10,
            maxLength: 800,
            decoration: InputDecoration(hintText: s.placeholder),
          ),
          PressableButton(
            label: _errors == null ? 'KONTROL ET' : 'TEKRAR KONTROL ET',
            color: vocabColor,
            onPressed: _check,
          ),
          if (_errors != null) ...[
            const SizedBox(height: 16),
            if (_errors!.isEmpty)
              Text(
                '${kidEmoji('🔍')}Türk hata dedektörü tipik bir hata bulmadı.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              )
            else
              Container(
                decoration: BoxDecoration(color: Brand.errorBg, borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.all(4),
                child: WhyWrongSection(errors: _errors!, maxErrors: 5),
              ),
            const SizedBox(height: 12),
            const SectionLabel('KONTROL LİSTESİ'),
            for (final (label, ok) in _checklist!)
              Row(
                children: [
                  Icon(
                    ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    color: ok ? Brand.success : Brand.muted,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(label),
                ],
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(Radii.md)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Örnek cevap', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                      SpeakerButton(text: s.modelAnswer, size: 36),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(s.modelAnswer, key: const Key('modelAnswer'), style: const TextStyle(height: 1.4)),
                  const SizedBox(height: 6),
                  Text(s.modelAnswerTr, style: TextStyle(color: Brand.muted, height: 1.35)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          PressableButton(
            label: 'Canlı konuş: ${s.scenario.partner} (Premium)',
            outlined: true,
            onPressed: () => openConversation(context, ref, s.scenario),
          ),
        ],
      ),
    );
  }
}
