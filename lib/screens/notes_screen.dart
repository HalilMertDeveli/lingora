import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/emoji_compat.dart';
import '../core/tr_errors.dart';
import '../data/notes_index.dart';
import '../data/notes_practice.dart';
import '../data/notes_repository.dart';
import '../data/practice.dart';
import '../data/progress.dart';
import '../data/review_grade.dart';
import '../models/grammar_lesson.dart';
import '../models/notes.dart';
import '../services/speech.dart';
import '../theme.dart';
import '../ui/guide_view.dart';
import '../ui/markdown_text.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import '../ui/review_card.dart';
import '../ui/why_wrong.dart';
import 'lesson_result_screen.dart';
import 'grammar_path_screen.dart';
import 'lesson_screen.dart';
import 'my_notes_screen.dart';
import 'reading_screen.dart';
import 'vocab/word_list_screen.dart';

Color get _notesColor => Brand.tone(const Color(0xFF2F80ED));

/// Home of the "Notlarım" track: the shared course notes (grammar, dictionary)
/// and the learner's own notes and words.
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
    final own = words.where(isOwnWord).toList();
    final ownDue = dueWordCount(own, p, now);
    final myNotes = p.visibleNotes.length;

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
                      'Hazır ders notları: ${notes.topics.length} gramer konusu ve ${notes.words.length} kelime. '
                      'Kendi notlarını ve kelimelerini de ekle, tekrar et.',
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
        const SizedBox(height: 14),
        _NotesSearchBar(onTap: () => _push(context, AllNotesScreen(notes: notes))),
        const _NotesSection('BUGÜN'),
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
          icon: Icons.edit_note_rounded,
          color: Brand.streak,
          title: 'Günlüğüm',
          subtitle: wroteToday ? 'Bugünkü günlüğünü yazdın' : 'Bugün İngilizce birkaç cümle yaz',
          badge: wroteToday ? '✓' : null,
          onTap: () => _push(context, DiaryScreen(prompts: notes.diaryPrompts)),
        ),
        const _NotesSection('KENDİ NOTLARIM'),
        _BigAction(
          key: const ValueKey('my-notes'),
          icon: Icons.sticky_note_2_outlined,
          color: _notesColor,
          title: 'Notlarım',
          subtitle: myNotes == 0
              ? 'İlk notunu yaz: bir kural, bir kalıp, aklında kalsın istediğin her şey'
              : '$myNotes not · ekle, düzenle, ara',
          onTap: () => _push(context, const MyNotesScreen()),
        ),
        _BigAction(
          key: const ValueKey('my-words'),
          icon: Icons.bookmark_add_outlined,
          color: Brand.success,
          title: 'Kelimelerim',
          subtitle: own.isEmpty
              ? 'Kendi kelimelerini ekle; tekrar sırasına girsinler'
              : '${own.length} kelime · ${ownDue > 0 ? '$ownDue tanesi tekrar bekliyor' : 'ekle, düzenle, tekrar et'}',
          badge: ownDue > 0 ? '$ownDue' : null,
          onTap: () => _push(context, WordListScreen(notes: notes, initialTopic: customTopic)),
        ),
        const _NotesSection('DERS NOTLARI'),
        _GrammarPathCard(notes: notes),
        const SizedBox(height: 10),
        _BigAction(
          icon: Icons.menu_book_rounded,
          color: Brand.primary,
          title: 'Gramer konuları',
          subtitle:
              '${notes.topics.length} konu, ${grammarSections(notes.topics).length} bölümde, aranabilir',
          onTap: () => _push(context, GrammarListScreen(notes: notes)),
        ),
        _BigAction(
          icon: Icons.translate_rounded,
          color: Brand.success,
          title: 'Sözlük',
          subtitle: '${words.length} kelime, ${wordTopics(words).length} konuda, A-Z sıralı',
          onTap: () => _push(context, WordListScreen(notes: notes)),
        ),
        _BigAction(
          icon: Icons.quiz_rounded,
          color: Brand.accent,
          title: 'Kelime testi',
          subtitle: 'Sözlükten eşleştirme ve seçmeli sorular',
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
          icon: Icons.code_rounded,
          color: const Color(0xFF0F766E),
          title: 'Yazılım kelimeleri',
          subtitle: 'Yazılımcı İngilizcesi kartlarıyla: örnek commit, PR ve stand-up cümleleri',
          onTap: () => _push(context, const NotesSoftwareWordsScreen()),
        ),
        const _NotesSection('OKUMA'),
        const ReadingEntryCard(),
      ],
    );
  }
}

