import 'package:flutter/material.dart';

/// Screen transitions (see docs/arayuz-referans.md, "Geçişler").
///
/// * Full-screen flows (lesson, exam, story, result chain…) are pushed as
///   `fullscreenDialog` routes and rise from the bottom of the screen.
/// * Other pages use the platform's usual transition.
/// * With reduced motion (phone setting or "Animasyonları azalt") pages
///   appear without movement.
class DilbazPageTransitionsBuilder extends PageTransitionsBuilder {
  const DilbazPageTransitionsBuilder({this.fallback = const ZoomPageTransitionsBuilder()});

  /// Transition for ordinary pages.
  final PageTransitionsBuilder fallback;

  /// Curves of the bottom-up session sheet.
  static const riseCurve = Curves.easeOutCubic;
  static const fallCurve = Curves.easeInCubic;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    if (route.fullscreenDialog) {
      final position = CurvedAnimation(parent: animation, curve: riseCurve, reverseCurve: fallCurve);
      return SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(position),
        child: child,
      );
    }
    return fallback.buildTransitions(route, context, animation, secondaryAnimation, child);
  }
}

/// The incoming half of a Material "fade through": when [active] turns true
/// the child fades in from 0 and grows from 92 % to full size. Used for the
/// bottom tabs, so switching tabs is a soft cross-fade instead of a jump.
class FadeThroughIn extends StatefulWidget {
  const FadeThroughIn({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;

  static const duration = Duration(milliseconds: 260);

  @override
  State<FadeThroughIn> createState() => _FadeThroughInState();
}

class _FadeThroughInState extends State<FadeThroughIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: FadeThroughIn.duration, value: 1);

  @override
  void didUpdateWidget(FadeThroughIn old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !MediaQuery.disableAnimationsOf(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Material fade-through: the new page waits a moment (the old one has
    // faded), then fades in while scaling up.
    final fade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.3, 1, curve: Curves.easeOut),
    );
    final scale = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.3, 1, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(scale), child: widget.child),
    );
  }
}
