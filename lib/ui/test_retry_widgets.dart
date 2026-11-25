import 'package:flutter/material.dart';

import '../data/practice.dart' show testPassPercent;
import '../data/test_retry.dart';
import '../theme.dart';

/// Under the header of a retried test: which attempt this is and what help it
/// gets ("Bu denemede geçme sınırı %70").
class RetryBanner extends StatelessWidget {
  const RetryBanner({super.key, required this.help});
  final RetryHelp help;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final eliminates = help.attempt >= eliminateFromAttempt;
    final lines = [
      if (help.eased) 'Bu denemede geçme sınırı %${help.passPercent}.',
      eliminates
          ? 'Daha önce takıldığın sorularda doğru şık sana göz kırpacak, bazı yanlış şıklar elendi.'
          : 'Daha önce takıldığın sorularda doğru şık sana göz kırpacak, “İpucu” da var.',
    ];
    return Container(
      key: const Key('retry-banner'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: p.accentBg, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.support_rounded, size: 20, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${help.attempt}. deneme',
                  style: TextStyle(fontWeight: FontWeight.w800, color: p.ink),
                ),
                const SizedBox(height: 2),
                Text(lines.join(' '), style: TextStyle(color: p.ink, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "İpucu" on a question missed in an earlier attempt: folded until tapped,
/// then the short rule and the note about wrong options. With [eliminated]
/// options it also says how many were greyed out.
class TestHintButton extends StatefulWidget {
  const TestHintButton({super.key, required this.hint, this.eliminated = 0});
  final TestHint? hint;
  final int eliminated;

  @override
  State<TestHintButton> createState() => _TestHintButtonState();
}

class _TestHintButtonState extends State<TestHintButton> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hint = widget.hint;
    final eliminated = widget.eliminated > 0
        ? Text(
            '${widget.eliminated} şık elendi',
            key: const Key('hint-eliminated'),
            style: TextStyle(color: p.muted, fontWeight: FontWeight.w700),
          )
        : null;
    if (hint == null) {
      return eliminated == null
          ? const SizedBox.shrink()
          : Padding(padding: const EdgeInsets.only(bottom: 10), child: eliminated);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TextButton.icon(
                key: const Key('hint-button'),
                onPressed: () => setState(() => _open = !_open),
                icon: Icon(_open ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded),
                label: Text(_open ? 'İpucunu gizle' : 'İpucu'),
                style: TextButton.styleFrom(
                  foregroundColor: p.accent,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const Spacer(),
              ?eliminated,
            ],
          ),
          if (_open)
            Container(
              key: const Key('hint-card'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.accentBg, borderRadius: BorderRadius.circular(Radii.md)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hint.rule != null) Text(hint.rule!, style: TextStyle(color: p.ink, height: 1.4)),
                  if (hint.rule != null && hint.clue != null) const SizedBox(height: 8),
                  if (hint.clue != null)
                    Text(
                      hint.clue!,
                      style: TextStyle(color: p.ink, height: 1.4, fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Hatalarının özeti" on the failed-test screen: the topics missed most,
/// each with a short rule, and the unit's own rule when it has one.
class MissSummaryCard extends StatelessWidget {
  const MissSummaryCard({super.key, required this.topics, this.rule});
  final List<MissedTopic> topics;
  final String? rule;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const Key('miss-summary'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hatalarının özeti',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: p.ink),
          ),
          const SizedBox(height: 8),
          for (final t in topics) ...[
            Text(
              '${t.label}: ${t.count} yanlış',
              style: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
            ),
            if (t.tip != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: Text(t.tip!, style: TextStyle(color: p.muted, height: 1.35)),
              )
            else
              const SizedBox(height: 6),
          ],
          if (rule != null) ...[
            const SizedBox(height: 4),
            Text(
              'Konunun kısa kuralı',
              style: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
            ),
            const SizedBox(height: 2),
            Text(rule!, style: TextStyle(color: p.muted, height: 1.35)),
          ],
        ],
      ),
    );
  }
}

/// What the next attempt of a failed test brings, for the failed screen.
String nextAttemptLine(int nextAttempt) {
  final pass = passPercentFor(nextAttempt);
  if (nextAttempt >= eliminateFromAttempt) {
    return 'Sonraki denemede takıldığın sorularda ipucu olacak, bazı yanlış şıklar elenecek'
        '${pass < testPassPercent ? ' ve geçme sınırı %$pass' : ''}.';
  }
  if (nextAttempt >= hintFromAttempt) return 'Sonraki denemede takıldığın sorularda ipucu olacak.';
  return '';
}
