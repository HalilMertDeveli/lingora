import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress.dart';
import '../../data/vocab_practice.dart';
import '../../models/vocab.dart';
import '../../theme.dart';
import 'dev_scenario_screen.dart';
import 'discover_screen.dart';
import 'review_screen.dart';
import 'word_list_screen.dart';

const vocabColor = Color(0xFF0F766E);

/// Status colours on the knowledge map.
const statusColors = {
  VocabStatus.unknown: Color(0xFFE7E5EF),
  VocabStatus.learning: Color(0xFFFFB020),
  VocabStatus.known: Color(0xFF1FA971),
};

const statusLabels = {
  VocabStatus.unknown: 'Bilmiyor',
  VocabStatus.learning: 'Öğreniyor',
  VocabStatus.known: 'Biliyor',
};

void pushVocab(BuildContext context, Widget screen, {bool dialog = false}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: dialog, builder: (_) => screen));

/// Yazılımcı İngilizcesi track home: knowledge map, discover, review,
/// scenarios and topics.
class VocabHomeScreen extends ConsumerWidget {
  const VocabHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(vocabProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Kelimeler yüklenemedi: $e')),
        data: (v) => _VocabHome(bundle: v),
      );
}

class _VocabHome extends ConsumerWidget {
  const _VocabHome({required this.bundle});
  final VocabBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final now = ref.watch(clockProvider)();
    final entries = bundle.entries;
    final bands = rankBands(entries, p);
    final due = dueVocabCount(entries, p, now);
    final fresh = triageQueue(entries, p).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF134E4A), vocabColor]),
            borderRadius: BorderRadius.circular(22),
          ),
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
              const SizedBox(height: 14),
              KnowledgeMap(bands: bands),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Action(
          icon: Icons.replay_rounded,
          color: vocabColor,
          title: 'Tekrar et',
          subtitle: due > 0 ? '$due kelimenin tekrar zamanı geldi' : 'Şu an tekrar bekleyen kelime yok',
          badge: due > 0 ? '$due' : null,
          onTap: due == 0
              ? null
              : () => pushVocab(
                  context,
                  VocabReviewScreen(queue: reviewQueue(entries, p, now), all: entries),
                  dialog: true,
                ),
        ),
        _Action(
          icon: Icons.style_rounded,
          color: Brand.primary,
          title: 'Kelime keşfet',
          subtitle: fresh > 0
              ? 'Biliyorum / Öğreneceğim / Sonra: $fresh kelime sırada'
              : 'Tüm kelimeleri ayırdın 🎉',
          onTap: fresh == 0 ? null : () => pushVocab(context, DiscoverScreen(all: entries), dialog: true),
        ),
        _Action(
          icon: Icons.forum_rounded,
          color: Brand.streak,
          title: 'İş senaryoları',
          subtitle: 'Stand-up, kod incelemesi, commit, PR, mülakat: yaz ve karşılaştır',
          onTap: () => pushVocab(context, const DevScenarioListScreen()),
        ),
        _Action(
          icon: Icons.search_rounded,
          color: Brand.success,
          title: 'Tüm kelimeler',
          subtitle: 'Ara, anlamına ve örneklerine bak',
          onTap: () => pushVocab(context, VocabWordListScreen(title: 'Tüm kelimeler', entries: entries)),
        ),
        const SizedBox(height: 8),
        Text('Konular', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final t in bundle.topics) _TopicTile(topic: t, entries: bundle.inTopic(t.name), all: entries),
      ],
    );
  }
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
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
      ),
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
                style: const TextStyle(fontWeight: FontWeight.w900, color: vocabColor),
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
                        color: statusColors[s],
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
                  color:
                      statusColors[i < knownBlocks
                          ? VocabStatus.known
                          : i < knownBlocks + learningBlocks
                          ? VocabStatus.learning
                          : VocabStatus.unknown],
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
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _TopicTile extends ConsumerWidget {
  const _TopicTile({required this.topic, required this.entries, required this.all});
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
            Text(topic.emoji, style: const TextStyle(fontSize: 28)),
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
                              child: Container(color: statusColors[VocabStatus.known]),
                            ),
                          if (learning > 0)
                            Expanded(
                              flex: learning,
                              child: Container(color: statusColors[VocabStatus.learning]),
                            ),
                          if (entries.length - known - learning > 0)
                            Expanded(
                              flex: entries.length - known - learning,
                              child: Container(color: statusColors[VocabStatus.unknown]),
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
      title: '${topic.emoji} ${topic.name}',
      entries: entries,
      header: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: fresh.isEmpty
                  ? null
                  : () => pushVocab(context, DiscoverScreen(all: all, topic: topic.name), dialog: true),
              icon: const Icon(Icons.style_rounded),
              label: Text('Keşfet (${fresh.length})'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: due.isEmpty
                  ? null
                  : () => pushVocab(context, VocabReviewScreen(queue: due, all: all), dialog: true),
              icon: const Icon(Icons.replay_rounded),
              label: Text('Tekrar (${due.length})'),
            ),
          ),
        ],
      ),
    );
  }
}