/// Section heading on the notes home ("BUGÜN", "GRAMER"…).
class _NotesSection extends StatelessWidget {
  const _NotesSection(this.title);
  final String title;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 8), child: SectionLabel(title));
}

/// Looks like a search box; opens the overview of all notes.
class _NotesSearchBar extends StatelessWidget {
  const _NotesSearchBar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TapCard(
    key: const ValueKey('notes-overview'),
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Icon(Icons.search_rounded, color: Brand.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Tüm notlarımda ara', style: TextStyle(color: Brand.muted, fontSize: 15)),
        ),
        Text(
          'İçindekiler',
          style: TextStyle(color: _notesColor, fontWeight: FontWeight.w800, fontSize: 13),
        ),
        Icon(Icons.chevron_right_rounded, color: _notesColor),
      ],
    ),
  );
}

class _BigAction extends StatelessWidget {
  const _BigAction({
    super.key,
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

class _FlashcardScreenState extends ConsumerState<FlashcardScreen> {
  final _started = DateTime.now();
  int _pos = 0;
  int _known = 0;

  NoteWord get _w => widget.words[_pos];

  void _answer(ReviewGrade grade) {
    ref.read(progressProvider.notifier).gradeWord(_w.id, grade);
    if (grade.known) _known++;
    if (_pos + 1 >= widget.words.length) {
      _finish();
      return;
    }
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
        body: const Center(child: EmptyState(message: 'Şu an tekrar edilecek kelime yok. Yarın tekrar bak!')),
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
                    tooltip: 'Kapat',
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: ReviewDeck(
                  key: ValueKey('note-card-$_pos'),
                  card: ReviewCardData.fromNoteWord(w),
                  behind: widget.words.length - _pos - 1,
                  color: _notesColor,
                  intervalOf: (g) =>
                      intervalLabel(scheduleReview(ref.read(progressProvider).wordBox[w.id], g).days),
                  onGrade: _answer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The personal dictionary: topics as chapters (own words first, then A-Z),
/// words A-Z inside each topic, searchable in English and Turkish.
class WordListScreen extends ConsumerStatefulWidget {
  const WordListScreen({super.key, required this.notes, this.initialTopic, this.initialQuery = ''});
  final NotesBundle notes;
  final String? initialTopic;
  final String initialQuery;

  @override
  ConsumerState<WordListScreen> createState() => _WordListScreenState();
}

class _WordListScreenState extends ConsumerState<WordListScreen> {
  late String _query = widget.initialQuery;
  late String? _topic = widget.initialTopic;
  late final _search = TextEditingController(text: widget.initialQuery);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(progressProvider);
    final words = dictionaryWords(widget.notes, p);
    final topics = wordTopics(words);
    if (_topic == customTopic && !topics.contains(customTopic)) topics.insert(0, customTopic);
    final counts = <String, int>{};
    for (final w in words) {
      counts[w.topic] = (counts[w.topic] ?? 0) + 1;
    }
    final sections = wordSections(words, topic: _topic, query: _query);
    final total = sections.fold(0, (n, s) => n + s.items.length);
    // Flattened rows: a heading per topic, then its words.
    final rows = <Object>[
      for (final s in sections) ...[s, ...s.items],
    ];
    return Scaffold(
      appBar: AppBar(title: Text('Sözlük (${words.length})')),
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
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Kelime ara (EN veya TR)',
              ),
            ),
          ),
          _ChipBar(
            labels: [for (final t in topics) '$t (${counts[t]})'],
            values: topics,
            allLabel: 'Tümü (${words.length})',
            selected: _topic,
            onSelected: (t) => setState(() => _topic = t),
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
          if (_query.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('$total sonuç', style: TextStyle(color: Brand.muted)),
              ),
            ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: EmptyState(
                      message: _topic == customTopic && _query.trim().isEmpty
                          ? 'Henüz kelime eklemedin. "Kelime ekle" ile başla; eklediğin kelimeler '
                                'tekrar sırasına girer.'
                          : 'Bu aramayla eşleşen kelime yok.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final row = rows[i];
                      if (row is NoteSection<NoteWord>) {
                        return _SectionHeader(title: row.title, count: row.items.length);
                      }
                      final w = row as NoteWord;
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
                        onTap: () => showNoteWordSheet(context, ref, w),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Details of one dictionary word in a bottom sheet.
void showNoteWordSheet(BuildContext context, WidgetRef ref, NoteWord w) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  // Grows and scrolls at the largest font instead of cutting its end off.
  isScrollControlled: true,
  builder: (sheet) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(w.en, style: Theme.of(sheet).textTheme.headlineSmall)),
              IconButton.filledTonal(
                tooltip: 'Dinle',
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
            Text('${kidEmoji(legacyEmoji('🧠'))}Hafıza ipucu: ${w.story}'),
          ],
          if (isOwnWord(w)) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  key: const ValueKey('edit-word'),
                  onPressed: () {
                    Navigator.pop(sheet);
                    showAddWordDialog(context, edit: w);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Düzenle'),
                ),
                TextButton.icon(
                  key: const ValueKey('delete-word'),
                  onPressed: () {
                    ref.read(progressProvider.notifier).removeCustomWord(w.id);
                    Navigator.pop(sheet);
                  },
                  icon: Icon(Icons.delete_outline_rounded, color: Brand.error),
                  label: Text('Sil', style: TextStyle(color: Brand.error)),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  ),
);

/// Horizontal row of chips: an optional first chip, then one per value.
class _ChipBar extends StatelessWidget {
  const _ChipBar({
    required this.labels,
    required this.values,
    required this.allLabel,
    required this.selected,
    required this.onSelected,
  });
  final List<String> labels;
  final List<String> values;
  final String allLabel;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(allLabel),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (var i = 0; i < values.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(labels[i]),
                selected: selected == values[i],
                onSelected: (_) => onSelected(values[i]),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Chapter heading inside a notes list: title and how many notes it holds.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.title, required this.count, this.number});
  final String title;
  final int count;
  final int? number;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
    child: Row(
      children: [
        if (number != null) ...[
          Text('$number.', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _notesColor)),
          const SizedBox(width: 6),
        ],
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        _CountPill(count),
      ],
    ),
  );
}

class _CountPill extends StatelessWidget {
  const _CountPill(this.count);
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: _notesColor.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      '$count',
      style: TextStyle(color: _notesColor, fontWeight: FontWeight.w800, fontSize: 13),
    ),
  );
}

