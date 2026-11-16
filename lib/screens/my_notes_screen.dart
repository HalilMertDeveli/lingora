import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notes_index.dart';
import '../data/progress.dart';
import '../models/notes.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';

/// "Notlarım": the notes each learner writes for themselves (a rule in their
/// own words, a phrase to remember…). Saved with the progress, so they follow
/// a signed-in account to other phones.
class MyNotesScreen extends ConsumerStatefulWidget {
  const MyNotesScreen({super.key});

  @override
  ConsumerState<MyNotesScreen> createState() => _MyNotesScreenState();
}

class _MyNotesScreenState extends ConsumerState<MyNotesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(progressProvider).visibleNotes;
    final shown = all.where((n) => userNoteMatches(n, _query)).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Notlarım (${all.length})')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-note'),
        onPressed: () => openNoteEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Not ekle'),
      ),
      body: all.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: EmptyState(
                  message:
                      'Henüz notun yok. Bir kuralı kendi cümlelerinle, aklında kalsın '
                      'istediğin bir kalıbı ya da örneği buraya yaz.',
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
              children: [
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Notlarında ara',
                  ),
                ),
                const SizedBox(height: 8),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 32),
                    child: EmptyState(message: 'Bu aramayla eşleşen not yok.'),
                  ),
                for (final n in shown) UserNoteCard(note: n),
              ],
            ),
    );
  }
}

/// One own note in a list: title, the start of the text and the date.
class UserNoteCard extends StatelessWidget {
  const UserNoteCard({super.key, required this.note});
  final UserNote note;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TapCard(
      onTap: () => openNoteEditor(context, note: note),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(noteTitle(note), style: Theme.of(context).textTheme.titleMedium),
                if (note.body.isNotEmpty && note.title.isNotEmpty)
                  Text(
                    note.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Brand.muted),
                  ),
                const SizedBox(height: 2),
                Text(
                  noteDate(note.updatedAt),
                  style: TextStyle(color: Brand.muted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Brand.muted),
        ],
      ),
    ),
  );
}

/// The note's title, or its first line when it has none.
String noteTitle(UserNote n) {
  if (n.title.trim().isNotEmpty) return n.title.trim();
  final first = n.body.trim().split('\n').first;
  return first.length > 60 ? '${first.substring(0, 60)}…' : first;
}

/// "16.11.2026".
String noteDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

bool userNoteMatches(UserNote n, String query) {
  final q = foldForSearch(query.trim());
  return q.isEmpty || foldForSearch(n.title).contains(q) || foldForSearch(n.body).contains(q);
}

void openNoteEditor(BuildContext context, {UserNote? note}) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => NoteEditorScreen(note: note)));

/// Writes a new note or edits / deletes [note].
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, this.note});
  final UserNote? note;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final _body = TextEditingController(text: widget.note?.body ?? '');

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isNotEmpty || body.isNotEmpty) {
      ref.read(progressProvider.notifier).saveUserNote(id: widget.note?.id, title: title, body: body);
    }
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Not silinsin mi?'),
        content: const Text('Bu not bu cihazdan ve hesabına bağlı diğer cihazlardan silinir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    ref.read(progressProvider.notifier).deleteUserNote(widget.note!.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.note == null ? 'Yeni not' : 'Notu düzenle'),
      actions: [
        if (widget.note != null)
          IconButton(
            tooltip: 'Notu sil',
            onPressed: _delete,
            icon: Icon(Icons.delete_outline_rounded, color: Brand.error),
          ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                TextField(
                  key: const ValueKey('note-title'),
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Başlık',
                    hintText: 'ör. Present Perfect ipucu',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('note-body'),
                  controller: _body,
                  autofocus: widget.note == null,
                  minLines: 8,
                  maxLines: null,
                  maxLength: 4000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Not',
                    alignLabelWithHint: true,
                    hintText: 'Kural, kalıp, örnek cümle… Kendi cümlelerinle yaz.',
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: PressableButton(key: const ValueKey('note-save'), label: 'KAYDET', onPressed: _save),
          ),
        ],
      ),
    ),
  );
}
