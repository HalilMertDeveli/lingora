import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../services/notifications.dart';
import '../theme.dart';
import 'league_screen.dart';
import 'path_screen.dart';
import 'profile_screen.dart';
import 'quests_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _settleLeague());
    // Keep scheduled reminders in sync with progress (e.g. skip today's
    // reminder once a lesson is done, re-plan hearts-full alerts).
    ref.listenManual<Progress>(
      progressProvider,
      (_, next) => ref
          .read(notificationServiceProvider)
          .apply(planNotifications(next, ref.read(clockProvider)())),
      fireImmediately: true,
    );
  }

  /// Closes last week's league (if a new week started) and shows the result.
  Future<void> _settleLeague() async {
    final notifier = ref.read(progressProvider.notifier)..settleLeague();
    final result = ref.read(progressProvider).leagueResult;
    if (result == null || !mounted) return;
    await showLeagueResult(context, result);
    notifier.dismissLeagueResult();
  }

  @override
  Widget build(BuildContext context) {
    final claimable = ref.watch(claimableQuestsProvider);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const StatsBar(),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Brand.line),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: const [PathScreen(), QuestsScreen(), LeagueScreen(), ProfileScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Öğren'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: claimable > 0,
              label: Text('$claimable'),
              child: const Icon(Icons.task_alt_outlined),
            ),
            selectedIcon: const Icon(Icons.task_alt),
            label: 'Görevler',
          ),
          const NavigationDestination(
              icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Lig'),
          const NavigationDestination(
              icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

/// Streak, XP and hearts. Refreshes every 30 s so refilled hearts show up.
class StatsBar extends ConsumerStatefulWidget {
  const StatsBar({super.key});

  @override
  ConsumerState<StatsBar> createState() => _StatsBarState();
}

class _StatsBarState extends ConsumerState<StatsBar> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(progressProvider);
    final now = ref.watch(clockProvider)();
    return Row(
      children: [
        const Text('🇬🇧', style: TextStyle(fontSize: 24)),
        const Spacer(),
        _Stat(icon: Icons.local_fire_department, color: Brand.streak, value: p.streakAt(now)),
        const SizedBox(width: 18),
        _Stat(icon: Icons.bolt, color: Brand.xp, value: p.totalXp),
        const SizedBox(width: 18),
        _Stat(icon: Icons.favorite, color: Brand.heart, value: p.heartsAt(now)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.color, required this.value});
  final IconData icon;
  final Color color;
  final int value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 4),
          Text('$value', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
        ],
      );
}
