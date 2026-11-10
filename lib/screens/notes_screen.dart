import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/text.dart';
import '../core/tr_errors.dart';
import '../data/notes_practice.dart';
import '../data/notes_repository.dart';
import '../data/practice.dart';
import '../data/progress.dart';
import '../models/grammar_lesson.dart';
import '../models/notes.dart';
import '../services/speech.dart';
import '../theme.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import '../ui/why_wrong.dart';
import 'lesson_result_screen.dart';
import 'grammar_path_screen.dart';
import 'lesson_screen.dart';
import 'reading_screen.dart';

Color get _notesColor => Brand.tone(const Color(0xFF2F80ED));

/// Home of the "Notlarım" track: the user's own Notion notes as study tools.
class NotesHomeScreen extends ConsumerWidget {
  const NotesHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesProvider);
    return notes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Notlar yüklenemedi: $e')),
      data: (n) => _NotesHome(notes: n),
    );
  }
}

void _push(BuildContext context, Widget screen, {bool dialog = false}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: dialog, builder: (_) => screen));

class _NotesHome extends ConsumerWidget {
  const _NotesHome({required this.notes});
  final NotesBundle notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final now = ref.watch(clockProvider)();
    final words = dictionaryWords(notes, p);
    final due = dueWordCount(words, p, now);
    final learned = learnedWordCount(p);
    final wroteToday = p.diary.containsKey(dayKey(now));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: context.lingora.hero(_notesColor, from: const Color(0xFF1C5DB8)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Notlarım',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Notion\'da yazdığın ${notes.words.length} kelime ve ${notes.topics.where((t) => !t.addedByApp).length} gramer konusu, '
                      'artık çalışılabilir hâlde.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$learned kelime öğrenildi',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const Mascot(mood: Mood.happy, size: 80, decorative: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _GrammarPathCard(notes: notes),
        const SizedBox(height: 10),
        const ReadingEntryCard(),
        const SizedBox(height: 10),
        _BigAction(
          icon: Icons.style_rounded,
          color: _notesColor,
          title: 'Kelime tekrarı',
          subtitle: due > 0 ? '$due kelimenin tekrar zamanı geldi' : 'Yeni kelimelerle başla',
          badge: due > 0 ? '$due' : null,
          onTap: () {
            final list = wordsToReview(words, ref.read(progressProvider), now);
            _push(context, FlashcardScreen(words: list), dialog: true);
          },
        ),
        _BigAction(
          icon: Icons.quiz_rounded,
          color: Brand.accent,
          title: 'Kelime testi',
          subtitle: 'Kendi sözlüğünden eşleştirme ve seçmeli sorular',
          onTap: () => _push(
            context,
            LessonScreen(
              nodeId: 'notes_quiz',
              title: 'Kelime testi',
              items: wordQuizItems(words),
              color: Brand.accent,
              mode: LessonMode.practice,
            ),
            dialog: true,
          ),
        ),
        _BigAction(
          icon: Icons.menu_book_rounded,
          color: Brand.primary,
          title: 'Tüm gramer notlarım',
          subtitle: '${notes.topics.length} konu, Notion\'daki hâliyle, aranabilir',
          onTap: () => _push(context, GrammarListScreen(notes: notes)),
        ),
        _BigAction(
          icon: Icons.translate_rounded,
          color: Brand.success,
          title: 'Sözlüğüm',
          subtitle: '${words.length} kelime, konulara göre, hafıza hikâyelerinle',
          onTap: () => _push(context, WordListScreen(notes: notes)),
        ),
        _BigAction(
          icon: Icons.edit_note_rounded,
          color: Brand.streak,
          title: 'Günlüğüm',
          subtitle: wroteToday ? 'Bugünkü günlüğünü yazdın' : 'Bugün İngilizce birkaç cümle yaz',
          onTap: () => _push(context, DiaryScreen(prompts: notes.diaryPrompts)),
        ),
      ],
    );
  }
}

class _BigAction extends StatelessWidget {
  const _BigAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TapCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(subtitle, style: TextStyle(color: Brand.muted, fontSize: 13)),
              ],
            ),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
              child: Text(
                badge!,
                style: TextStyle(color: onColor(color), fontWeight: FontWeight.w900),
              ),
            ),
          Icon(Icons.chevron_right_rounded, color: Brand.muted),
        ],
      ),
    ),
  );
}

/// Flip cards with spaced repetition: "Biliyorum" moves a word up a box.
class FlashcardScreen extends ConsumerStatefulWidget {
  const FlashcardScreen({super.key, required this.words});
  final List<NoteWord> words;

