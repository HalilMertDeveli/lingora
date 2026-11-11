import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress.dart';
import '../../data/topic_themes.dart';
import '../../data/vocab_practice.dart';
import '../../models/vocab.dart';
import '../../theme.dart';
import '../../ui/motion.dart';
import '../../ui/theme_art.dart';
import '../../nav/tab_navigator.dart';
import 'discover_screen.dart';
import 'review_screen.dart';
import 'word_list_screen.dart';

/// Track colour (teal), softened in adult mode.
const _vocabTeal = Color(0xFF0F766E);
Color get vocabColor => Brand.tone(_vocabTeal);

/// Status colours on the knowledge map, from the active palette.
Color statusColor(VocabStatus s) => switch (s) {
  VocabStatus.unknown => Brand.line,
  VocabStatus.learning => Brand.accent,
  VocabStatus.known => Brand.success,
};

const statusLabels = {
  VocabStatus.unknown: 'Bilmiyor',
  VocabStatus.learning: 'Öğreniyor',
  VocabStatus.known: 'Biliyor',
};

void pushVocab(BuildContext context, Widget screen, {bool dialog = false}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: dialog, builder: (_) => screen));

/// Words whose review is due, for the "Tekrar" tab badge.
final vocabDueProvider = Provider<int>((ref) {
  final v = ref.watch(vocabProvider).value;
  if (v == null) return 0;
  return dueVocabCount(v.entries, ref.watch(progressProvider), ref.watch(clockProvider)());
});

/// Loads the word bundle, then builds a tab of the Yazılımcı İngilizcesi track.
class _VocabTab extends ConsumerWidget {
  const _VocabTab({required this.builder});
  final Widget Function(BuildContext context, VocabBundle bundle) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(vocabProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Kelimeler yüklenemedi: $e')),
        data: (v) => ScrollToTopOnReselect(child: builder(context, v)),
      );
}

/// "Keşfet" tab (home of the track): sort new words, then study by topic.
class VocabDiscoverTab extends ConsumerWidget {
  const VocabDiscoverTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _VocabTab(
    builder: (context, bundle) {
      final p = ref.watch(progressProvider);
      final entries = bundle.entries;
      final fresh = triageQueue(entries, p).length;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: context.lingora.hero(_vocabTeal, from: const Color(0xFF134E4A)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Yazılımcı İngilizcesi',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'Commit, PR, stand-up ve mülakatta gereken ${entries.length} kelime, önem sırasına göre.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Action(
            icon: Icons.style_rounded,
            color: Brand.primary,
            title: 'Kelime keşfet',
            subtitle: fresh > 0
                ? 'Biliyorum / Öğreneceğim / Sonra: $fresh kelime sırada'
                : 'Tüm kelimeleri ayırdın ${kidEmoji('🎉')}'.trim(),
            onTap: fresh == 0 ? null : () => pushVocab(context, DiscoverScreen(all: entries), dialog: true),
          ),
          const SizedBox(height: 8),
          const SectionLabel('KONULAR'),
          const SizedBox(height: 8),
          for (final (i, t) in bundle.topics.indexed)
            _TopicTile(index: i, topic: t, entries: bundle.inTopic(t.name), all: entries),
        ],
      );
    },
  );
}

/// "Tekrar" tab: spaced repetition of the words being learned.
class VocabReviewTab extends ConsumerWidget {
  const VocabReviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _VocabTab(
    builder: (context, bundle) {
      final p = ref.watch(progressProvider);
      final now = ref.watch(clockProvider)();
      final entries = bundle.entries;
      final due = reviewQueue(entries, p, now);
      final learning = entries.where((e) => vocabStatus(e, p) == VocabStatus.learning).toList();
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text('Tekrar', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Öğrendiğin kelimeler unutmadan önce geri gelir. Yanlış cevap ceza değildir, kelime sadece daha sık gelir.',
            style: TextStyle(color: Brand.muted),
          ),
          const SizedBox(height: 16),
          _Action(
            icon: Icons.replay_rounded,
            color: vocabColor,
            title: 'Tekrar et',
            subtitle: due.isNotEmpty
                ? '${due.length} kelimenin tekrar zamanı geldi'
                : 'Şu an tekrar bekleyen kelime yok',
            badge: due.isNotEmpty ? '${due.length}' : null,
            onTap: due.isEmpty
                ? null
                : () => pushVocab(context, VocabReviewScreen(queue: due, all: entries), dialog: true),
          ),
          _Action(
            icon: Icons.school_outlined,
            color: Brand.accent,
            title: 'Öğrendiğin kelimeler',
            subtitle: learning.isEmpty
                ? 'Keşfet sekmesinde "Öğreneceğim" dediklerin burada toplanır'
                : '${learning.length} kelime öğreniliyor',
            onTap: learning.isEmpty
                ? null
                : () => pushVocab(
                    context,
                    VocabWordListScreen(title: 'Öğrendiğin kelimeler', entries: learning),
                  ),
          ),
        ],
      );
    },
  );
}

