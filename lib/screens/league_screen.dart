import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/league.dart';
import '../data/progress.dart';
import '../services/firebase/account_service.dart';
import '../services/league_remote.dart';
import '../services/profile.dart';
import '../theme.dart';
import '../ui/avatar.dart';
import 'auth_screen.dart';
import 'friends_screen.dart';
import 'quests_screen.dart' show formatLeft;

/// Calm amber for the line above which learners move down a tier: a
/// marker of the race, not a warning.
const _moveDownColor = Color(0xFFE08A00);

/// Dünya Ligi: this week's group of up to 100 learners (or the simulated
/// preview), the zones and the countdown.
class LeagueScreen extends ConsumerStatefulWidget {
  const LeagueScreen({super.key});

  @override
  ConsumerState<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends ConsumerState<LeagueScreen> {
  final _meKey = GlobalKey(debugLabel: 'league-me');

  /// The table kind the screen last scrolled to the user's row for.
  Type? _scrolledFor;

  void _scrollToMe(WorldLeagueView view) {
    if (_scrolledFor == view.runtimeType) return;
    _scrolledFor = view.runtimeType;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _meKey.currentContext;
      if (c == null || !c.mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          c,
          alignment: 0.4,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(progressProvider);
    final now = ref.watch(clockProvider)();
    final view = ref.watch(worldLeagueProvider).value ?? const WorldOffline();
    final live = view is WorldLive ? view.league : null;
    final tier = switch (view) {
      WorldLive(:final league) => league.tier,
      WorldNeedsJoin(:final tier) => tier,
      _ => p.leagueTier.clamp(0, leagueTiers.length - 1),
    };
    final info = leagueTiers[tier];
    final country = ref.watch(leagueCountryProvider);
    final List<LeagueEntry>? table = switch (view) {
      WorldLive(:final league) => league.table,
      WorldNeedsJoin() => null,
      _ => standings(
        tier: tier,
        weekStart: weekStart(now),
        now: now,
        userXp: p.weekXp(weekStart(now)),
        userCountry: country,
      ),
    };
    if (table != null) _scrollToMe(view);
    final size = table?.length ?? leagueSize;
    final zones = leagueZones(tier, size);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (!Brand.isKid)
                        Text(
                          view is WorldLive || view is WorldNeedsJoin
                              ? 'Dünya Ligi · $leagueSize kişilik grup'
                              : 'Dünya Ligi',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const SizedBox(height: 4),
                      _Countdown(serverWeek: view is WorldLive),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Friends and the shared streak (not in Çocuk modu: no social features for kids).
          if (!Brand.isKid) ...[
            const SizedBox(height: 12),
            TapCard(
              key: const ValueKey('league-friends'),
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FriendsScreen())),
              child: Row(
                children: [
                  const Text('🤝', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Arkadaşlar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        Text(
                          'Birbirinize destek olun, ortak seri yapın',
                          style: TextStyle(color: Brand.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Brand.muted),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _TierStrip(current: tier),
          const SizedBox(height: 12),
          Text(
            _zoneText(tier, zones),
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (view is WorldGuest) ...[const _GuestCard(), const SizedBox(height: 12)],
          if (view is WorldNeedsJoin) const _JoinCard(),
          if (table != null)
            for (var i = 0; i < table.length; i++) ...[
              if (i == zones.promote && zones.promote > 0) const _ZoneLine('↑ YÜKSELME BÖLGESİ', null),
              if (i == size - zones.demote && zones.demote > 0)
                const _ZoneLine('↓ ALT LİG BÖLGESİ', _moveDownColor),
              _Row(
                key: table[i].isUser ? _meKey : null,
                rank: i + 1,
                entry: table[i],
                tier: tier,
                size: size,
              ),
            ],
          const SizedBox(height: 16),
          Text(
            switch (view) {
              WorldLive(:final league) =>
                'Bu hafta ${league.countries > 1 ? '${league.countries} ülkeden ' : ''}'
                    '${league.members.length} Dilmaç kullanıcısıyla yarışıyorsun.',
              WorldGuest() => 'Örnek tablo: rakipler bu cihazda simüle edilir.',
              WorldNeedsJoin() => '',
              WorldOffline() => 'Çevrimdışı mod: rakipler bu cihazda simüle edilir.',
            },
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.muted, fontSize: 12),
          ),
          if (live != null) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                key: const ValueKey('league-leave'),
                onPressed: () => _confirmLeave(context),
                child: Text('Ligden ayrıl', style: TextStyle(color: Brand.muted)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmLeave(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ligden ayrıl'),
        content: const Text(
          'Satırın bu haftanın tablosundan kaldırılır; adın ve fotoğrafın artık görünmez. '
          'Ligin korunur, istediğin zaman yeniden katılabilirsin.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ayrıl')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(leagueApiProvider)?.leave();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Bağlantı kurulamadı. Biraz sonra yeniden dene.')));
      }
    }
  }
}

String _zoneText(int tier, ({int promote, int demote}) z) {
  final up = tier + 1 < leagueTiers.length ? leagueTiers[tier + 1].name : null;
  final down = tier > 0 ? leagueTiers[tier - 1].name : null;
  return switch ((z.promote > 0 && up != null, z.demote > 0 && down != null)) {
    (true, false) => 'İlk ${z.promote} kişi $up Ligine yükselir',
    (true, true) => 'İlk ${z.promote} kişi $up Ligine yükselir, son ${z.demote} kişi $down Ligine geçer',
    (false, true) => 'En üst lig! Son ${z.demote} kişi $down Ligine geçer',
    (false, false) => 'Hafta sonunda sıralama kaydedilir',
  };
}

/// Time left in the league week, refreshed every minute.
class _Countdown extends ConsumerStatefulWidget {
  const _Countdown({required this.serverWeek});

  /// The Dünya Ligi week ends Monday 00:00 Turkish time everywhere.
  final bool serverWeek;

  @override
  ConsumerState<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends ConsumerState<_Countdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    final left = widget.serverWeek ? untilTrWeekEnd(now) : untilWeekEnd(now);
    return Row(
      children: [
        Icon(Icons.timer_outlined, size: 16, color: Colors.white.withValues(alpha: 0.9)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Hafta bitimine ${formatLeft(left)}',
            key: const ValueKey('league-countdown'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
          ),
        ),
      ],
    );
  }
}

class _TierStrip extends StatelessWidget {
  const _TierStrip({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (var i = 0; i < leagueTiers.length; i++)
          Tooltip(
            message: '${leagueTiers[i].name} Ligi',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Opacity(
                opacity: i <= current ? 1 : 0.3,
                child: Glyph(
                  emoji: leagueTiers[i].emoji,
                  icon: Icons.military_tech_rounded,
                  size: i == current ? 34 : 24,
                  color: leagueTiers[i].color,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _ZoneLine extends StatelessWidget {
  const _ZoneLine(this.label, this.color);
  final String label;

  /// Null: the theme's success colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Brand.success;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: c, thickness: 2)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1),
            ),
          ),
          Expanded(child: Divider(color: c, thickness: 2)),
        ],
      ),
    );
  }
}

/// A guest sees the preview and is asked to sign in to join.
class _GuestCard extends ConsumerWidget {
  const _GuestCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(accountServiceProvider);
    return _InfoCard(
      emoji: '🌍',
      title: 'Dünya Ligi',
      text:
          'Her hafta farklı ülkelerden 100 kişilik bir grupta haftalık XP ile yarış. '
          'Katılmak için ücretsiz bir Dilmaç hesabıyla giriş yap (Google, e-posta ya da telefon).',
      action: service == null
          ? null
          : FilledButton.icon(
              key: const ValueKey('league-sign-in'),
              icon: const Icon(Icons.login_rounded),
              label: const Text('Giriş yap ve katıl'),
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<bool>(builder: (_) => AuthScreen(service: service))),
            ),
    );
  }
}

/// First visit with an account: what others will see, then join.
class _JoinCard extends ConsumerStatefulWidget {
  const _JoinCard();

  @override
  ConsumerState<_JoinCard> createState() => _JoinCardState();
}

class _JoinCardState extends ConsumerState<_JoinCard> {
  bool _busy = false;
  String? _error;

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await joinWorldLeague(ref.read);
      // leagueState changes on the server; the screen follows it.
    } catch (_) {
      if (mounted) setState(() => _error = 'Bağlantı kurulamadı. Biraz sonra yeniden dene.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(myDisplayNameProvider);
    final photo = ref.watch(profileProvider.select((p) => p.photo));
    final flag = flagEmoji(ref.watch(leagueCountryProvider));
    return _InfoCard(
      emoji: '🌍',
      title: 'Dünya Ligi’ne katıl',
      text:
          'Her hafta farklı ülkelerden 100 kişilik bir grupta haftalık XP ile yarış. '
          'Herkes Bronz Ligi’nden başlar; ilk 15 kişi bir üst lige çıkar.',
      extra: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            PhotoAvatar(
              photo: photo,
              size: 40,
              fallback: CircleAvatar(
                radius: 20,
                backgroundColor: Brand.card,
                child: const Text('⭐', style: TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Gruptaki herkes adını ($name${flag.isEmpty ? '' : ' $flag'})'
                '${photo != null ? ', profil fotoğrafını' : ''} ve ülkeni görür. '
                'Ülkeni ve fotoğrafını Profil’den değiştirebilir, ligden istediğin zaman ayrılabilirsin.',
                key: const ValueKey('league-privacy'),
                style: TextStyle(color: Brand.muted, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
      action: FilledButton.icon(
        key: const ValueKey('league-join'),
        icon: _busy
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.emoji_events_rounded),
        label: const Text('Lige katıl'),
        onPressed: _busy ? null : _join,
      ),
      error: _error,
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.emoji,
    required this.title,
    required this.text,
    this.extra,
    this.action,
    this.error,
  });
  final String emoji;
  final String title;
  final String text;
  final Widget? extra;
  final Widget? action;
  final String? error;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Brand.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Brand.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(text),
        ?extra,
        if (action != null) ...[const SizedBox(height: 12), action!],
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            style: TextStyle(color: Brand.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    ),
  );
}

class _Row extends ConsumerWidget {
  const _Row({super.key, required this.rank, required this.entry, required this.tier, required this.size});
  final int rank;
  final LeagueEntry entry;
  final int tier;
  final int size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The user's own (fresher) photo and name; other members' thumbnails
    // as the server has them. No photos in Çocuk modu.
    final mine = entry.isUser && !Brand.isKid ? ref.watch(profileProvider) : null;
    final photo = Brand.isKid ? null : (mine?.photo ?? entry.photo);
    final chosen = mine?.name;
    final name = entry.isUser ? (chosen != null ? '$chosen (Sen)' : entry.name) : entry.name;
    final flag = Brand.isKid ? '' : flagEmoji(entry.country);
    final rankColor = inPromotionZone(tier, rank, size)
        ? Brand.success
        : inDemotionZone(tier, rank, size)
        ? _moveDownColor
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
            width: 36,
            child: Text(
              '$rank',
              style: TextStyle(color: rankColor, fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
          PhotoAvatar(
            key: entry.isUser ? const ValueKey('league-my-avatar') : null,
            photo: photo,
            size: 40,
            fallback: CircleAvatar(
              radius: 20,
              backgroundColor: Brand.surface,
              child: Text(entry.avatar, style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),
          if (flag.isNotEmpty) ...[
            Text(flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

/// Full-screen result shown once after a league week ends. A race, not a
/// verdict: moving down is just next week's league.
class LeagueResultScreen extends StatelessWidget {
  const LeagueResultScreen({super.key, required this.result});
  final LeagueResult result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final tier = leagueTiers[r.newTier.clamp(0, leagueTiers.length - 1)];
    final place = r.size != null ? '${r.size} kişi içinde ${r.rank}.' : '${r.rank}.';
    final (title, body) = r.promoted
        ? ('${tier.name} Ligine yükseldin!', 'Geçen haftayı $place sırada bitirdin. Yeni ligine hoş geldin!')
        : r.demoted
        ? (
            'Yeni hafta, yeni yarış',
            'Geçen haftayı $place sırada bitirdin. Bu hafta ${tier.name} Liginde yarışıyorsun; '
                'ilk ${leagueZones(r.newTier).promote} arasına girersen yeniden yükselirsin.',
          )
        : (
            '${tier.name} Liginde kaldın',
            'Geçen haftayı $place sırada bitirdin. Bu hafta yükselme bölgesine!',
          );
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: tier.color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Glyph(
                    emoji: tier.emoji,
                    icon: Icons.military_tech_rounded,
                    size: 88,
                    color: tier.color,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                title,
                key: const ValueKey('league-result-title'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Brand.muted),
              ),
              if (r.xp != null) ...[
                const SizedBox(height: 20),
                Center(
                  child: Chip(
                    avatar: const Icon(Icons.bolt_rounded),
                    label: Text('Bu hafta ${r.xp} XP', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
              const Spacer(),
              FilledButton(
                key: const ValueKey('league-result-ok'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Devam'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows [r] full screen once after a league week ends.
Future<void> showLeagueResult(BuildContext context, LeagueResult r) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => LeagueResultScreen(result: r)));
