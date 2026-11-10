import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/league.dart';
import '../data/progress.dart';
import '../services/league_remote.dart';
import '../theme.dart';
import 'quests_screen.dart' show formatLeft;

class LeagueScreen extends ConsumerWidget {
  const LeagueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final now = ref.watch(clockProvider)();
    final start = weekStart(now);
    // Real members when signed in to Firebase, otherwise simulated rivals.
    final remote = ref.watch(remoteLeagueProvider).value;
    final tier = remote?.tier ?? p.leagueTier;
    final info = leagueTiers[tier];
    final table = remote?.table ?? standings(tier: tier, weekStart: start, now: now, userXp: p.weekXp(start));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: context.lingora.hero(info.color),
          child: Row(
            children: [
              Glyph(emoji: info.emoji, icon: Icons.military_tech_rounded, size: 48, color: Colors.white),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${info.name} Ligi',
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hafta bitimine ${formatLeft(untilWeekEnd(now))}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _TierStrip(current: tier),
        const SizedBox(height: 12),
        Text(
          switch ((tier > 0, tier < leagueTiers.length - 1)) {
            (false, _) => 'İlk $promoteCount kişi üst lige çıkar',
            (true, true) => 'İlk $promoteCount kişi üst lige çıkar, son $demoteCount kişi alt lige düşer',
            (true, false) => 'Son $demoteCount kişi alt lige düşer',
          },
          textAlign: TextAlign.center,
          style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < table.length; i++) ...[
          if (i == promoteCount && tier < leagueTiers.length - 1)
            _ZoneLine('YÜKSELME BÖLGESİ', Brand.success),
          if (i == leagueSize - demoteCount && tier > 0) _ZoneLine('DÜŞME BÖLGESİ', Brand.error),
          _Row(rank: i + 1, entry: table[i], tier: tier),
        ],
        const SizedBox(height: 16),
        Text(
          remote != null
              ? 'Bu hafta gerçek Lingora kullanıcılarıyla yarışıyorsun.'
              : 'Çevrimdışı mod: rakipler bu cihazda simüle edilir.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Brand.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _TierStrip extends StatelessWidget {
  const _TierStrip({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < leagueTiers.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Opacity(
            opacity: i <= current ? 1 : 0.3,
            child: Text(leagueTiers[i].emoji, style: TextStyle(fontSize: i == current ? 34 : 24)),
          ),
        ),
    ],
  );
}

class _ZoneLine extends StatelessWidget {
  const _ZoneLine(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: Divider(color: color, thickness: 2)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1),
          ),
        ),
        Expanded(child: Divider(color: color, thickness: 2)),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.rank, required this.entry, required this.tier});
  final int rank;
  final LeagueEntry entry;
  final int tier;

  @override
  Widget build(BuildContext context) {
    final rankColor = inPromotionZone(tier, rank)
        ? Brand.success
        : inDemotionZone(tier, rank)
        ? Brand.error
        : Brand.muted;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: entry.isUser ? Brand.primary.withValues(alpha: 0.10) : null,
        borderRadius: BorderRadius.circular(14),
        border: entry.isUser ? Border.all(color: Brand.primary, width: 2) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '$rank',
              style: TextStyle(color: rankColor, fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
          CircleAvatar(
            radius: 20,
            backgroundColor: Brand.surface,
            child: Text(entry.avatar, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.name,
              style: TextStyle(fontSize: 16, fontWeight: entry.isUser ? FontWeight.w900 : FontWeight.w600),
            ),
          ),
          Text(
            '${entry.xp} XP',
            style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Dialog shown once after a league week ends.
Future<void> showLeagueResult(BuildContext context, LeagueResult r) {
  final tier = leagueTiers[r.newTier];
  final (title, body) = r.promoted
      ? ('${tier.emoji} Terfi ettin!', 'Geçen haftayı ${r.rank}. bitirdin ve ${tier.name} Ligine yükseldin.')
      : r.demoted
      ? ('Alt lige düştün', 'Geçen haftayı ${r.rank}. bitirdin. Bu hafta ${tier.name} Liginde yeniden dene!')
      : ('Hafta bitti', 'Geçen haftayı ${r.rank}. bitirdin ve ${tier.name} Liginde kaldın.');
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, textAlign: TextAlign.center),
      content: Text(body, textAlign: TextAlign.center),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam'))],
    ),
  );
}
