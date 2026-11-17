import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';
import '../data/course_shelf.dart';
import '../data/progress.dart';
import '../models/course.dart';
import '../nav/nav_target.dart';
import '../nav/top_bar.dart' show trackIcon;
import '../services/growth/analytics.dart';
import '../theme.dart';
import '../ui/flag.dart';
import '../ui/mascot.dart';

/// "Kurslarım": every course on one calm, full screen. The course being
/// studied sits on top as a big card; the other courses the learner follows
/// come next, each with its progress and a "Devam et" button; at the bottom
/// the courses they can still add, each with a short preview before
/// "Bu kursa başla".
///
/// Opened from the course badge on the top bar. Picking another course
/// closes the screen and plays a short curtain in that course's colour while
/// the path behind it switches.
Future<void> openMyCourses(BuildContext context, WidgetRef ref) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  ref.read(courseShelfProvider.notifier).hintDone();
  // The root navigator: full screen, over the bottom bar.
  final picked = await Navigator.of(context, rootNavigator: true).push<_Pick>(
    PageRouteBuilder(
      settings: const RouteSettings(name: 'kurslarim'),
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => const MyCoursesScreen(),
      transitionsBuilder: (context, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
  if (picked == null) return;
  final current = ref.read(progressProvider).trackId;
  if (picked.id == current) return;
  final track = trackById(picked.id);
  ref.read(courseShelfProvider.notifier).keep(current);
  if (picked.added) {
    ref.read(courseShelfProvider.notifier).add(picked.id);
  } else {
    ref.read(progressProvider.notifier).setTrack(picked.id);
  }
  logEvent(ref, AnalyticsEvent.trackChosen(picked.id, source: picked.added ? 'shelf_add' : 'shelf'));
  showCourseCurtain(overlay, track);
}

/// The learner's choice on the shelf.
typedef _Pick = ({String id, bool added});

class MyCoursesScreen extends ConsumerWidget {
  const MyCoursesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final progress = ref.watch(progressProvider);
    final shelf = ref.watch(courseShelfProvider);
    final now = ref.watch(clockProvider)();
    final current = progress.trackId;

    final stats = <String, TrackStats>{};
    for (final t in allTracks) {
      if (pathCourseId(t) == null) continue;
      final outline = ref.watch(trackOutlineProvider(t.id)).value;
      if (outline != null) stats[t.id] = trackStats(outline, progress);
    }
    final followed = followedTrackIds(
      current: current,
      shelf: shelf,
      withProgress: {
        for (final e in stats.entries)
          if (e.value.done > 0) e.key,
      },
    );
    final others = followed.skip(1).map(trackById).toList();
    final more = allTracks.where((t) => !followed.contains(t.id)).toList();

    void pick(Track t, {bool added = false}) => Navigator.of(context).pop<_Pick>((id: t.id, added: added));

    Widget card(Track t) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _FollowedCard(
        track: t,
        stats: stats[t.id],
        lastStudied: lastStudiedLabel(shelf.lastStudied[t.id], now),
        onContinue: () => pick(t),
      ),
    );

    return Scaffold(
      key: const Key('courses-screen'),
      backgroundColor: p.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header(onClose: () => Navigator.of(context).pop())),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              sliver: SliverList.list(
                children: [
                  const _Label('ŞU AN ÇALIŞTIĞIN'),
                  _CurrentCard(
                    track: trackById(current),
                    stats: stats[current],
                    lastStudied: lastStudiedLabel(shelf.lastStudied[current], now),
                    onContinue: () {
                      final kind = trackById(current).kind;
                      Navigator.of(context).pop();
                      ref.read(pendingNavTargetProvider.notifier).open(NavTarget(tabsFor(kind).first));
                    },
                  ),
                  if (trackById(current).kind == TrackKind.course) ...[
                    const SizedBox(height: 10),
                    const AccentPicker(),
                  ],
                  if (others.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const _Label('DEVAM ETTİĞİN KURSLAR'),
                    for (final t in others) card(t),
                  ],
                  if (more.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const _Label('YENİ BİR KURS EKLE'),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Bir kursa dokun, içinde neler olduğuna bak. İlerlemen her kursta ayrı saklanır.',
                        style: TextStyle(color: p.muted, fontSize: 13),
                      ),
                    ),
                    for (final t in more)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AddCard(
                          track: t,
                          onTap: () async {
                            final start = await showCoursePreview(context, t);
                            if (start == true && context.mounted) pick(t, added: true);
                          },
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            key: const Key('courses-close'),
            tooltip: 'Kapat',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('Kurslarım', style: Theme.of(context).textTheme.headlineSmall),
                ),
                Text('Hangi kursla devam etmek istersin?', style: TextStyle(color: p.muted)),
              ],
            ),
          ),
          // Çocuk modu: Pofuduk waves. Adults see nothing here (decorative).
          const Mascot(mood: Mood.wave, size: 64, decorative: true),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 2),
    child: Semantics(header: true, child: SectionLabel(text)),
  );
}

