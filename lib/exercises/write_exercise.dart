import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../models/course.dart';
import '../screens/paywall_screen.dart';
import '../services/billing/premium.dart';
import '../services/growth/analytics_events.dart';
import '../services/writing.dart';
import '../theme.dart';
import 'common.dart';

/// A short free text (curriculum §3, `write`). Free for everyone: the task is
/// done when the text is long enough and the learner ticked the checklist,
/// then the model text is shown. Premium learners can also ask for AI
/// feedback (scores, a few focused corrections) and rewrite before checking.
class WriteExercise extends ConsumerStatefulWidget {
  const WriteExercise({super.key, required this.ex, required this.locked, required this.onReady});
  final Exercise ex;
  final bool locked;
  final ReadyCallback onReady;

  @override
  ConsumerState<WriteExercise> createState() => _WriteExerciseState();
}

class _WriteExerciseState extends ConsumerState<WriteExercise> {
  final _text = TextEditingController();
  final Set<int> _ticked = {};
  WritingFeedback? _feedback;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _changed() {
    final check = localWritingCheck(widget.ex, _text.text, _ticked);
    setState(() {});
    widget.onReady(check.done ? () => true : null);
  }

  Future<void> _askFeedback(WritingService service) async {
    final taskId = widget.ex.taskId;
    if (taskId == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final feedback = await service.assess(taskId, _text.text.trim());
      // The error analysis screen counts these types like the hata dedektörü's.
      ref
          .read(progressProvider.notifier)
          .recordErrorCategories(feedback.corrections.map((c) => errorCategoryOf(c.type)).nonNulls);
      if (mounted) setState(() => _feedback = feedback);
    } on WritingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.ex;
    final t = Theme.of(context).textTheme;
    final words = wordCount(_text.text);
    final check = localWritingCheck(ex, _text.text, _ticked);
    final enough = words >= ex.minWords;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExerciseTitle('Yaz'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(Radii.md)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ex.prompt ?? '', style: t.titleMedium),
              const SizedBox(height: 4),
              Text(
                ex.maxWords > 0
                    ? 'Hedef: ${ex.minWords}–${ex.maxWords} kelime'
                    : 'En az ${ex.minWords} kelime',
                style: TextStyle(color: Brand.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('write-text'),
          controller: _text,
          enabled: !widget.locked,
          minLines: 6,
          maxLines: 12,
          maxLength: 2000,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Metnini İngilizce yaz…', border: OutlineInputBorder()),
          onChanged: (_) => _changed(),
        ),
        Text(
          '$words kelime',
          key: const Key('write-count'),
          style: TextStyle(fontWeight: FontWeight.w800, color: enough ? Brand.success : Brand.muted),
        ),
        const SizedBox(height: 12),
        if (ex.checklist.isNotEmpty) ...[
          Text('Kontrol listesi', style: t.titleSmall),
          for (final (i, item) in ex.checklist.indexed)
            CheckboxListTile(
              key: Key('write-check-$i'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _ticked.contains(i),
              title: Text(item),
              onChanged: widget.locked
                  ? null
                  : (on) {
                      on == true ? _ticked.add(i) : _ticked.remove(i);
                      _changed();
                    },
            ),
        ],
        if (!widget.locked && check.notes.isNotEmpty && _text.text.trim().isNotEmpty)
          for (final n in check.notes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $n', style: TextStyle(color: Brand.muted)),
            ),
        if (!widget.locked) ...[const SizedBox(height: 12), _feedbackButton()],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: Brand.error)),
          ),
        if (_feedback != null) ...[const SizedBox(height: 12), WritingFeedbackCard(feedback: _feedback!)],
      ],
    );
  }

  /// AI feedback for Premium, a way to it for others; nothing offline.
  Widget _feedbackButton() {
    final service = ref.watch(writingServiceProvider);
    if (service == null || widget.ex.taskId == null) {
      return Text(
        'Yapay zekâ geri bildirimi için internet ve hesap gerekir; yerel kontrol yine de çalışıyor.',
        style: TextStyle(color: Brand.muted),
      );
    }
    if (!ref.watch(premiumProvider)) {
      return OutlinedButton.icon(
        key: const Key('write-feedback-premium'),
        icon: const Icon(Icons.lock_rounded),
        label: const Text('Yapay zekâ geri bildirimi (Premium)'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const PaywallScreen(placement: PaywallPlacement.writingFeedback),
          ),
        ),
      );
    }
    final ready = wordCount(_text.text) >= widget.ex.minWords;
    return FilledButton.tonalIcon(
      key: const Key('write-feedback'),
      icon: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.auto_awesome_rounded),
      label: Text(_feedback == null ? 'Yapay zekâ geri bildirimi al' : 'Düzelttim, tekrar bak'),
      onPressed: ready && !_busy ? () => _askFeedback(service) : null,
    );
  }
}

/// Rubric scores, corrections and the next step of AI writing feedback.
class WritingFeedbackCard extends StatelessWidget {
  const WritingFeedbackCard({super.key, required this.feedback});
  final WritingFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      key: const Key('write-feedback-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.card,
        border: Border.all(color: Brand.line, width: 2),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Geri bildirim', style: t.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final MapEntry(:key, :value) in WritingFeedback.criteria.entries)
                if (feedback.scores[key] case final s?) Chip(label: Text('$value: $s/3')),
            ],
          ),
          for (final c in feedback.corrections)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: c.from,
                          style: TextStyle(color: Brand.error, decoration: TextDecoration.lineThrough),
                        ),
                        const TextSpan(text: '  →  '),
                        TextSpan(
                          text: c.to,
                          style: TextStyle(color: Brand.success, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  if (c.whyTr.isNotEmpty) Text(c.whyTr, style: TextStyle(color: Brand.muted)),
                ],
              ),
            ),
          if (feedback.nextTr.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Sıradaki adım: ${feedback.nextTr}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 6),
          Text(
            'Düzeltmeleri uygula ve metnini yeniden yaz. Bitince "Düzelttim, tekrar bak" ya da "Kontrol et".',
            key: const Key('write-rewrite-hint'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// The model text, shown after a writing task is submitted.
class WritingModelText extends StatelessWidget {
  const WritingModelText({super.key, required this.model});
  final String model;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('write-model'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Model metin', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(model),
    ],
  );
}