  @override
  ConsumerState<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends ConsumerState<FlashcardScreen> with SingleTickerProviderStateMixin {
  late final _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
  late final SpeechService _speech = ref.read(speechProvider);
  final _started = DateTime.now();
  int _pos = 0;
  int _known = 0;

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  NoteWord get _w => widget.words[_pos];

  void _answer(bool known) {
    ref.read(progressProvider.notifier).reviewWord(_w.id, known: known);
    known ? Haptics.success() : Haptics.tap();
    if (known) _known++;
    if (_pos + 1 >= widget.words.length) {
      _finish();
      return;
    }
    _flip.value = 0;
    setState(() => _pos++);
  }

  void _finish() {
    final total = widget.words.length;
    final reward = ref
        .read(progressProvider.notifier)
        .completeNode(
          'notes_words',
          xp: max(5, _known),
          answered: total,
          correct: _known,
          perfect: _known == total,
        );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LessonResultScreen(
          reward: reward,
          accuracy: total == 0 ? 100 : (_known * 100 / total).round(),
          duration: DateTime.now().difference(_started),
          perfect: _known == total,
          headline: '$_known / $total kelimeyi biliyordun',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.words.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Şu an tekrar edilecek kelime yok. Yarın tekrar bak!')),
      );
    }
    final w = _w;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: Brand.muted),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: GlossyProgress(value: _pos / widget.words.length, color: _notesColor),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_pos + 1}/${widget.words.length}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: Brand.muted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => _flip.value < 0.5 ? _flip.forward() : _flip.reverse(),
                child: AnimatedBuilder(
                  animation: _flip,
                  builder: (_, _) {
                    final angle = _flip.value * pi;
                    final back = angle > pi / 2;
                    return Center(
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(angle),
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(back ? pi : 0),
                          child: _card(w, back),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: PressableButton(
                      label: 'BİLMİYORUM',
                      color: Brand.error,
                      onPressed: () => _answer(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PressableButton(
                      label: 'BİLİYORUM',
                      color: Brand.success,
                      onPressed: () => _answer(true),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(NoteWord w, bool back) => Container(
    key: ValueKey('${w.id}-$back'),
    width: MediaQuery.sizeOf(context).width - 48,
    constraints: const BoxConstraints(minHeight: 320),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: back ? Color.alphaBlend(_notesColor.withValues(alpha: 0.1), Brand.card) : Brand.card,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: back ? _notesColor : Brand.line, width: 2),
      boxShadow: [
        if (Brand.isKid)
          BoxShadow(color: edgeOf(back ? _notesColor : Brand.line), offset: const Offset(0, 6)),
      ],
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          trUpper(w.topic),
          style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1),
        ),
        const SizedBox(height: 14),
        if (!back) ...[
          Text(
            w.en,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          IconButton.filledTonal(
            onPressed: () => _speech.say(w.en),
            icon: const Icon(Icons.volume_up_rounded),
          ),
          const SizedBox(height: 16),
          Text('Anlamını düşün, sonra karta dokun', style: TextStyle(color: Brand.muted)),
        ] else ...[
          Text(
            w.tr,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _notesColor),
          ),
          if (w.example != null) ...[
            const SizedBox(height: 14),
            Text(
              '“${w.example}”',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic),
            ),
          ],
          if (w.story != null) ...[
            const SizedBox(height: 14),
            Text(
              '${kidEmoji('🧠')}${w.story}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.muted),
            ),
          ],
        ],
      ],
    ),
  );
}

/// The personal dictionary, searchable and filterable by topic.
class WordListScreen extends ConsumerStatefulWidget {
  const WordListScreen({super.key, required this.notes});
  final NotesBundle notes;

  @override
  ConsumerState<WordListScreen> createState() => _WordListScreenState();
}