/// One grammar topic as a list card: its number in the notebook, title, source.
class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic, required this.all, this.number, this.step});
  final GrammarTopic topic;
  final List<GrammarTopic> all;
  final String? number;

  /// Step of the Gramer Yolu that teaches this topic, if any.
  final int? step;

  @override
  Widget build(BuildContext context) {
    final t = topic;
    final details = [
      if (number == null) t.category,
      if (t.rules.isNotEmpty) '${t.rules.length} kural',
      '${t.examples.length} örnek',
      if (step != null) 'Gramer Yolu adım $step',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TapCard(
        onTap: () => _push(context, TopicScreen(topic: t, all: all)),
        child: Row(
          children: [
            if (number != null)
              SizedBox(
                width: 40,
                child: Text(
                  number!,
                  style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, style: Theme.of(context).textTheme.titleMedium),
                  Text(details.join(' · '), style: TextStyle(color: Brand.muted, fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Brand.muted),
          ],
        ),
      ),
    );
  }
}

/// Grammar notes as a numbered notebook: chapters in curriculum order
/// (1. Temeller, 2. To be…), topics numbered inside (1.1, 1.2…), with a
/// table of contents that jumps to a chapter.
class GrammarListScreen extends ConsumerStatefulWidget {
  const GrammarListScreen({super.key, required this.notes, this.initialCategory, this.initialQuery = ''});
  final NotesBundle notes;
  final String? initialCategory;
  final String initialQuery;

  @override
  ConsumerState<GrammarListScreen> createState() => _GrammarListScreenState();
}

class _GrammarListScreenState extends ConsumerState<GrammarListScreen> {
  late String _query = widget.initialQuery;
  late final _search = TextEditingController(text: widget.initialQuery);
  final _keys = <String, GlobalKey>{};

  /// Numbers come from the whole notebook so they stay put while searching.
  late final _chapters = grammarSections(widget.notes.topics);

  @override
  void initState() {
    super.initState();
    final c = widget.initialCategory;
    if (c != null) WidgetsBinding.instance.addPostFrameCallback((_) => _jump(c, animate: false));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  GlobalKey _key(String category) => _keys.putIfAbsent(category, GlobalKey.new);

  void _jump(String category, {bool animate = true}) {
    final ctx = _keys[category]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: animate ? const Duration(milliseconds: 300) : Duration.zero);
  }

  @override
  Widget build(BuildContext context) {
    final sections = grammarSections(widget.notes.topics, query: _query);
    // The first Gramer Yolu step built on each topic.
    final ordered = orderedLessons(ref.watch(grammarLessonsProvider).value ?? const <GrammarLesson>[]);
    final stepOfTopic = <String, int>{};
    for (final (i, l) in ordered.indexed) {
      for (final id in l.noteIds) {
        stepOfTopic.putIfAbsent(id, () => i + 1);
      }
    }
    final chapterNo = {for (var i = 0; i < _chapters.length; i++) _chapters[i].title: i + 1};
    final topicNo = {
      for (final c in _chapters)
        for (var i = 0; i < c.items.length; i++) c.items[i].id: '${chapterNo[c.title]}.${i + 1}',
    };
    return Scaffold(
      appBar: AppBar(title: Text('Gramer konuları (${widget.notes.topics.length})')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Konu ara (ör. unless, wish)',
              ),
            ),
          ),
          if (sections.length > 1)
            _ChipBar(
              labels: [for (final s in sections) '${chapterNo[s.title]}. ${s.title}'],
              values: [for (final s in sections) s.title],
              allLabel: 'Başa dön',
              selected: null,
              onSelected: (c) => _jump(c ?? sections.first.title),
            ),
          Expanded(
            child: sections.isEmpty
                ? const Center(child: EmptyState(message: 'Bu aramayla eşleşen konu yok.'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_query.trim().isEmpty) ...[
                          _GrammarPathCard(notes: widget.notes),
                          const SizedBox(height: 4),
                        ],
                        for (final s in sections) ...[
                          _SectionHeader(
                            key: _key(s.title),
                            title: s.title,
                            count: s.items.length,
                            number: chapterNo[s.title],
                          ),
                          for (final t in s.items)
                            _TopicCard(
                              topic: t,
                              all: widget.notes.topics,
                              number: topicNo[t.id],
                              step: stepOfTopic[t.id],
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// "Tüm notlarım": the whole notebook in one place. Without a search it is a
/// table of contents (grammar chapters, dictionary topics, diary); with a
/// search it shows matching grammar topics, words and diary days together.
class AllNotesScreen extends ConsumerStatefulWidget {
  const AllNotesScreen({super.key, required this.notes});
  final NotesBundle notes;

  @override
  ConsumerState<AllNotesScreen> createState() => _AllNotesScreenState();
}

class _AllNotesScreenState extends ConsumerState<AllNotesScreen> {
  static const _preview = 5;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final notes = widget.notes;
    final p = ref.watch(progressProvider);
    final words = dictionaryWords(notes, p);
    return Scaffold(
      appBar: AppBar(title: const Text('Tüm notlarım')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          TextField(
            key: const ValueKey('all-notes-search'),
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Gramer, kelime veya günlükte ara',
            ),
          ),
          if (_query.trim().isNotEmpty)
            ..._results(context, notes, words, p.diary)
          else
            ..._contents(context, notes, words, p.diary),
        ],
      ),
    );
  }

  List<Widget> _contents(
    BuildContext context,
    NotesBundle notes,
    List<NoteWord> words,
    Map<String, String> diary,
  ) {
    final chapters = grammarSections(notes.topics);
    final days = diaryDays(diary);
    return [
      _SectionHeader(title: 'Notlarım', count: ref.read(progressProvider).visibleNotes.length),
      TapCard(
        onTap: () => _push(context, const MyNotesScreen()),
        child: Row(
          children: [
            Expanded(
              child: Text(
                ref.read(progressProvider).visibleNotes.isEmpty
                    ? 'Henüz notun yok. Kendi notlarını buraya ekleyebilirsin.'
                    : ref.read(progressProvider).visibleNotes.take(3).map(noteTitle).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Brand.muted),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Brand.muted),
          ],
        ),
      ),
      _SectionHeader(title: 'Gramer konuları', count: notes.topics.length),
      _IndexCard(
        rows: [
          for (var i = 0; i < chapters.length; i++)
            _IndexRow(
              label: '${i + 1}. ${chapters[i].title}',
              count: chapters[i].items.length,
              onTap: () =>
                  _push(context, GrammarListScreen(notes: notes, initialCategory: chapters[i].title)),
            ),
        ],
      ),
      _SectionHeader(title: 'Sözlük', count: words.length),
      _IndexCard(
        rows: [
          for (final s in wordSections(words))
            _IndexRow(
              label: s.title,
              count: s.items.length,
              onTap: () => _push(context, WordListScreen(notes: notes, initialTopic: s.title)),
            ),
        ],
      ),
      _SectionHeader(title: 'Günlük', count: days.length),
      TapCard(
        onTap: () => _push(context, DiaryScreen(prompts: notes.diaryPrompts)),
        child: Row(
          children: [
            Expanded(
              child: Text(
                days.isEmpty
                    ? 'Henüz günlük yazmadın. İlk sayfanı bugün yaz!'
                    : 'Son yazdığın gün: ${days.first}',
                style: TextStyle(color: Brand.muted),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Brand.muted),
          ],
        ),
      ),
    ];
  }

  List<Widget> _results(
    BuildContext context,
    NotesBundle notes,
    List<NoteWord> words,
    Map<String, String> diary,
  ) {
    final topics = notes.topics.where((t) => topicMatches(t, _query)).toList();
    final found = wordSections(words, query: _query).expand((s) => s.items).toList();
    final days = diaryDays(diary, query: _query);
    final mine = ref.read(progressProvider).visibleNotes.where((n) => userNoteMatches(n, _query)).toList();
    if (topics.isEmpty && found.isEmpty && days.isEmpty && mine.isEmpty) {
      return const [SizedBox(height: 40), EmptyState(message: 'Notlarda bununla eşleşen bir şey bulamadım.')];
    }
    Widget more(int n, VoidCallback onTap) => n <= _preview
        ? const SizedBox.shrink()
        : Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onTap, child: Text('Tümünü gör ($n)')),
          );
    return [
      if (mine.isNotEmpty) ...[
        _SectionHeader(title: 'Notlarım', count: mine.length),
        for (final n in mine.take(_preview)) UserNoteCard(note: n),
        more(mine.length, () => _push(context, const MyNotesScreen())),
      ],
      if (topics.isNotEmpty) ...[
        _SectionHeader(title: 'Gramer', count: topics.length),
        for (final t in topics.take(_preview)) _TopicCard(topic: t, all: notes.topics),
        more(topics.length, () => _push(context, GrammarListScreen(notes: notes, initialQuery: _query))),
      ],
      if (found.isNotEmpty) ...[
        _SectionHeader(title: 'Kelimeler', count: found.length),
        for (final w in found.take(_preview))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(w.en, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${w.tr} · ${w.topic}'),
            onTap: () => showNoteWordSheet(context, ref, w),
          ),
        more(found.length, () => _push(context, WordListScreen(notes: notes, initialQuery: _query))),
      ],
      if (days.isNotEmpty) ...[
        _SectionHeader(title: 'Günlük', count: days.length),
        for (final d in days.take(_preview))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(d, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(diary[d]!, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => _push(context, DiaryScreen(prompts: notes.diaryPrompts)),
          ),
      ],
    ];
  }
}

/// A card listing the chapters of the notebook, each with its note count.
class _IndexCard extends StatelessWidget {
  const _IndexCard({required this.rows});
  final List<_IndexRow> rows;

  @override
  Widget build(BuildContext context) => TapCard(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 14, endIndent: 14, color: Brand.line),
          rows[i],
        ],
      ],
    ),
  );
}