/// The colour a track is drawn in for the current mode and brightness.
Color courseColor(BuildContext context, Track t) => context.palette.tone(courseLook(t).color);

/// A track's picture: its flag, or its icon on a tile of its colour (an
/// emoji in Çocuk modu).
class CourseTile extends StatelessWidget {
  const CourseTile(this.track, {super.key, this.size = 44, this.onHero = false});
  final Track track;
  final double size;

  /// Drawn on a coloured hero: a light tile instead of a coloured one.
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final c = courseColor(context, track);
    final radius = BorderRadius.circular(size * (context.isKid ? 0.5 : 0.3));
    final Widget inner;
    if (context.isKid) {
      inner = Text(track.emoji, style: TextStyle(fontSize: size * 0.56));
    } else if (track.flag != null) {
      inner = FlagIcon(track.flag!, width: size * 0.62);
    } else {
      inner = Icon(trackIcon(track), color: onHero ? c : Colors.white, size: size * 0.54);
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: onHero ? Colors.white : null,
        gradient: onHero
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(c, Colors.white, 0.18)!, c],
              ),
      ),
      child: inner,
    );
  }
}

/// Whole percent: at least %1 once a step is done, %100 only when all are.
String _percent(TrackStats s) {
  if (s.done == 0) return '%0';
  if (s.done >= s.total) return '%100';
  return '%${(statsFraction(s) * 100).round().clamp(1, 99)}';
}

/// One line on a track's progress for cards and screen readers.
String progressLine(Track t, TrackStats? s) {
  if (pathCourseId(t) == null) return 'Kendi hızında çalış';
  if (s == null) return 'Hazırlanıyor…';
  if (s.done == 0) return 'Henüz başlamadın · ${s.total} adım';
  return '${_percent(s)} tamamlandı · ${s.done}/${s.total} adım';
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.color, this.background});
  final String text;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: background ?? color.withValues(alpha: context.palette.isDark ? 0.2 : 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800),
    ),
  );
}

