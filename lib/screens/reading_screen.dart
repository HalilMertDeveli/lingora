import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notes_practice.dart';
import '../data/notes_repository.dart';
import '../data/progress.dart';
import '../data/reading_repository.dart';
import '../models/notes.dart';
import '../models/reading.dart';
import '../services/speech.dart';
import '../services/growth/analytics.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import 'lesson_result_screen.dart';

Color get _readColor => Brand.tone(const Color(0xFF0E9F8E));

Map<String, Color> get _levelColors => {'A1': Brand.success, 'A2': Color(0xFF2F80ED), 'B1': Brand.primary};

/// Number of stories the user has finished.
int readStoryCount(Progress p) => p.completed.keys.where((k) => k.startsWith('read_')).length;

/// Shortcut card to the reading library, used on the course path and in
/// "Notlarım".
class ReadingEntryCard extends ConsumerWidget {
  const ReadingEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = readStoryCount(ref.watch(progressProvider));
    return TapCard(
      color: _readColor,
      padding: const EdgeInsets.all(12),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReadingLibraryScreen())),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _readColor.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Glyph(emoji: '📚', icon: Icons.auto_stories_outlined, size: 22, color: _readColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Okuma hikâyeleri', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                Text(
                  done == 0 ? 'Türkçe açıklamalı kısa hikâyeler' : '$done hikâye okundu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Brand.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Brand.muted),
        ],
      ),
    );
  }
}

