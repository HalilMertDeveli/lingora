import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress.dart';
import '../../data/vocab_practice.dart';
import '../../exercises/common.dart';
import '../../models/vocab.dart';
import '../../theme.dart';
import 'vocab_home_screen.dart';

/// Searchable list of track words; tapping one opens its card.
class VocabWordListScreen extends ConsumerStatefulWidget {
  const VocabWordListScreen({super.key, required this.title, required this.entries, this.header});
  final String title;
  final List<VocabEntry> entries;
  final Widget? header;

  @override
  ConsumerState<VocabWordListScreen> createState() => _VocabWordListScreenState();
}

class _VocabWordListScreenState extends ConsumerState<VocabWordListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(progressProvider);
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.entries
        : widget.entries
              .where((e) => e.word.toLowerCase().contains(q) || e.tr.toLowerCase().contains(q))
              .toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (widget.header != null) ...[widget.header!, const SizedBox(height: 12)],
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Kelime veya anlam ara',
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 10),
          for (final e in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 6, backgroundColor: statusColors[vocabStatus(e, p)]),
              title: Text(e.word, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(e.tr),
              trailing: Text('#${e.rank}', style: TextStyle(color: Brand.muted)),
              onTap: () => showVocabEntry(context, e),
            ),
          if (list.isEmpty)
            Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('Sonuç yok', style: TextStyle(color: Brand.muted)),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showVocabEntry(BuildContext context, VocabEntry e) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    maxChildSize: 0.95,
    builder: (_, controller) => SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: VocabEntryDetails(entry: e),
    ),
  ),
);

/// Everything about one word: meanings, examples by context, collocations,
/// synonym and the Turkish tip.
class VocabEntryDetails extends StatelessWidget {
  const VocabEntryDetails({super.key, required this.entry});
  final VocabEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        title,
        style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(e.word, style: Theme.of(context).textTheme.headlineSmall)),
            SpeakerButton(text: e.word, size: 40),
          ],
        ),
        Text(
          '${e.posTr} · ${e.topic} · #${e.rank}${e.fromNotes ? ' · 📒 notlarında' : ''}',
          style: TextStyle(color: Brand.muted),
        ),
        section('ANLAMLAR'),
        for (final s in e.senses)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.tr, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(
                  s.def,
                  style: TextStyle(color: Brand.muted, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        section('ÖRNEKLER'),
        for (final x in e.examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${x.context.emoji} ${x.context.label}',
                  style: const TextStyle(fontSize: 12, color: vocabColor, fontWeight: FontWeight.w800),
                ),
                Text(x.en, style: const TextStyle(fontSize: 15)),
                Text(x.tr, style: TextStyle(color: Brand.muted)),
              ],
            ),
          ),
        section('EŞDİZİMLER'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in e.collocations)
              Tooltip(
                message: c.tr,
                child: Chip(label: Text('${c.phrase} · ${c.tr}')),
              ),
          ],
        ),
        if (e.synonym != null) ...[section('EŞ ANLAMLI'), Text(e.synonym!)],
        if (e.tip != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Brand.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text('💡 ${e.tip}', style: const TextStyle(height: 1.35)),
          ),
        ],
      ],
    );
  }
}

/// Notlarım shortcut: the track words that also appear in the user's own
/// Notion dictionary.
class NotesSoftwareWordsScreen extends ConsumerWidget {
  const NotesSoftwareWordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(vocabProvider)
      .when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('Kelimeler yüklenemedi: $e'))),
        data: (v) => VocabWordListScreen(
          title: 'Notlarındaki yazılım kelimeleri',
          entries: v.entries.where((e) => e.fromNotes).toList(),
          header: Text(
            'Notion sözlüğündeki yazılım kelimelerin, Yazılımcı İngilizcesi kartlarıyla: anlamlar, '
            'commit/PR örnekleri, eşdizimler ve ipuçları.',
            style: TextStyle(color: Brand.muted),
          ),
        ),
      );
}
