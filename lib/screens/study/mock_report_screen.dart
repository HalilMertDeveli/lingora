import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../study/analysis.dart';
import '../../study/question_types.dart';
import '../../study/study_state.dart';
import '../../theme.dart';
import 'methods_screen.dart';
import 'notebook_screen.dart';

/// Button for an exam result screen: opens the report of the attempt whose
/// answers were logged under [source].
class MockReportButton extends StatelessWidget {
  const MockReportButton({super.key, required this.source});
  final String source;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const Key('mock-report'),
    onPressed: () =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MockReportScreen(source: source))),
    icon: const Icon(Icons.insights_rounded),
    label: const Text('Tür ve süre raporu'),
  );
}

String _mmss(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// The mock report (yds-faz1-yontem §5): per question type right / wrong /
/// blank, time against the targets, the gap to the 72-right plan and what
/// to work on next.
class MockReportScreen extends ConsumerWidget {
  const MockReportScreen({super.key, required this.source});
  final String source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answers = ref.watch(studyLogProvider).answers.where((a) => a.source == source).toList();
    final report = MockReport(answers, mix: ExamMix.of(mockIdOf(source)));
    final t = Theme.of(context).textTheme;
    final slow = overTwoMinutes(answers);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deneme raporu'),
        actions: [
          IconButton(
            tooltip: 'Zaman yönetimi',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => openMethods(context, focus: 'time'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '${report.correct} / ${report.total} doğru · ${report.blank} boş',
            key: const Key('report-total'),
            style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(
            'Süre ${_mmss(report.seconds)} · hedef sürelerin toplamı ${_mmss(report.targetSeconds)}',
            style: TextStyle(color: Brand.muted),
          ),
          if (report.total == 80)
            Text(
              'YDS ölçeğinde ${(report.correct * ydsPointsPerQuestion).toStringAsFixed(2).replaceAll('.', ',')} puan',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          if (report.blank > 0) ...[
            const SizedBox(height: 8),
            const Text(
              'Yanlış doğruyu götürmez: boş bırakma, süre bitmeden işaretle.',
              key: Key('report-blank'),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          if (slow > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$slow soruda 2 dakikayı aştın. Böyle sorularda işaretle ve geç; sona kalan sürede dön.',
              key: const Key('report-slow'),
              style: TextStyle(color: Brand.tone(Brand.error)),
            ),
          ],
          const SizedBox(height: 16),
          const SectionLabel('SORU TİPLERİ'),
          const SizedBox(height: 8),
          for (final row in report.rows) _Row(row: row),
          const SizedBox(height: 16),
          const SectionLabel('72 DOĞRU HEDEFİNE GÖRE'),
          const SizedBox(height: 8),
          if (report.focus.isEmpty)
            const Text('Her türde hedefi tuttun. Harika!')
          else
            for (final r in report.focus.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${r.stat.type.label}: ${r.gap} doğru eksik '
                  '(${r.stat.correct} / hedef ${r.target.toStringAsFixed(r.target % 1 == 0 ? 0 : 1)})',
                ),
              ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('report-notebook'),
            onPressed: () => openNotebook(context),
            icon: const Icon(Icons.menu_book_rounded),
            label: const Text('Yanlışları hata defterinde incele'),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row});
  final MockRow row;

  @override
  Widget build(BuildContext context) {
    final s = row.stat;
    final slow = s.slow;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TapCard(
        key: Key('report-${s.type.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.type.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                    '${s.correct} D · ${s.wrong} Y · ${s.blank} B',
                    style: TextStyle(color: Brand.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'ort. ${s.avgSeconds.round()} sn',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: slow ? Brand.tone(Brand.error) : Brand.tone(Brand.success),
                  ),
                ),
                Text('hedef ${s.type.targetSeconds} sn', style: TextStyle(color: Brand.muted, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