/// All stories grouped by level, with progress per level.
class ReadingLibraryScreen extends ConsumerWidget {
  const ReadingLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stories = ref.watch(storiesProvider);
    final p = ref.watch(progressProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Okuma')),
      body: stories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hikâyeler yüklenemedi: $e')),
        data: (all) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text(
              'Türkiye\'de geçen kısa hikâyeler. Her kelimeye dokunup Türkçesini görebilir, '
              'dinleyebilir ve sözlüğüne ekleyebilirsin.',
              style: TextStyle(color: Brand.muted),
            ),
            for (final level in readingLevels) ..._level(context, level, all, p),
          ],
        ),
      ),
    );
  }

  List<Widget> _level(BuildContext context, String level, List<ReadingStory> all, Progress p) {
    final list = all.where((s) => s.level == level).toList();
    if (list.isEmpty) return const [];
    final done = list.where((s) => p.isDone(readNodeId(s.id))).length;
    final color = _levelColors[level] ?? _readColor;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(
          children: [
            Text('$level · ${readingLevelNames[level]}', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            Text(
              '$done/${list.length}',
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlossyProgress(value: done / list.length, color: color, height: 10),
      ),
      for (final s in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TapCard(
            color: color,
            onTap: () {
              logEventFrom(context, AnalyticsEvent.featureUse(AppFeature.reading));
              Navigator.of(context).push(
                MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => StoryReaderScreen(story: s)),
              );
            },
            child: Row(
              children: [
                IconBadge(icon: Icons.menu_book_outlined, emoji: s.emoji, color: _readColor, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title, style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        '${s.titleTr} · ${s.wordCount} kelime',
                        style: TextStyle(color: Brand.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (p.isDone(readNodeId(s.id)))
                  Icon(Icons.check_circle_rounded, color: Brand.success)
                else
                  Icon(Icons.chevron_right_rounded, color: Brand.muted),
              ],
            ),
          ),
        ),
    ];
  }
}

/// Reads one story: every word is tappable, glossed words are underlined,
/// "dinle" reads sentence by sentence, questions come at the end.
class StoryReaderScreen extends ConsumerStatefulWidget {
  const StoryReaderScreen({super.key, required this.story});
  final ReadingStory story;

  @override
  ConsumerState<StoryReaderScreen> createState() => _StoryReaderScreenState();
}

class _StoryReaderScreenState extends ConsumerState<StoryReaderScreen> {
  late final _paragraphs = tokenizeStory(widget.story);
  late final _sentences = storySentences(_paragraphs);
  late final SpeechService _speech = ref.read(speechProvider);
  final _started = DateTime.now();

  bool _listening = false;
  bool _slow = false;
  int _sentence = 0;
  bool _quiz = false;

  void _say(int i) {
    setState(() => _sentence = i.clamp(0, _sentences.length - 1));
    _speech.say(_sentences[_sentence], slow: _slow);
  }

  void _openWord(ReadingToken t) {
    if (_listening) setState(() => _sentence = t.sentence);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _WordSheet(token: t, example: _sentences[t.sentence]),
    );
  }

  void _finish(int firstTry) {
    final n = widget.story.questions.length;
    final reward = ref
        .read(progressProvider.notifier)
        .completeNode(
          readNodeId(widget.story.id),
          xp: 10 + firstTry * 2,
          answered: n,
          correct: firstTry,
          perfect: firstTry == n,
        );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LessonResultScreen(
          reward: reward,
          accuracy: n == 0 ? 100 : (firstTry * 100 / n).round(),
          duration: DateTime.now().difference(_started),
          perfect: firstTry == n,
          headline: 'Hikâye bitti! $firstTry/$n ilk denemede doğru',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.story;
    final color = _levelColors[s.level] ?? _readColor;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.title),
        actions: [
          if (!_quiz)
            IconButton(
              tooltip: _listening ? 'Dinlemeyi kapat' : 'Dinle',
              isSelected: _listening,
              icon: const Icon(Icons.headphones_rounded),
              selectedIcon: Icon(Icons.headphones_rounded, color: color),
              onPressed: () => setState(() => _listening = !_listening),
            ),
        ],
      ),
      body: _quiz ? _Quiz(story: s, color: color, onDone: _finish) : _reader(color),
      bottomNavigationBar: !_quiz && _listening ? _listenBar(color) : null,
    );
  }

  Widget _reader(Color color) {
    final s = widget.story;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(
          children: [
            IconBadge(icon: Icons.menu_book_outlined, emoji: s.emoji, color: _readColor, size: 48),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.titleTr, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    '${s.level} · ${readingLevelNames[s.level]} · ${s.wordCount} kelime',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(14)),
          child: Text(
            '${kidEmoji('👆')}Her kelimeye dokunabilirsin. Altı noktalı olanların bu hikâyeye özel Türkçe notu var. '
            'Hoparlör düğmesiyle cümle cümle dinle.',
            style: TextStyle(color: Brand.muted, fontSize: 13),
          ),
        ),
        const SizedBox(height: 16),
        for (final p in _paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Wrap(spacing: 5, runSpacing: 4, children: [for (final t in p) _token(t, color)]),
          ),
        const SizedBox(height: 8),
        PressableButton(
          label: 'SORULARA GEÇ',
          color: color,
          onPressed: () => setState(() {
            _listening = false;
            _quiz = true;
          }),
        ),
      ],
    );
  }

  Widget _token(ReadingToken t, Color color) {
    final current = _listening && t.sentence == _sentence;
    return GestureDetector(
      onTap: () => _openWord(t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
        decoration: BoxDecoration(
          color: current ? color.withValues(alpha: 0.14) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          t.text,
          style: TextStyle(
            fontSize: 19,
            height: 1.4,
            color: Brand.ink,
            decoration: t.gloss != null ? TextDecoration.underline : null,
            decorationStyle: TextDecorationStyle.dotted,
            decorationColor: color,
            decorationThickness: 2,
          ),
        ),
      ),
    );
  }

  Widget _listenBar(Color color) => SafeArea(
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Brand.card,
        border: Border(top: BorderSide(color: Brand.line)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Önceki cümle',
            onPressed: _sentence > 0 ? () => _say(_sentence - 1) : null,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: () => _say(_sentence),
              icon: const Icon(Icons.volume_up_rounded),
              label: Text('Cümle ${_sentence + 1}/${_sentences.length}'),
            ),
          ),
          IconButton(
            tooltip: 'Sonraki cümle',
            onPressed: _sentence < _sentences.length - 1 ? () => _say(_sentence + 1) : null,
            icon: const Icon(Icons.skip_next_rounded),
          ),
          IconButton(
            tooltip: 'Yavaş oku',
            isSelected: _slow,
            onPressed: () => setState(() => _slow = !_slow),
            icon: Glyph(
              emoji: '🐢',
              icon: Icons.slow_motion_video_rounded,
              size: 22,
              color: _slow ? _readColor : Brand.muted,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Meaning, pronunciation and "Sözlüğüme ekle" for a tapped word.
class _WordSheet extends ConsumerStatefulWidget {
  const _WordSheet({required this.token, required this.example});
  final ReadingToken token;
  final String example;

  @override
  ConsumerState<_WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends ConsumerState<_WordSheet> {
  final _meaning = TextEditingController();
  bool _added = false;

  @override
  void dispose() {
    _meaning.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.token;
    final p = ref.watch(progressProvider);
    final notes = ref.watch(notesProvider).value;
    final dict = notes == null ? p.customWords : dictionaryWords(notes, p);
    final known = findWord(dict, t.word);
    final meaning = t.gloss ?? known?.tr;
    final display = stripPunctuation(t.text);

    void add() {
      final tr = meaning ?? _meaning.text.trim();
      if (tr.isEmpty) return;
      ref.read(progressProvider.notifier).addCustomWord(customWord(t.word, tr, example: widget.example));
      Haptics.success();
      setState(() => _added = true);
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(display, style: Theme.of(context).textTheme.headlineSmall)),
                IconButton.filledTonal(
                  tooltip: 'Telaffuz',
                  onPressed: () => ref.read(speechProvider).say(display),
                  icon: const Icon(Icons.volume_up_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (meaning != null)
              Text(
                meaning,
                key: const ValueKey('word-meaning'),
                style: TextStyle(fontSize: 20, color: _readColor, fontWeight: FontWeight.w800),
              )
            else ...[
              Text(
                'Bu kelimenin hikâyede notu yok. Anlamını kendin yazıp sözlüğüne ekleyebilirsin.',
                style: TextStyle(color: Brand.muted),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _meaning,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Türkçe anlamı'),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '“${widget.example}”',
              style: TextStyle(fontStyle: FontStyle.italic, color: Brand.muted),
            ),
            const SizedBox(height: 16),
            if (_added)
              Row(
                children: [
                  Mascot(mood: Mood.happy, size: 40),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sözlüğüne eklendi! Kelime tekrarında karşına çıkacak.',
                      style: TextStyle(color: Brand.success, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              )
            else if (known != null)
              Text(
                '✓ Bu kelime zaten sözlüğünde',
                style: TextStyle(color: Brand.success, fontWeight: FontWeight.w800),
              )
            else
              PressableButton(
                label: 'Sözlüğüme ekle',
                color: _readColor,
                onPressed: (meaning ?? _meaning.text.trim()).isEmpty ? null : add,
              ),
          ],
        ),
      ),
    );
  }
}

/// Comprehension questions; a wrong pick just asks to try again.
class _Quiz extends StatefulWidget {
  const _Quiz({required this.story, required this.color, required this.onDone});
  final ReadingStory story;
  final Color color;
  final void Function(int firstTry) onDone;

  @override
  State<_Quiz> createState() => _QuizState();
}

class _QuizState extends State<_Quiz> {
  int _i = 0;
  int _firstTry = 0;
  final Set<int> _wrong = {};
  bool _solved = false;
  int _shake = 0;

  ReadingQuestion get _q => widget.story.questions[_i];

  void _pick(int option) {
    if (_solved || _wrong.contains(option)) return;
    if (option == _q.answer) {
      Haptics.success();
      setState(() {
        _solved = true;
        if (_wrong.isEmpty) _firstTry++;
      });
    } else {
      Haptics.error();
      setState(() {
        _wrong.add(option);
        _shake++;
      });
    }
  }

  void _next() {
    if (_i + 1 >= widget.story.questions.length) {
      widget.onDone(_firstTry);
      return;
    }
    setState(() {
      _i++;
      _wrong.clear();
      _solved = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    final n = widget.story.questions.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        GlossyProgress(value: (_i + (_solved ? 1 : 0)) / n, color: widget.color),
        const SizedBox(height: 16),
        Text(
          'Soru ${_i + 1}/$n',
          style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(q.q, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Shake(
          trigger: _shake,
          child: Column(
            children: [
              for (var o = 0; o < q.options.length; o++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Opacity(
                    opacity: _wrong.contains(o) ? 0.5 : 1,
                    child: TapCard(
                      onTap: () => _pick(o),
                      selected: _solved && o == q.answer || _wrong.contains(o),
                      color: _wrong.contains(o) ? Brand.error : Brand.success,
                      child: Row(
                        children: [
                          Expanded(child: Text(q.options[o], style: const TextStyle(fontSize: 16))),
                          if (_solved && o == q.answer)
                            Icon(Icons.check_circle_rounded, color: Brand.success),
                          if (_wrong.contains(o)) Icon(Icons.close_rounded, color: Brand.error),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!_solved && _wrong.isNotEmpty)
          Text(
            'Olmadı, bir daha dene. Hikâyeye dönüp bakmak serbest.',
            style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w700),
          ),
        if (_solved) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Brand.successBg, borderRadius: BorderRadius.circular(14)),
            child: Text('${kidEmoji('💡')}${q.explain}', style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(height: 16),
          PressableButton(label: _i + 1 >= n ? 'BİTİR' : 'DEVAM', color: widget.color, onPressed: _next),
        ],
      ],
    );
  }
}

/// Lets the user add their own word to the personal dictionary.
Future<void> showAddWordDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _AddWordDialog());

class _AddWordDialog extends ConsumerStatefulWidget {
  const _AddWordDialog();

  @override
  ConsumerState<_AddWordDialog> createState() => _AddWordDialogState();
}

class _AddWordDialogState extends ConsumerState<_AddWordDialog> {
  final _en = TextEditingController();
  final _tr = TextEditingController();
  final _example = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _en.dispose();
    _tr.dispose();
    _example.dispose();
    super.dispose();
  }

  void _save() {
    final en = _en.text.trim();
    final tr = _tr.text.trim();
    if (en.isEmpty || tr.isEmpty) {
      setState(() => _error = 'İngilizce kelimeyi ve Türkçe anlamını yaz.');
      return;
    }
    final notes = ref.read(notesProvider).value;
    final p = ref.read(progressProvider);
    final List<NoteWord> dict = notes == null ? p.customWords : dictionaryWords(notes, p);
    if (findWord(dict, en) != null) {
      setState(() => _error = '“$en” zaten sözlüğünde.');
      return;
    }
    ref.read(progressProvider.notifier).addCustomWord(customWord(en, tr, example: _example.text));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Kelime ekle'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('add-en'),
            controller: _en,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'İngilizce'),
          ),
          TextField(
            key: const ValueKey('add-tr'),
            controller: _tr,
            decoration: const InputDecoration(labelText: 'Türkçe anlamı'),
          ),
          TextField(
            controller: _example,
            decoration: const InputDecoration(labelText: 'Örnek cümle (isteğe bağlı)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Brand.error)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: _save,
        child: const Text('Ekle'),
      ),
    ],
  );
}
