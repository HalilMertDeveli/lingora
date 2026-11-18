import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/speech_evidence.dart';
import '../data/scenarios.dart';
import '../services/conversation.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import 'pronunciation_screen.dart';

/// End-of-conversation karne of the voice coach: the learner's wrong
/// sentences with the right version and a Turkish note (from the AI), and the
/// words the phone's recognizer struggled with (on-device evidence only),
/// each one a tap away from the telaffuz koçu.
class ConversationReportScreen extends ConsumerStatefulWidget {
  const ConversationReportScreen({super.key, required this.scenario, required this.history});
  final Scenario scenario;
  final List<ChatMessage> history;

  @override
  ConsumerState<ConversationReportScreen> createState() => _ConversationReportScreenState();
}

class _ConversationReportScreenState extends ConsumerState<ConversationReportScreen> {
  late Future<ConversationReport> _report = _load();

  Future<ConversationReport> _load() =>
      ref.read(conversationReportServiceProvider).report(widget.scenario, widget.history);

  int get _turns => widget.history.where((m) => m.fromUser).length;
  int get _spoken => widget.history.where((m) => m.fromUser && m.spoken).length;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Konuşma karnesi')),
    body: SafeArea(
      child: FutureBuilder<ConversationReport>(
        future: _report,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Karnen hazırlanıyor…')],
              ),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${snap.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => setState(() => _report = _load()),
                      child: const Text('Tekrar dene'),
                    ),
                  ],
                ),
              ),
            );
          }
          return _body(context, snap.requireData);
        },
      ),
    ),
  );

  Widget _body(BuildContext context, ConversationReport r) {
    final words = [for (final w in r.weakWords) w.word];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Mascot(mood: r.mistakes.isEmpty ? Mood.cheer : Mood.happy, size: 72, decorative: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.scenario.title, style: Theme.of(context).textTheme.titleLarge),
                  Text(
                    '$_turns mesaj · $_spoken sesli · ${r.mistakes.length} düzeltme',
                    key: const Key('report-stats'),
                    style: TextStyle(color: Brand.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (r.summaryTr.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Brand.accentBg, borderRadius: BorderRadius.circular(14)),
            child: Text(r.summaryTr, style: const TextStyle(height: 1.4)),
          ),
        ],
        const SizedBox(height: 20),
        Text('Düzeltilecek cümleler', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (r.mistakes.isEmpty)
          Text('Harika: belirgin bir dil bilgisi hatası yok.', style: TextStyle(color: Brand.muted))
        else
          for (final (i, m) in r.mistakes.indexed) _MistakeCard(m, key: ValueKey('mistake-$i')),
        const SizedBox(height: 20),
        Text('Telaffuzu zayıf kelimeler', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Telefonun konuşma tanıması bu kelimelerde zorlandı (sen düzelttin ya da emin olamadı).',
          style: TextStyle(color: Brand.muted, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (r.weakWords.isEmpty)
          Text(
            _spoken == 0
                ? 'Bu sohbette sesli konuşmadın. Bir dahaki sefere mikrofonu dene.'
                : 'Telefon söylediğin her kelimeyi net anladı.',
            key: const Key('no-weak-words'),
            style: TextStyle(color: Brand.muted),
          )
        else ...[
          for (final (i, w) in r.weakWords.indexed) _WeakWordTile(w, onPractise: () => _practise(words, i)),
          const SizedBox(height: 12),
          PressableButton(
            key: const Key('practise-all'),
            label: 'TELAFFUZ KOÇUNDA ÇALIŞ',
            onPressed: () => _practise(words, 0),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tamam')),
      ],
    );
  }

  void _practise(List<String> words, int i) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PronunciationWordsScreen(words: words, initial: i),
    ),
  );
}

class _MistakeCard extends StatelessWidget {
  const _MistakeCard(this.m, {super.key});
  final ReportMistake m;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Brand.card,
      border: Border.all(color: Brand.line, width: 2),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.close_rounded, color: Brand.error, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                m.original,
                style: TextStyle(color: Brand.muted, decoration: TextDecoration.lineThrough),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_rounded, color: Brand.success, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(m.corrected, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        if (m.explanationTr.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(m.explanationTr, style: TextStyle(color: Brand.muted, fontSize: 13)),
        ],
      ],
    ),
  );
}

class _WeakWordTile extends StatelessWidget {
  const _WeakWordTile(this.w, {required this.onPractise});
  final WeakWordEvidence w;
  final VoidCallback onPractise;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (w.heard.isNotEmpty) '“${w.heard}” olarak anlaşıldı',
      if (w.heard.isEmpty) 'tanıyıcı emin olamadı',
      if (w.confidence != null) 'güven %${(w.confidence! * 100).round()}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TapCard(
        key: ValueKey('weak-${w.word}'),
        onTap: onPractise,
        child: Row(
          children: [
            Icon(Icons.record_voice_over_rounded, color: Brand.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w.word, style: Theme.of(context).textTheme.titleMedium),
                  Text(details, style: TextStyle(color: Brand.muted, fontSize: 13)),
                ],
              ),
            ),
            Text(
              'Çalış',
              style: TextStyle(color: Brand.primary, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