/// The course being studied: a big card in its own colour.
class _CurrentCard extends StatelessWidget {
  const _CurrentCard({
    required this.track,
    required this.stats,
    required this.lastStudied,
    required this.onContinue,
  });
  final Track track;
  final TrackStats? stats;
  final String lastStudied;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final lt = context.lingora;
    final look = courseLook(track);
    final deco = lt.hero(look.color, from: Color.lerp(look.color, Colors.white, 0.2));
    final bg = deco.color ?? look.color;
    final s = stats;
    final hasPath = pathCourseId(track) != null;
    return Semantics(
      container: true,
      label: 'Şu an çalıştığın kurs: ${track.title}. ${progressLine(track, s)}. $lastStudied.',
      child: Container(
        key: const Key('course-current'),
        decoration: deco.copyWith(
          boxShadow: [
            BoxShadow(color: bg.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8)),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CourseTile(track, size: 52, onHero: true),
                const SizedBox(width: 12),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          look.forWhom,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 13.5),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const ExcludeSemantics(
                  child: Icon(Icons.check_circle_rounded, color: Colors.white, size: 26),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ExcludeSemantics(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (look.level.isNotEmpty)
                    _Chip(look.level, color: Colors.white, background: Colors.white.withValues(alpha: 0.18)),
                  if (track.badge != null)
                    _Chip(
                      track.badge!,
                      color: Colors.white,
                      background: Colors.white.withValues(alpha: 0.18),
                    ),
                ],
              ),
            ),
            if (hasPath) ...[
              const SizedBox(height: 14),
              ExcludeSemantics(child: _HeroBar(value: s == null ? 0 : statsFraction(s))),
            ],
            const SizedBox(height: 8),
            ExcludeSemantics(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      progressLine(track, s),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  Text(
                    lastStudied,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: Key('course-continue-${track.id}'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: bg,
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(lt.buttonRadius)),
                ),
                onPressed: onContinue,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Devam et'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBar extends StatelessWidget {
  const _HeroBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.clamp(0.0, 1.0)),
    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 500),
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => Container(
      height: 10,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: v == 0 ? 0.02 : v,
        heightFactor: 1,
        child: const DecoratedBox(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(10))),
        ),
      ),
    ),
  );
}

/// Another course the learner follows: progress, last study and "Devam et".
class _FollowedCard extends StatelessWidget {
  const _FollowedCard({
    required this.track,
    required this.stats,
    required this.lastStudied,
    required this.onContinue,
  });
  final Track track;
  final TrackStats? stats;
  final String lastStudied;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = courseColor(context, track);
    final look = courseLook(track);
    final s = stats;
    return Semantics(
      container: true,
      button: true,
      label: '${track.title}. ${progressLine(track, s)}. $lastStudied. Bu kursa geçmek için dokun.',
      excludeSemantics: true,
      child: TapCard(
        key: Key('course-card-${track.id}'),
        onTap: onContinue,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CourseTile(track),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        look.forWhom,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (pathCourseId(track) != null) ...[
              _Bar(value: s == null ? 0 : statsFraction(s), color: c),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        progressLine(track, s),
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.ink),
                      ),
                      Text(lastStudied, style: TextStyle(color: p.muted, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  key: Key('course-continue-${track.id}'),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.withValues(alpha: p.isDark ? 0.24 : 0.12),
                    foregroundColor: c,
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    minimumSize: const Size(48, 44),
                  ),
                  onPressed: onContinue,
                  child: Text(s != null && s.done == 0 ? 'Başla' : 'Devam et'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 8,
      decoration: BoxDecoration(color: p.isDark ? p.surface : p.line, borderRadius: BorderRadius.circular(8)),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

/// A course not on the shelf yet: tap for its preview.
class _AddCard extends StatelessWidget {
  const _AddCard({required this.track, required this.onTap});
  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = courseColor(context, track);
    final look = courseLook(track);
    return Semantics(
      button: true,
      label: '${track.title}. ${look.forWhom} Önizlemek için dokun.',
      excludeSemantics: true,
      child: TapCard(
        key: Key('course-add-${track.id}'),
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        child: Row(
          children: [
            CourseTile(track, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          track.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      if (track.badge != null) ...[const SizedBox(width: 6), _Chip(track.badge!, color: c)],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    look.forWhom,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.withValues(alpha: p.isDark ? 0.22 : 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add_rounded, color: c),
            ),
          ],
        ),
      ),
    );
  }
}

/// What is inside [outline]: its section titles (or unit titles for a
/// one-section course), at most four.
List<String> courseHighlights(Course outline) {
  final sections = outline.sections.where((s) => !s.implicit).map((s) => s.title).toList();
  final titles = sections.length >= 2 ? sections : outline.units.map((u) => u.title).toList();
  return titles.take(4).toList();
}

/// Preview of a course before it is added: who it is for, its level and
/// what is inside. Resolves to true when the learner taps "Bu kursa başla".
Future<bool?> showCoursePreview(BuildContext context, Track track) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: context.palette.card,
  builder: (_) => _Preview(track: track),
);

class _Preview extends ConsumerWidget {
  const _Preview({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final lt = context.lingora;
    final look = courseLook(track);
    final c = courseColor(context, track);
    final outline = pathCourseId(track) == null ? null : ref.watch(trackOutlineProvider(track.id));
    final course = outline?.value;
    final items = course != null ? courseHighlights(course) : look.highlights;
    final steps = course?.allNodes.length;
    return SingleChildScrollView(
      key: const Key('course-preview'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CourseTile(track, size: 60),
              const SizedBox(width: 14),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(track.title, style: Theme.of(context).textTheme.headlineSmall),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(look.forWhom, style: TextStyle(fontSize: 15, color: p.ink)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (look.level.isNotEmpty) _Chip('Seviye: ${look.level}', color: c),
              if (steps != null) _Chip('$steps adım', color: c),
              if (track.badge != null) _Chip(track.badge!, color: c),
            ],
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionLabel('İÇİNDE NELER VAR'),
            const SizedBox(height: 8),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(child: Icon(Icons.check_circle_outline_rounded, color: c, size: 20)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item, style: const TextStyle(fontSize: 14.5))),
                  ],
                ),
              ),
          ] else if (outline != null && outline.isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Radii.md)),
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: p.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Şu anki kursundaki ilerlemen kaybolmaz; istediğin zaman geri dönebilirsin.',
                    style: TextStyle(color: p.muted, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('course-start'),
            style: FilledButton.styleFrom(
              backgroundColor: c,
              foregroundColor: onColor(c),
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(lt.buttonRadius)),
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(true);
            },
            icon: const Icon(Icons.rocket_launch_outlined),
            label: const Text('Bu kursa başla'),
          ),
          const SizedBox(height: 4),
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Vazgeç')),
        ],
      ),
    );
  }
}

