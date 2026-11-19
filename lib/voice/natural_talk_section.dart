import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../goals/learn_goal.dart';
import '../services/billing/premium.dart';
import '../theme.dart';
import 'talk_screen.dart';
import 'voice_catalog.dart';

/// "Doğal konuşma" on the Konuş page: free talk, characters and a phone
/// call. Adults only (the caller hides it in Çocuk modu).
class NaturalTalkSection extends ConsumerWidget {
  const NaturalTalkSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(learnGoalProvider)?.kind;
    final premium = ref.watch(premiumProvider);
    return Column(
      key: const Key('natural-talk'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('DOĞAL KONUŞMA'),
        const SizedBox(height: 8),
        TapCard(
          key: const Key('free-talk'),
          onTap: () => showFreeTalkSheet(context, ref),
          child: Row(
            children: [
              const IconBadge(icon: Icons.forum_rounded, emoji: '🗣️', size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Serbest sohbet', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      'Senaryo yok. Konunu seç ya da söyle, gerçek bir insanla konuşur gibi sohbet et.',
                      style: TextStyle(color: Brand.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Brand.muted),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // As tall as the tallest card needs (at least the old 128): a fixed
        // height cut the names at the largest font (QA, 69 dp overflow).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in charactersFor(goal))
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 128),
                      child: _CharacterCard(character: c),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('call-emma'),
          onPressed: () => openCharacterCall(context, ref),
          icon: const Icon(Icons.call_rounded),
          label: Text(premium ? "Emma'yı ara: telefonda konuş" : "Emma'yı ara (Premium)"),
        ),
      ],
    );
  }
}

class _CharacterCard extends ConsumerWidget {
  const _CharacterCard({required this.character});
  final Character character;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = character;
    return SizedBox(
      width: 150,
      child: TapCard(
        key: Key('character-${c.id}'),
        onTap: () => openTalk(context, ref, characterScenario(c)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(c.emoji, style: const TextStyle(fontSize: 26)),
                const Spacer(),
                InkResponse(
                  key: Key('character-voice-${c.id}'),
                  onTap: () => showVoiceSettingsSheet(context, character: c),
                  // A 48 dp target around the small icon.
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      size: 20,
                      color: Brand.muted,
                      semanticLabel: 'Ses seç',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              c.role,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Brand.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks (or types) the free-talk topic, then opens the chat.
Future<void> showFreeTalkSheet(BuildContext context, WidgetRef ref) async {
  final topic = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TopicSheet(topics: topicsFor(ref.read(learnGoalProvider)?.kind)),
  );
  if (topic == null || !context.mounted) return;
  await openTalk(context, ref, freeTalkScenario(topic));
}

class _TopicSheet extends StatefulWidget {
  const _TopicSheet({required this.topics});
  final List<TalkTopic> topics;

  @override
  State<_TopicSheet> createState() => _TopicSheetState();
}

class _TopicSheetState extends State<_TopicSheet> {
  final _own = TextEditingController();

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ne hakkında konuşalım?', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in widget.topics)
              ActionChip(
                key: Key('topic-${t.en}'),
                label: Text('${t.emoji} ${t.tr}'),
                onPressed: () => Navigator.pop(context, t.tr),
              ),
            ActionChip(
              key: const Key('topic-any'),
              label: const Text('🎲 Fark etmez'),
              onPressed: () => Navigator.pop(context, ''),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('topic-own'),
          controller: _own,
          maxLength: 60,
          textInputAction: TextInputAction.go,
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
          decoration: const InputDecoration(
            hintText: 'Kendi konun (ör. Galatasaray, yeni işim, Japonya gezisi)',
            counterText: '',
          ),
        ),
      ],
    ),
  );
}