class _IndexRow extends StatelessWidget {
  const _IndexRow({required this.label, required this.count, required this.onTap});
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CountPill(count),
        Icon(Icons.chevron_right_rounded, color: Brand.muted),
      ],
    ),
    onTap: onTap,
  );
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(label: Text(topic.category)),
                  ),
                  const SizedBox(height: 10),
                  ...topicGuideCards(context, topic, onSpeak: (en) => ref.read(speechProvider).say(en)),
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

/// "Olumlu: I do" → "**Olumlu:** I do": a short label before a colon reads
/// as the rule's title. Rules that already use markdown stay as they are.
String _boldLead(String rule) {
  if (rule.contains('*')) return rule;
  final m = RegExp(r'^([^:]{1,24}):\s+(.+)$').firstMatch(rule);
  return m == null ? rule : '**${m[1]}:** ${m[2]}';
}

/// A grammar note as guide cards: the explanation, its rules (coloured
/// bullets, formulas as chips) and its examples (with a speaker button).
List<Widget> topicGuideCards(
  BuildContext context,
  GrammarTopic topic, {
  required void Function(String en) onSpeak,
}) {
  final body = topic.body.trim();
  final rules = [
    for (final r in topic.rules)
      if (r.trim().isNotEmpty)
        parseMarkdown('- ${_boldLead(r.replaceAll('\n', ' ').trim())}', guide: true).first,
  ];
  Widget gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 16), child: w);
  return [
    if (body.isNotEmpty)
      gap(
        GuideCard.topic(
          context,
          key: const Key('note-explain'),
          title: 'Konu anlatımı',
          topic: GuideTopic.goal,
          child: MarkdownText(body, guide: true, color: guideLook(GuideTopic.goal, context.palette).color),
        ),
      ),
    if (rules.isNotEmpty)
      gap(
        GuideCard.topic(
          context,
          key: const Key('note-rules'),
          title: 'Kurallar',
          topic: GuideTopic.rule,
          child: MdBlocksView(blocks: rules, color: guideLook(GuideTopic.rule, context.palette).color),
        ),
      ),
    if (topic.examples.isNotEmpty)
      gap(
        GuideCard.topic(
          context,
          key: const Key('note-examples'),
          title: 'Örnekler',
          topic: GuideTopic.example,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in topic.examples)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ExampleBox(en: e.en, tr: e.tr, onSpeak: () => onSpeak(e.en)),
                ),
            ],
          ),
        ),
      ),
  ];
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
    ref.read(progressProvider.notifier).recordTrErrors(errors, text: _text.text);
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
    final lessons = orderedLessons(ref.watch(grammarLessonsProvider).value ?? const <GrammarLesson>[]);
    final p = ref.watch(progressProvider);
    final done = lessons.where((l) => p.isDone(lessonNodeId(l))).length;
    final next = nextGrammarLesson(lessons, p);
    return TapCard(
      selected: true,
      color: Brand.primary,
      onTap: () => _push(context, GrammarPathScreen(notes: notes)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Glyph(emoji: legacyEmoji('🧭'), icon: Icons.route_outlined, size: 30),
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
            'Ders notlarından hazırlanan adım adım dersler: formül, zaman çizelgesi, '
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
                  child: Text(
                    'Sıradaki · Adım ${lessons.indexOf(next) + 1}: ${next.title}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
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
