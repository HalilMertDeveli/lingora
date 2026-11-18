import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/course_repository.dart';
import '../data/course_shelf.dart';
import '../data/progress.dart';
import '../screens/my_courses_screen.dart';
import '../theme.dart';
import '../ui/first_tour.dart';

/// The course badge on the left of the top bar: the course being studied
/// (its picture, "KURSUN" and a short name) with a switch icon. Tapping it
/// opens "Kurslarım" ([openMyCourses]).
///
/// On first start, and once after each course added from the shelf, a small
/// bubble under the badge says where courses are changed. It goes away by
/// itself, on a tap, or when the badge is used.
class CourseBadge extends ConsumerStatefulWidget {
  const CourseBadge({super.key});

  /// How long the hint bubble stays.
  static const hintDuration = Duration(seconds: 6);

  @override
  ConsumerState<CourseBadge> createState() => _CourseBadgeState();
}

class _CourseBadgeState extends ConsumerState<CourseBadge> with SingleTickerProviderStateMixin {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  late final _hint = AnimationController(vsync: this, duration: CourseBadge.hintDuration);

  @override
  void initState() {
    super.initState();
    _hint.addStatusListener((s) {
      if (s == AnimationStatus.completed) ref.read(courseHintProvider.notifier).hide();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeArm());
  }

  @override
  void dispose() {
    _hint.dispose();
    super.dispose();
  }

  /// Every tab has its own top bar; only the one on screen (its tickers
  /// on) starts the hint.
  bool get _onScreen => mounted && TickerMode.valuesOf(context).enabled;

  void _maybeArm() {
    if (!_onScreen || _tourPending(ref)) return;
    showCourseHintIfArmed(ref);
  }

  /// Keeps the bubble in step with [courseHintProvider]. A badge rebuilt
  /// while the hint is up (a tab or course change) picks it up again.
  void _sync(bool visible) {
    if (!mounted) return;
    if (visible && _onScreen) {
      if (!_portal.isShowing) {
        _portal.show();
        _hint.forward(from: 0);
      }
    } else if (_portal.isShowing) {
      _hint.stop();
      _portal.hide();
    }
  }

  void _hideHint() {
    ref.read(courseHintProvider.notifier).hide();
    _sync(false);
  }

  @override
  Widget build(BuildContext context) {
    // A course added on the shelf arms the hint again.
    ref.listen(courseShelfProvider.select((s) => s.hintArmed), (_, armed) {
      if (armed) WidgetsBinding.instance.addPostFrameCallback((_) => _maybeArm());
    });
    final visible = ref.watch(courseHintProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(visible));
    final p = context.palette;
    final track = ref.watch(trackProvider);
    final look = courseLook(track);
    final c = courseColor(context, track);
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => _HintBubble(link: _link, animation: _hint, onTap: _hideHint),
        child: Semantics(
          button: true,
          label: 'Kursun: ${track.title}. Kurslarını görmek ve değiştirmek için dokun.',
          excludeSemantics: true,
          child: Tooltip(
            message: 'Kurslarım',
            excludeFromSemantics: true,
            child: InkWell(
              key: const Key('topbar-track'),
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                _hideHint();
                openMyCourses(context, ref);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: p.isDark ? 0.18 : 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.withValues(alpha: p.isDark ? 0.45 : 0.3)),
                ),
                // Largest font on a narrow phone: the counters leave too
                // little room, so only the course picture stays (the
                // semantics label still names the course).
                child: LayoutBuilder(
                  builder: (context, box) => box.maxWidth < 96
                      ? CourseTile(track, size: 30)
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CourseTile(track, size: 30),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'KURSUN',
                                    // One line: wrapping overflowed the top bar with the
                                    // largest font on a narrow phone.
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      color: c,
                                      fontSize: 9.5,
                                      height: 1.1,
                                      letterSpacing: 0.8,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    look.short,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: p.ink,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(Icons.unfold_more_rounded, size: 20, color: c),
                          ],
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

/// Whether the badge hint is up right now (not stored: the stored part is
/// [CourseShelf.hintArmed]).
class CourseHintNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void show() => state = true;
  void hide() => state = false;
}

/// Shows the badge hint if it is armed, and disarms it: shown once.
void showCourseHintIfArmed(WidgetRef ref) {
  if (!ref.read(courseShelfProvider).hintArmed) return;
  ref.read(courseShelfProvider.notifier).hintDone();
  ref.read(courseHintProvider.notifier).show();
}

/// The first-run tour is still to come: the hint waits for it to finish
/// (the home screen shows it then) so the two never overlap.
bool _tourPending(WidgetRef ref) => FirstTour.enabled && ref.read(prefsProvider).getBool(tourDoneKey) != true;

final courseHintProvider = NotifierProvider<CourseHintNotifier, bool>(CourseHintNotifier.new);

/// "Kursunu buradan değiştirebilirsin": a small dark bubble pointing at the
/// badge. Fades in, stays, fades out with [animation].
class _HintBubble extends StatelessWidget {
  const _HintBubble({required this.link, required this.animation, required this.onTap});
  final LayerLink link;
  final Animation<double> animation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = p.isDark ? const Color(0xFFF1F3F5) : const Color(0xFF1F2430);
    final fg = p.isDark ? const Color(0xFF1F2430) : Colors.white;
    final opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 6,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 86),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 8),
    ]).animate(animation);
    return CompositedTransformFollower(
      link: link,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, 6),
      child: Align(
        alignment: Alignment.topLeft,
        child: FadeTransition(
          opacity: opacity,
          child: Semantics(
            liveRegion: true,
            label: 'İpucu: Kursunu buradan değiştirebilirsin.',
            excludeSemantics: true,
            child: GestureDetector(
              key: const Key('course-hint'),
              onTap: onTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: CustomPaint(size: const Size(14, 7), painter: _Notch(bg)),
                  ),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_horiz_rounded, color: fg, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Kursunu buradan değiştirebilirsin',
                            // Not the app bar title's one-line ellipsis.
                            softWrap: true,
                            maxLines: 2,
                            overflow: TextOverflow.visible,
                            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.close_rounded, color: fg.withValues(alpha: 0.7), size: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notch extends CustomPainter {
  _Notch(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Notch old) => old.color != color;
}