/// A short curtain in [track]'s colour over the whole app while the path
/// behind it switches: the colour grows from the course badge, shows the
/// course for a moment and fades into its path. Skipped when the system
/// asks for less motion.
void showCourseCurtain(OverlayState overlay, Track track) {
  if (MediaQuery.maybeDisableAnimationsOf(overlay.context) ?? false) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Curtain(
      track: track,
      onDone: () {
        if (entry.mounted) entry.remove();
        entry.dispose();
      },
    ),
  );
  overlay.insert(entry);
}

class _Curtain extends StatefulWidget {
  const _Curtain({required this.track, required this.onDone});
  final Track track;
  final VoidCallback onDone;

  @override
  State<_Curtain> createState() => _CurtainState();
}

class _CurtainState extends State<_Curtain> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1150))
    ..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lingora;
    final look = courseLook(widget.track);
    final bg = lt.hero(look.color, from: Color.lerp(look.color, Colors.white, 0.2)).color ?? look.color;
    final size = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    final origin = Offset(80, top + kToolbarHeight / 2);
    final maxR = (size.bottomRight(Offset.zero) - origin).distance + 40;
    final grow = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 0.38, curve: Curves.easeInOutCubic),
    );
    final show = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.18, 0.45, curve: Curves.easeOutBack),
    );
    final fade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.72, 1, curve: Curves.easeIn),
    );
    return AbsorbPointer(
      key: const Key('course-curtain'),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Opacity(
          opacity: 1 - fade.value,
          child: ClipPath(
            clipper: _CircleClip(origin, maxR * grow.value),
            child: Container(
              color: bg,
              alignment: Alignment.center,
              child: Transform.scale(
                scale: 0.8 + 0.2 * show.value.clamp(0.0, 1.2) + 0.08 * fade.value,
                child: Opacity(
                  opacity: show.value.clamp(0.0, 1.0),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CourseTile(widget.track, size: 88, onHero: true),
                        const SizedBox(height: 16),
                        Text(
                          widget.track.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Yolun hazırlanıyor',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleClip extends CustomClipper<Path> {
  _CircleClip(this.center, this.radius);
  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) => Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_CircleClip old) => old.radius != radius || old.center != center;
}