/// "Harita" tab: the knowledge map and the full word list.
class VocabMapTab extends ConsumerWidget {
  const VocabMapTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _VocabTab(
    builder: (context, bundle) {
      final p = ref.watch(progressProvider);
      final entries = bundle.entries;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: context.lingora.hero(_vocabTeal, from: const Color(0xFF134E4A)),
            child: KnowledgeMap(bands: rankBands(entries, p)),
          ),
          const SizedBox(height: 16),
          _Action(
            icon: Icons.search_rounded,
            color: Brand.success,
            title: 'Tüm kelimeler',
            subtitle: 'Ara, anlamına ve örneklerine bak',
            onTap: () => pushVocab(context, VocabWordListScreen(title: 'Tüm kelimeler', entries: entries)),
          ),
        ],
      );
    },
  );
}

/// Rank bands as coloured blocks: one row per band, one cell per word
/// group, plus the estimated share of known words.
class KnowledgeMap extends StatelessWidget {
  const KnowledgeMap({super.key, required this.bands});
  final List<RankBand> bands;

  @override
  Widget build(BuildContext context) {
    final percent = knownPercent(bands);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(Radii.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Bilgi haritası', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              Text(
                '~%$percent biliyorsun',
                key: const Key('knownPercent'),
                style: TextStyle(fontWeight: FontWeight.w900, color: vocabColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final b in bands) _BandRow(band: b),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            children: [
              for (final s in VocabStatus.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor(s),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(statusLabels[s]!, style: TextStyle(fontSize: 12, color: Brand.muted)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BandRow extends StatelessWidget {
  const _BandRow({required this.band});
  final RankBand band;

  @override
  Widget build(BuildContext context) {
    // Ten blocks per band, coloured known → learning → unknown.
    const blocks = 10;
    final knownBlocks = (band.known * blocks / band.size).round();
    final learningBlocks = ((band.known + band.learning) * blocks / band.size).round() - knownBlocks;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(
              '${band.from}–${band.to}',
              style: TextStyle(fontSize: 12, color: Brand.muted, fontWeight: FontWeight.w700),
            ),
          ),
          for (var i = 0; i < blocks; i++)
            Expanded(
              child: Container(
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: statusColor(
                    i < knownBlocks
                        ? VocabStatus.known
                        : i < knownBlocks + learningBlocks
                        ? VocabStatus.learning
                        : VocabStatus.unknown,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
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
  final VoidCallback? onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Opacity(
      opacity: onTap == null ? 0.6 : 1,
      child: TapCard(
        onTap: onTap,
        child: Row(
          children: [
            IconBadge(icon: icon, color: color, size: 44),
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
          ],
        ),
      ),
    ),
  );
}

class _TopicTile extends ConsumerWidget {
  const _TopicTile({required this.index, required this.topic, required this.entries, required this.all});

  /// Position of the topic: picks its object from the code theme.
  final int index;
  final VocabTopic topic;
  final List<VocabEntry> entries;
  final List<VocabEntry> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final known = entries.where((e) => vocabStatus(e, p) == VocabStatus.known).length;
    final learning = entries.where((e) => vocabStatus(e, p) == VocabStatus.learning).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TapCard(
        onTap: () => pushVocab(context, VocabTopicScreen(topic: topic, entries: entries, all: all)),
        child: Row(
          children: [
            // The code theme's objects (terminal, branch, bug…) on a soft tile.
            Container(
              width: 46,
              height: 46,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: vocabColor.withValues(alpha: context.palette.isDark ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ThemeObject(
                theme: themeById(softwareThemeId),
                object: softwareTopicObject(index),
                size: 36,
                semanticLabel: topic.name,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(topic.name, style: Theme.of(context).textTheme.titleMedium),
                  Text(topic.description, style: TextStyle(color: Brand.muted, fontSize: 13)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 6,
                      child: Row(
                        children: [
                          if (known > 0)
                            Expanded(
                              flex: known,
                              child: Container(color: statusColor(VocabStatus.known)),
                            ),
                          if (learning > 0)
                            Expanded(
                              flex: learning,
                              child: Container(color: statusColor(VocabStatus.learning)),
                            ),
                          if (entries.length - known - learning > 0)
                            Expanded(
                              flex: entries.length - known - learning,
                              child: Container(color: statusColor(VocabStatus.unknown)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('$known/${entries.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// One topic: its own discover and review, plus the word list.
class VocabTopicScreen extends ConsumerWidget {
  const VocabTopicScreen({super.key, required this.topic, required this.entries, required this.all});
  final VocabTopic topic;
  final List<VocabEntry> entries;
  final List<VocabEntry> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final now = ref.watch(clockProvider)();
    final due = reviewQueue(entries, p, now);
    final fresh = triageQueue(entries, p);
    return VocabWordListScreen(
      title: '${kidEmoji(topic.emoji)}${topic.name}',
      entries: entries,
      header: Row(
        children: [
          Expanded(
            child: PressableButton(
              label: 'KEŞFET (${fresh.length})',
              onPressed: fresh.isEmpty
                  ? null
                  : () => pushVocab(context, DiscoverScreen(all: all, topic: topic.name), dialog: true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PressableButton(
              label: 'TEKRAR (${due.length})',
              color: vocabColor,
              onPressed: due.isEmpty
                  ? null
                  : () => pushVocab(context, VocabReviewScreen(queue: due, all: all), dialog: true),
            ),
          ),
        ],
      ),
    );
  }
}