class _WordListScreenState extends ConsumerState<WordListScreen> {
  String _query = '';
  String? _topic;

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(progressProvider);
    final words = dictionaryWords(widget.notes, p);
    final topics = {for (final w in words) w.topic}.toList()..sort();
    final q = _query.toLowerCase();
    final shown = words
        .where((w) => _topic == null || w.topic == _topic)
        .where((w) => q.isEmpty || w.en.toLowerCase().contains(q) || w.tr.toLowerCase().contains(q))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text('Sözlüğüm (${words.length})')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddWordDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Kelime ekle'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Kelime ara (EN veya TR)',
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: const Text('Tümü'),
                    selected: _topic == null,
                    onSelected: (_) => setState(() => _topic = null),
                  ),
                ),
                for (final t in topics)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(t),
                      selected: _topic == t,
                      onSelected: (_) => setState(() => _topic = t),
                    ),
                  ),
              ],
            ),
          ),
          if (_topic != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: PressableButton(
                label: 'BU KONUYU ÇALIŞ',
                color: _notesColor,
                onPressed: () => _push(
                  context,
                  FlashcardScreen(words: wordsToReview(words, p, ref.read(clockProvider)(), topic: _topic)),
                  dialog: true,
                ),
              ),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: shown.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: Brand.line),
              itemBuilder: (_, i) {
                final w = shown[i];
                final box = p.wordBox[w.id];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(w.en, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(w.tr),
                  trailing: box == null
                      ? null
                      : Icon(
                          box >= 3 ? Icons.verified_rounded : Icons.timelapse_rounded,
                          color: box >= 3 ? Brand.success : Brand.accent,
                        ),
                  onTap: () => _showWord(context, w),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showWord(BuildContext context, NoteWord w) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(w.en, style: Theme.of(context).textTheme.headlineSmall)),
                IconButton.filledTonal(
                  onPressed: () => ref.read(speechProvider).say(w.en),
                  icon: const Icon(Icons.volume_up_rounded),
                ),
              ],
            ),
            Text(
              w.tr,
              style: TextStyle(fontSize: 18, color: _notesColor, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(w.topic, style: TextStyle(color: Brand.muted)),
            if (w.example != null) ...[
              const SizedBox(height: 12),
              Text('“${w.example}”', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 16)),
            ],
            if (w.story != null) ...[
              const SizedBox(height: 12),
              Text('${kidEmoji('🧠')}Hafıza hikâyen: ${w.story}'),
            ],
            if (w.topic == customTopic) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  ref.read(progressProvider.notifier).removeCustomWord(w.id);
                  Navigator.pop(context);
                },
                icon: Icon(Icons.delete_outline_rounded, color: Brand.error),
                label: Text('Sözlüğümden çıkar', style: TextStyle(color: Brand.error)),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Grammar topics grouped by category.
class GrammarListScreen extends StatefulWidget {
  const GrammarListScreen({super.key, required this.notes});
  final NotesBundle notes;

  @override
  State<GrammarListScreen> createState() => _GrammarListScreenState();
}

