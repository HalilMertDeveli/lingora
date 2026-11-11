import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Dilbaz's navigation rules, in one place.
///
/// * Every bottom tab owns a [TabNavigator]. Pages pushed inside a tab keep
///   the bottom bar visible and survive switching tabs.
/// * Full-screen flows (lesson, exam, story, placement test, paywall…) are
///   pushed as `fullscreenDialog` routes. A [TabNavigator] forwards those to
///   the root navigator, so they cover the bottom bar whatever context
///   pushed them. Call sites keep using plain `Navigator.of(context).push`.
class TabNavigator extends Navigator {
  TabNavigator({super.key, super.observers, required this.root})
    : super(onGenerateRoute: (_) => _TabRootRoute<void>(builder: root));

  /// The tab's first page.
  final WidgetBuilder root;

  @override
  NavigatorState createState() => TabNavigatorState();
}

class TabNavigatorState extends NavigatorState {
  /// The app's root navigator (the one that holds the tab shell).
  NavigatorState get rootNavigator => Navigator.of(context, rootNavigator: true);

  @override
  Future<T?> push<T extends Object?>(Route<T> route) {
    if (route is PageRoute<T> && route.fullscreenDialog) return rootNavigator.push(route);
    return super.push(route);
  }

  /// Pops every page of this tab, back to its root.
  void popToRoot() => popUntil((r) => r.isFirst);
}

class _TabRootRoute<T> extends MaterialPageRoute<T> {
  _TabRootRoute({required super.builder});

  // The tab root appears instantly: switching tabs is not a page transition.
  @override
  Duration get transitionDuration => Duration.zero;
}

/// What a tab's root page can listen to: [reselected] ticks when the user
/// taps the already-selected tab while it is at its root (scroll to the top,
/// or to the current node on the path).
///
/// To react when a full-screen flow closes, a root page can watch
/// `TickerMode.valuesOf(context).enabled`: it is false while the tab is
/// hidden or covered.
class TabScope extends InheritedWidget {
  const TabScope({super.key, required this.reselected, required super.child});

  final ValueListenable<int> reselected;

  static TabScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TabScope>();

  @override
  bool updateShouldNotify(TabScope old) => old.reselected != reselected;
}

/// Scrolls a tab root's list back to the top when its tab is tapped again.
///
/// Wrap a tab root whose body is a primary vertical scroll view.
class ScrollToTopOnReselect extends StatefulWidget {
  const ScrollToTopOnReselect({super.key, required this.child});
  final Widget child;

  @override
  State<ScrollToTopOnReselect> createState() => _ScrollToTopOnReselectState();
}

class _ScrollToTopOnReselectState extends State<ScrollToTopOnReselect> {
  final _controller = ScrollController();
  ValueListenable<int>? _reselected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = TabScope.maybeOf(context)?.reselected;
    if (next == _reselected) return;
    _reselected?.removeListener(_toTop);
    _reselected = next?..addListener(_toTop);
  }

  void _toTop() {
    for (final p in _controller.positions) {
      p.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _reselected?.removeListener(_toTop);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PrimaryScrollController(controller: _controller, child: widget.child);
}
