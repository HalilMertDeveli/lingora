import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';
import '../data/course_repository.dart';
import '../data/progress.dart';
import '../services/notifications.dart';
import '../theme.dart';
import 'conversation_screen.dart';
import 'exam_screen.dart';
import 'league_screen.dart';
import 'notes_screen.dart';
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
    // reminder once a lesson is done).
    ref.listenManual<Progress>(
      progressProvider,
      (_, next) =>
          ref.read(notificationServiceProvider).apply(planNotifications(next, ref.read(clockProvider)())),
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
    final track = ref.watch(trackProvider);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: const StatsBar(),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Brand.line),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          switch (track.kind) {
            TrackKind.exam => ExamHomeScreen(key: ValueKey(track.id), examId: track.id),
            TrackKind.notes => const NotesHomeScreen(),
            TrackKind.course => const PathScreen(),
          },
          const ConversationHomeScreen(),
          const QuestsScreen(),
          const LeagueScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Öğren',
          ),
          const NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: 'Konuş',
          ),
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
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'Lig',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

/// Track switcher plus streak and XP. There are no hearts: mistakes are
/// never punished in Lingora.
class StatsBar extends ConsumerWidget {
  const StatsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final now = ref.watch(clockProvider)();
    final track = ref.watch(trackProvider);
    return Row(
      children: [
        Flexible(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => showTrackPicker(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Glyph(emoji: track.emoji, icon: trackIcon(track), size: 24),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      track.title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, color: Brand.muted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _Stat(icon: Icons.local_fire_department, color: Brand.streak, value: p.streakAt(now)),
        const SizedBox(width: 14),
        _Stat(icon: Icons.bolt, color: Brand.xp, value: p.totalXp),
      ],
    );
  }
}

Future<void> showTrackPicker(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => const _TrackPicker(),
);

class _TrackPicker extends ConsumerWidget {
  const _TrackPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(trackProvider).id;
    Widget tile(Track t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TapCard(
        selected: t.id == current,
        onTap: () {
          ref.read(progressProvider.notifier).setTrack(t.id);
          Navigator.pop(context);
        },
        child: Row(
          children: [
            IconBadge(icon: trackIcon(t), emoji: t.emoji, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, style: Theme.of(context).textTheme.titleMedium),
                  Text(t.subtitle, style: TextStyle(color: Brand.muted, fontSize: 13)),
                ],
              ),
            ),
            if (t.badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Brand.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  t.badge!,
                  style: TextStyle(color: Brand.primary, fontSize: 10, fontWeight: FontWeight.w900),
                ),
              ),
          ],
        ),
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ne çalışmak istersin?', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('İlerlemen her kursta ayrı saklanır.', style: TextStyle(color: Brand.muted)),
            const SizedBox(height: 14),
            const _SectionLabel('KURSLAR'),
            for (final t in courseCatalog) tile(t),
            const SizedBox(height: 8),
            const _SectionLabel('SINAVLARA HAZIRLIK'),
            for (final t in examCatalog) tile(t),
            const SizedBox(height: 8),
            const _SectionLabel('KENDİ NOTLARIN'),
            tile(notesTrack),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: SectionLabel(text));
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
      Text(
        '$value',
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ],
  );
}

/// Material icon for a track, used instead of its emoji in adult mode.
IconData trackIcon(Track t) => switch (t.id) {
  'pro_tourism' => Icons.hotel_outlined,
  'pro_interview' => Icons.work_outline_rounded,
  'pro_software' => Icons.code_rounded,
  'yds' => Icons.school_outlined,
  'lgs' => Icons.edit_note_rounded,
  'notes' => Icons.sticky_note_2_outlined,
  // Not an exhaustive switch on kind, so new track kinds compile without edits.
  _ when t.kind == TrackKind.exam => Icons.assignment_outlined,
  _ when t.kind == TrackKind.notes => Icons.sticky_note_2_outlined,
  _ => Icons.translate_rounded,
};