class _GrammarListScreenState extends State<GrammarListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final topics = widget.notes.topics
        .where((t) => q.isEmpty || t.title.toLowerCase().contains(q) || t.body.toLowerCase().contains(q))
        .toList();
    final categories = {for (final t in topics) t.category}.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Gramer notlarım')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Konu ara (ör. unless, wish)',
            ),
          ),
          const SizedBox(height: 8),
          for (final c in categories) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
              child: Text(c, style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final t in topics.where((t) => t.category == c))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TapCard(
                  onTap: () => _push(context, TopicScreen(topic: t, all: widget.notes.topics)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title, style: Theme.of(context).textTheme.titleMedium),
                            Text(
                              '${t.addedByApp ? kidEmoji('✨') : ''}${t.source} · ${t.examples.length} örnek',
                              style: TextStyle(color: Brand.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: Brand.muted),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One grammar topic: the user's explanation, rules and examples, plus
/// practice generated from those examples.
class TopicScreen extends ConsumerWidget {
  const TopicScreen({super.key, required this.topic, required this.all});
  final GrammarTopic topic;
  final List<GrammarTopic> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = topicItems(topic, all);
    return Scaffold(
      appBar: AppBar(title: Text(topic.title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(label: Text(topic.category)),
                      Chip(
                        avatar: Icon(
                          topic.addedByApp ? Icons.auto_awesome_rounded : Icons.description_outlined,
                          size: 16,
                        ),
                        label: Text(topic.source),
                      ),
                    ],
                  ),
                  if (topic.addedByApp)
                    Container(
                      margin: const EdgeInsets.only(top: 6, bottom: 4),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Brand.accentBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('Bu konu notlarında yoktu; eksik kalmasın diye Lingora ekledi.'),
                    ),
                  const SizedBox(height: 8),
                  for (final para in topic.body.split('\n\n').where((s) => s.trim().isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(para.trim(), style: const TextStyle(fontSize: 16, height: 1.45)),
                    ),
                  if (topic.rules.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Brand.primary.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'KURALLAR',
                            style: TextStyle(
                              color: Brand.primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (final r in topic.rules)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• $r',
                                style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (topic.examples.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text('Örneklerin', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    for (final e in topic.examples)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: IconButton(
                          icon: Icon(Icons.volume_up_rounded, color: Brand.primary),
                          onPressed: () => ref.read(speechProvider).say(e.en),
                        ),
                        title: Text(e.en, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(e.tr),
                      ),
                  ],
                ],
              ),
            ),
            if (items.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Brand.line, width: 2)),
                ),
                child: PressableButton(
                  label: 'BU KONUDAN ALIŞTIRMA (${items.length})',
                  onPressed: () => _push(
                    context,
                    LessonScreen(
                      nodeId: 'note_${topic.id}',
                      title: topic.title,
                      items: topicItems(topic, all),
                      color: Brand.primary,
                    ),
                    dialog: true,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// English diary: one entry per day, with a daily prompt and offline checks
/// for typical Turkish-speaker mistakes.
class DiaryScreen extends ConsumerStatefulWidget {
  const DiaryScreen({super.key, required this.prompts});
  final List<String> prompts;

  @override
  ConsumerState<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends ConsumerState<DiaryScreen> {
  late final String _today = dayKey(ref.read(clockProvider)());
  late final _text = TextEditingController(text: ref.read(progressProvider).diary[_today] ?? '');
  List<TrError> _errors = const [];
  bool _checked = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _prompt {
    final d = DateTime.parse(_today);
    return widget.prompts[d.difference(DateTime(d.year)).inDays % widget.prompts.length];
  }

  void _save() {
    final text = _text.text.trim();
    final notifier = ref.read(progressProvider.notifier);
    final first = !ref.read(progressProvider).diary.containsKey(_today);
    notifier.saveDiary(_today, text);
    if (first && text.split(RegExp(r'\s+')).length >= 10) {
      notifier.completeNode('diary', xp: 10, answered: 1, correct: 1);
    }
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(first && text.isNotEmpty ? 'Günlüğün kaydedildi! +10 XP' : 'Kaydedildi.')),
    );
  }

  void _runCheck() {
    final errors = detectTrErrors(_text.text);
    ref.read(progressProvider.notifier).recordTrErrors(errors);
    setState(() {
      _errors = errors;
      _checked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final diary = ref.watch(progressProvider).diary;
    final past = diary.keys.where((k) => k != _today).toList()..sort((a, b) => b.compareTo(a));
    final words = _text.text.trim().isEmpty ? 0 : _text.text.trim().split(RegExp(r'\s+')).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Günlüğüm')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Brand.accentBg, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const Glyph(emoji: '✍️', icon: Icons.edit_note_rounded, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_prompt, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 8,
            maxLines: 16,
            onChanged: (_) => setState(() => _checked = false),
            decoration: const InputDecoration(hintText: 'Dear diary, today I…'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('$words kelime', style: TextStyle(color: Brand.muted)),
          ),
          Row(
            children: [
              Expanded(
                child: PressableButton(
                  label: 'KONTROL ET',
                  outlined: true,
                  onPressed: words == 0 ? null : _runCheck,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PressableButton(label: 'KAYDET', color: Brand.streak, onPressed: _save),
              ),
            ],
          ),
          if (_checked)
            PopIn(
              from: 0.9,
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _errors.isEmpty ? Brand.successBg : Brand.accentBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _errors.isEmpty
                    ? const Text(
                        'Türklerin sık yaptığı hatalardan birini bulamadım. Harika! '
                        '(Ayrıntılı kontrol, yapay zekâ sunucusu bağlanınca gelecek.)',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${kidEmoji('💡')}Daha doğal: ${_errors.first.corrected}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          WhyWrongSection(errors: _errors, maxErrors: 6),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: () => setState(() {
                              _text.text = _errors.first.corrected;
                              _checked = false;
                            }),
                            child: const Text('Düzeltmeyi uygula'),
                          ),
                        ],
                      ),
              ),
            ),
          if (past.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('Önceki günler', style: Theme.of(context).textTheme.titleLarge),
            for (final day in past)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TapCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        day,
                        style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(diary[day]!),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Entry to the guided "Gramer Yolu", with progress and the next lesson.
class _GrammarPathCard extends ConsumerWidget {
  const _GrammarPathCard({required this.notes});
  final NotesBundle notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessons = ref.watch(grammarLessonsProvider).value ?? const <GrammarLesson>[];
    final p = ref.watch(progressProvider);
    final done = lessons.where((l) => p.isDone(lessonNodeId(l))).length;
    final next = lessons.where((l) => !p.isDone(lessonNodeId(l))).firstOrNull;
    return TapCard(
      selected: true,
      color: Brand.primary,
      onTap: () => _push(context, GrammarPathScreen(notes: notes)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Glyph(emoji: '🧭', icon: Icons.route_outlined, size: 30),
              const SizedBox(width: 10),
              Expanded(child: Text('Gramer Yolu', style: Theme.of(context).textTheme.titleLarge)),
              Text(
                '$done/${lessons.length}',
                style: TextStyle(color: Brand.primary, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Notlarından hazırlanan adım adım dersler: formül, zaman çizelgesi, '
            'Türkçe karşılaştırma, yaygın hatalar ve mini test.',
            style: TextStyle(color: Brand.muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          GlossyProgress(
            value: lessons.isEmpty ? 0 : done / lessons.length,
            color: Brand.primary,
            height: 10,
          ),
          if (next != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Glyph(emoji: next.emoji, icon: Icons.play_lesson_outlined, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Sıradaki: ${next.title}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Icon(Icons.play_circle_fill_rounded, color: Brand.primary, size: 30),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
