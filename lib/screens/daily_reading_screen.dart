import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings.dart';
import '../services/billing/premium.dart' show premiumProvider;
import '../services/growth/daily_reading.dart';
import '../services/talk_about.dart';
import '../theme.dart';
import '../ui/premium_offer.dart' show openPaywall;

/// Paywall placement (analytics) of the locked "Bunu konuşalım" button.
const dailyTalkPlacement = 'daily_reading_talk';

/// Öğren: one compact row to today's reading. Hidden once it was finished
/// today, while nothing is available, and while it loads.
class DailyReadingCard extends ConsumerWidget {
  const DailyReadingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(dailyReadingProvider).value;
    if (r == null) return const SizedBox.shrink();
    if (ref.watch(dailyReadDoneProvider).contains(r.id)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TapCard(
        key: const ValueKey('daily-reading-card'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: () => openDailyReading(context),
        child: Row(
          children: [
            const Glyph(emoji: '📰', icon: Icons.auto_stories_rounded, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Günün okuması · ${r.level}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  Text(
                    r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Brand.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Brand.primary),
          ],
        ),
      ),
    );
  }
}

Future<void> openDailyReading(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DailyReadingScreen()));

class DailyReadingScreen extends ConsumerStatefulWidget {
  const DailyReadingScreen({super.key});

  @override
  ConsumerState<DailyReadingScreen> createState() => _DailyReadingScreenState();
}

class _DailyReadingScreenState extends ConsumerState<DailyReadingScreen> {
  /// An older reading opened from "Önceki günler"; null = today's.
  DailyReading? _older;

  @override
  Widget build(BuildContext context) {
    final level = ref.watch(dailyLevelProvider);
    final today = ref.watch(dailyReadingProvider);
    final reading = _older ?? today.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Günün okuması')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final l in dailyReadingLevels)
                  ChoiceChip(
                    key: ValueKey('daily-level-$l'),
                    label: Text(l),
                    selected: l == level,
                    onSelected: (_) {
                      setState(() => _older = null);
                      ref.read(dailyLevelProvider.notifier).pick(l);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (reading == null)
              today.isLoading
                  ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                  : const _Empty()
            else
              _ReadingBody(key: ValueKey(reading.id), reading: reading),
            const SizedBox(height: 24),
            _History(
              level: level,
              currentId: reading?.id,
              onOpen: (r) => setState(() => _older = r.date == today.value?.date ? null : r),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('daily-reading-empty'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(14)),
    child: const Text(
      'Bugünün okuması henüz hazır değil ya da internete bağlı değilsin. '
      'Bağlandığında son günlerin okumaları telefonuna kaydedilir, internetsiz de okuyabilirsin.',
      style: TextStyle(height: 1.4),
    ),
  );
}

class _ReadingBody extends ConsumerStatefulWidget {
  const _ReadingBody({super.key, required this.reading});
  final DailyReading reading;

  @override
  ConsumerState<_ReadingBody> createState() => _ReadingBodyState();
}

class _ReadingBodyState extends ConsumerState<_ReadingBody> {
  final Map<int, int> _picked = {};

  DailyReading get r => widget.reading;

  void _pick(int q, int option) {
    if (_picked.containsKey(q)) return;
    setState(() => _picked[q] = option);
    if (_picked.length == r.questions.length) ref.read(dailyReadDoneProvider.notifier).mark(r);
  }

  /// The text with the glossed words in bold.
  List<TextSpan> _spans(String paragraph) {
    final words = [for (final g in r.glossary) if (g.word.isNotEmpty) RegExp.escape(g.word)];
    if (words.isEmpty) return [TextSpan(text: paragraph)];
    final re = RegExp('(${words.join('|')})', caseSensitive: false);
    final out = <TextSpan>[];
    var at = 0;
    for (final m in re.allMatches(paragraph)) {
      if (m.start > at) out.add(TextSpan(text: paragraph.substring(at, m.start)));
      out.add(
        TextSpan(
          text: m.group(0),
          style: TextStyle(fontWeight: FontWeight.w800, color: Brand.primary),
        ),
      );
      at = m.end;
    }
    if (at < paragraph.length) out.add(TextSpan(text: paragraph.substring(at)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final right = [for (final e in _picked.entries) if (r.questions[e.key].answer == e.value) e.key].length;
    final finished = _picked.length == r.questions.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${r.kind == 'news' ? 'Haber tadında' : 'Kısa hikâye'} · ${r.level} · ${r.date}',
          style: TextStyle(color: Brand.muted, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(r.title, key: const ValueKey('daily-reading-title'), style: t.headlineSmall),
        const SizedBox(height: 12),
        for (final para in r.text.split(RegExp(r'\n\s*\n')))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text.rich(
              TextSpan(children: _spans(para.trim())),
              style: TextStyle(fontSize: 17, height: 1.5, color: Brand.ink),
            ),
          ),
        if (r.summaryTr.isNotEmpty)
          Text('Özet: ${r.summaryTr}', style: TextStyle(color: Brand.muted, fontStyle: FontStyle.italic)),
        const SizedBox(height: 20),
        Text('Kelimeler', style: t.titleMedium),
        const SizedBox(height: 8),
        for (final g in r.glossary)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TapCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: g.word, style: const TextStyle(fontWeight: FontWeight.w900)),
                        TextSpan(text: '  ${g.meaningTr}'),
                      ],
                    ),
                  ),
                  if (g.example.isNotEmpty)
                    Text(g.example, style: TextStyle(color: Brand.muted, fontSize: 13, height: 1.3)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text('Sorular', style: t.titleMedium),
        const SizedBox(height: 8),
        for (final (qi, q) in r.questions.indexed) ...[
          Text('${qi + 1}. ${q.question}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final (oi, o) in q.options.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: TapCard(
                key: ValueKey('daily-q$qi-o$oi'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: switch (_picked[qi]) {
                  null => null,
                  _ when oi == q.answer => Brand.successBg,
                  final p when p == oi => Brand.errorBg,
                  _ => null,
                },
                onTap: () => _pick(qi, oi),
                child: Text(o),
              ),
            ),
          if (_picked.containsKey(qi) && q.explanationTr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(q.explanationTr, style: TextStyle(color: Brand.muted, fontSize: 13)),
            ),
          const SizedBox(height: 8),
        ],
        if (finished)
          Text(
            '${r.questions.length} sorudan $right doğru!',
            key: const ValueKey('daily-reading-score'),
            style: TextStyle(fontWeight: FontWeight.w900, color: Brand.success, fontSize: 16),
          ),
        const SizedBox(height: 12),
        _TalkButton(reading: r),
      ],
    );
  }
}

