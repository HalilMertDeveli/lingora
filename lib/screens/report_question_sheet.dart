import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_version.dart';
import '../data/catalog.dart';
import '../data/course_repository.dart';
import '../models/course.dart';
import '../services/question_reports.dart';
import '../theme.dart';

/// What the app attaches to a report by itself.
class ReportTarget {
  const ReportTarget({
    required this.questionId,
    required this.lessonId,
    this.question,
    this.answer,
    this.correct,
  });

  final String questionId;
  final String lessonId;
  final String? question;
  final String? answer;
  final bool? correct;
}

/// The question's text for the panel: the prompt, sentence or exam stem.
String? questionTextOf(Exercise ex) {
  final parts = [
    ?ex.question,
    ?ex.prompt,
    ?ex.text,
    if (ex.options.isNotEmpty) ex.options.join(' / '),
    if (ex.pairs.isNotEmpty) ex.pairs.map((p) => '${p.$1}=${p.$2}').join(', '),
  ].where((s) => s.trim().isNotEmpty);
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Small "Bildir" link under a question and its explanation.
class ReportQuestionButton extends StatelessWidget {
  const ReportQuestionButton({super.key, required this.target});

  /// Read at tap time, so the answer given so far is included.
  final ReportTarget Function() target;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: TextButton.icon(
      key: const Key('report-question'),
      style: TextButton.styleFrom(
        foregroundColor: Brand.muted,
        minimumSize: const Size(48, 40),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: () => showReportSheet(context, target()),
      icon: const Icon(Icons.flag_outlined, size: 18),
      label: const Text('Bildir'),
    ),
  );
}

Future<void> showReportSheet(BuildContext context, ReportTarget target) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => ReportSheet(target: target),
);

class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({super.key, required this.target});
  final ReportTarget target;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  final _note = TextEditingController();
  ReportReason? _reason;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    final reporter = ref.read(questionReporterProvider);
    final t = widget.target;
    final track = ref.read(trackProvider);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (reporter == null) throw const ReportException(ReportError.unavailable);
      await reporter.send(
        QuestionReport(
          reason: reason,
          questionId: t.questionId,
          lessonId: t.lessonId,
          appVersion: appVersion,
          note: _note.text,
          answer: t.answer,
          correct: t.correct,
          question: t.question,
          track: track.id == defaultTrackId ? null : track.id,
        ),
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        const SnackBar(content: Text('Teşekkürler! Bildirimin ekibimize ulaştı, soruya bakacağız.')),
      );
    } on ReportException catch (e) {
      if (mounted) setState(() => _error = e.error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          key: const Key('report-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Bu soruda ne sorun var?', style: t.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Soru, dersin adı, cevabın ve uygulama sürümü bildirime kendiliğinden eklenir.',
                style: TextStyle(color: Brand.muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              for (final r in ReportReason.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TapCard(
                    key: Key('report-reason-${r.code}'),
                    selected: _reason == r,
                    onTap: () => setState(() => _reason = r),
                    child: Row(
                      children: [
                        Icon(
                          _reason == r ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: _reason == r ? Brand.primary : Brand.muted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(r.label, style: t.titleSmall)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              TextField(
                key: const Key('report-note'),
                controller: _note,
                maxLength: maxReportNote,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Not (isteğe bağlı)',
                  hintText: 'Ör. "I agree too" da doğru olmalı',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error case final e?) ...[
                Text(
                  e,
                  key: const Key('report-error'),
                  style: TextStyle(color: Brand.error),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                key: const Key('report-send'),
                onPressed: _reason == null || _sending ? null : _send,
                child: Text(_sending ? 'Gönderiliyor…' : 'Gönder'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
