import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';
import '../data/course_repository.dart';
import '../data/progress.dart';
import '../services/growth/analytics.dart';
import '../theme.dart';
import '../ui/flag.dart';
import 'nav_target.dart';

/// Top bar of every tab root: the track button on the left (opens the track
/// drawer), streak and XP on the right (each opens its own panel). There are
/// no hearts: mistakes are never punished in Dilbaz.
class LingoraTopBar extends StatelessWidget implements PreferredSizeWidget {
  const LingoraTopBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) => AppBar(
    automaticallyImplyLeading: false,
    titleSpacing: 12,
    title: const StatsBar(),
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Divider(height: 1, color: Brand.line),
    ),
  );
}

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
            key: const Key('topbar-track'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => showTrackPicker(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (track.flag != null)
                    FlagIcon(track.flag!, width: 26)
                  else
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
        const SizedBox(width: 4),
        _Stat(
          key: const Key('topbar-streak'),
          icon: Icons.local_fire_department,
          color: Brand.streak,
          value: p.streakAt(now),
          tooltip: 'Seri',
          onTap: () => showTopPanel(context, const StreakPanel()),
        ),
        _Stat(
          key: const Key('topbar-xp'),
          icon: Icons.bolt,
          color: Brand.xp,
          value: p.totalXp,
          tooltip: 'XP',
          onTap: () => showTopPanel(context, const XpPanel()),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final int value;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 4),
            Text(
              '$value',
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Opens [panel] sliding down from under the top bar, over the whole app
/// (bottom bar included). Tapping outside or back closes it.
Future<void> showTopPanel(BuildContext context, Widget panel) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 220),
    // Measured in the dialog: the AppBar hides the status bar padding from its children.
    pageBuilder: (dialogContext, _, _) => Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(dialogContext).top + kToolbarHeight + 1),
        child: Material(
          color: Brand.background,
          elevation: 6,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), child: panel),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return ClipRect(
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -1), end: Offset.zero).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        ),
      );
    },
  );
}

/// The track drawer: pick what to study. Progress is kept per track.
Future<void> showTrackPicker(BuildContext context) => showTopPanel(context, const TrackDrawer());

class TrackDrawer extends ConsumerWidget {
  const TrackDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(trackProvider).id;
    Widget tile(Track t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TapCard(
        selected: t.id == current,
        onTap: () {
          if (t.id != current) {
            ref.read(progressProvider.notifier).setTrack(t.id);
            logEvent(ref, AnalyticsEvent.trackChosen(t.id, source: 'home'));
          }
          Navigator.pop(context);
        },
        child: Row(
          children: [
            if (t.flag != null)
              SizedBox(width: 40, height: 40, child: Center(child: FlagIcon(t.flag!, width: 36)))
            else
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

    return Column(
      key: const Key('track-drawer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Ne çalışmak istersin?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('İlerlemen her kursta ayrı saklanır.', style: TextStyle(color: Brand.muted)),
        const SizedBox(height: 14),
        const _SectionLabel('KURSLAR'),
        for (final t in courseCatalog) tile(t),
        for (final t in vocabCatalog) tile(t),
        const SizedBox(height: 8),
        const _SectionLabel('SINAVLARA HAZIRLIK'),
        for (final t in examCatalog) tile(t),
        const SizedBox(height: 8),
        const _SectionLabel('KENDİ NOTLARIN'),
        tile(notesTrack),
      ],
    );
  }
}

const _weekdayInitials = ['Pt', 'Sa', 'Ça', 'Pe', 'Cu', 'Ct', 'Pz'];
const _months = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// Streak panel: the current streak and this month's calendar of active days.
class StreakPanel extends ConsumerWidget {
  const StreakPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final now = ref.watch(clockProvider)();
    final streak = p.streakAt(now);
    final doneToday = p.xpOn(now) > 0;
    final first = DateTime(now.year, now.month);
    final days = DateTime(now.year, now.month + 1, 0).day;
    final lead = first.weekday - 1; // Monday first
    final active = [for (var d = 1; d <= days; d++) p.xpOn(DateTime(now.year, now.month, d)) > 0];

    return Column(
      key: const Key('streak-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.local_fire_department, color: Brand.streak, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    streak == 0 ? 'Seri yok' : '$streak günlük seri',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    doneToday
                        ? 'Bugünkü dersin tamam. Yarın görüşürüz!'
                        : streak == 0
                        ? 'Bugün bir ders yap, serin başlasın.'
                        : 'Bugün bir ders yaparsan serin devam eder.',
                    style: TextStyle(color: Brand.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text('${_months[now.month - 1]} ${now.year}', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          primary: false,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: [
            for (final w in _weekdayInitials)
              Center(
                child: Text(
                  w,
                  style: TextStyle(color: Brand.muted, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (var d = 1; d <= days; d++)
              Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active[d - 1] ? Brand.streak : null,
                  border: d == now.day ? Border.all(color: Brand.streak, width: 2) : null,
                ),
                child: Text(
                  '$d',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active[d - 1] ? onColor(Brand.streak) : null,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Kaçırılan gün ceza değildir; seri sadece yeniden başlar.',
          style: TextStyle(color: Brand.muted, fontSize: 12),
        ),
      ],
    );
  }
}

/// XP panel: total, today against the daily goal and the last seven days.
class XpPanel extends ConsumerWidget {
  const XpPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final now = ref.watch(clockProvider)();
    final today = p.xpOn(now);
    final week = [for (var i = 6; i >= 0; i--) DateTime(now.year, now.month, now.day - i)];
    final weekXp = week.fold<int>(0, (s, d) => s + p.xpOn(d));
    final maxXp = week.map(p.xpOn).fold<int>(p.dailyGoal, (a, b) => a > b ? a : b);
    final hasLeague = tabsFor(ref.watch(trackProvider).kind).contains(AppTab.league);

    return Column(
      key: const Key('xp-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.bolt, color: Brand.xp, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${p.totalXp} XP', style: Theme.of(context).textTheme.titleLarge),
                  Text('Son 7 günde $weekXp XP', style: TextStyle(color: Brand.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text('Bugün: $today / ${p.dailyGoal} XP', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (today / p.dailyGoal).clamp(0.0, 1.0),
            minHeight: 10,
            color: today >= p.dailyGoal ? Brand.success : Brand.xp,
            backgroundColor: Brand.line,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in week)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        height: 4 + 50 * p.xpOn(d) / maxXp,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: p.xpOn(d) > 0 ? Brand.xp : Brand.line,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _weekdayInitials[d.weekday - 1],
                        style: TextStyle(fontSize: 11, color: Brand.muted),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (hasLeague) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                ref.read(pendingNavTargetProvider.notifier).open(const NavTarget(AppTab.league));
              },
              icon: const Icon(Icons.emoji_events_outlined, size: 18),
              label: const Text('Ligdeki sırana bak'),
            ),
          ),
        ],
      ],
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