/// "Bunu konuşalım": Premium opens the voice chat about the text; without
/// Premium the button shows a lock and opens the paywall when tapped. Hidden
/// until the voice conversation registers a launcher, and in Çocuk modu.
class _TalkButton extends ConsumerWidget {
  const _TalkButton({required this.reading});
  final DailyReading reading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launch = ref.watch(talkAboutLauncherProvider);
    if (launch == null || ref.watch(appSettingsProvider.select((s) => s.isKid))) return const SizedBox.shrink();
    final premium = ref.watch(premiumProvider);
    return FilledButton.icon(
      key: const ValueKey('daily-talk'),
      icon: Icon(premium ? Icons.record_voice_over_rounded : Icons.lock_rounded),
      label: Text(premium ? 'Bunu konuşalım' : 'Bunu konuşalım · Premium'),
      onPressed: () {
        if (!premium) {
          openPaywall(context, dailyTalkPlacement);
          return;
        }
        launch(
          context,
          TalkTopic(
            topic: TalkTopic.clip(reading.title),
            context: reading.text,
            opener: reading.talkPrompt,
            level: reading.level,
          ),
        );
      },
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.level, required this.currentId, required this.onOpen});
  final String level;
  final String? currentId;
  final ValueChanged<DailyReading> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dailyReadingProvider); // refresh when today's arrives
    final done = ref.watch(dailyReadDoneProvider);
    final list = ref.read(dailyReadingCacheProvider).history(level).where((r) => r.id != currentId).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Önceki günler', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final r in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TapCard(
              key: ValueKey('daily-history-${r.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              onTap: () => onOpen(r),
              child: Row(
                children: [
                  Expanded(child: Text('${r.date} · ${r.title}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (done.contains(r.id)) Icon(Icons.check_circle_rounded, color: Brand.success, size: 20),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
