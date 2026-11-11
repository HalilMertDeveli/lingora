import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';
import '../data/course_repository.dart';
import '../data/progress.dart';
import '../nav/nav_target.dart';
import '../nav/tab_navigator.dart';
import '../nav/top_bar.dart';
import '../org/org_widgets.dart';
import '../services/notifications.dart';
import 'exam_screen.dart';
import 'league_screen.dart';
import 'notes_screen.dart';
import 'path_screen.dart';
import 'practice_hub_screen.dart';
import 'profile_screen.dart';
import 'quests_screen.dart';
import 'vocab/dev_scenario_screen.dart';
import 'vocab/vocab_home_screen.dart';

export '../nav/top_bar.dart' show StatsBar, showTrackPicker, trackIcon;

/// The tab shell. Rules (see also [TabNavigator]):
///
/// 1. Tabs depend on the track kind ([tabsFor]); changing the track resets
///    every tab's pages and opens the first tab.
/// 2. Each tab has its own navigator: inner pages keep the bottom bar and
///    are kept when switching tabs.
/// 3. Full-screen flows go to the root navigator and hide the bottom bar.
/// 4. Back: pop the tab's page; at a tab root go to the first tab; at the
///    first tab's root leave the app.
/// 5. Tapping the selected tab pops it to its root; at the root it scrolls
///    to the top (or to the current node on the path).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late String _trackId;
  late List<AppTab> _tabs;
  int _index = 0;

  /// Bumped on a track change so every tab navigator starts over.
  int _generation = 0;
  final _navigators = <AppTab, GlobalKey<TabNavigatorState>>{};
  final _reselected = <AppTab, ValueNotifier<int>>{};

  /// Tabs are built the first time they are opened.
  final _opened = <AppTab>{};

  @override
  void initState() {
    super.initState();
    _reset(ref.read(trackProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) => _settleLeague());
    // Keep scheduled reminders in sync with progress (e.g. skip today's
    // reminder once a lesson is done).
    ref.listenManual<Progress>(
      progressProvider,
      (_, next) =>
          ref.read(notificationServiceProvider).apply(planNotifications(next, ref.read(clockProvider)())),
      fireImmediately: true,
    );
    ref.listenManual<Track>(trackProvider, (_, next) {
      if (next.id != _trackId) setState(() => _reset(next));
    });
    ref.listenManual<NavTarget?>(pendingNavTargetProvider, (_, target) {
      if (target != null) WidgetsBinding.instance.addPostFrameCallback((_) => _open(target));
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    for (final n in _reselected.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _reset(Track track) {
    _trackId = track.id;
    _tabs = tabsFor(track.kind);
    _index = 0;
    _generation++;
    _navigators.clear();
    _opened
      ..clear()
      ..add(_tabs.first);
  }

  GlobalKey<TabNavigatorState> _keyOf(AppTab tab) => _navigators.putIfAbsent(
    tab,
    () => GlobalKey<TabNavigatorState>(debugLabel: '${tab.name}#$_generation'),
  );

  ValueNotifier<int> _reselectOf(AppTab tab) => _reselected.putIfAbsent(tab, () => ValueNotifier(0));

  TabNavigatorState? get _currentNavigator => _navigators[_tabs[_index]]?.currentState;

  /// Closes last week's league (if a new week started) and shows the result.
  Future<void> _settleLeague() async {
    final notifier = ref.read(progressProvider.notifier)..settleLeague();
    final result = ref.read(progressProvider).leagueResult;
    if (result == null || !mounted) return;
    await showLeagueResult(context, result);
    notifier.dismissLeagueResult();
  }

  void _select(int i) {
    if (i == _index) {
      final nav = _currentNavigator;
      if (nav != null && nav.canPop()) {
        nav.popToRoot();
      } else {
        _reselectOf(_tabs[i]).value++;
      }
      return;
    }
    setState(() {
      _index = i;
      _opened.add(_tabs[i]);
    });
  }

  /// Android back, rule 4.
  void _back() {
    final nav = _currentNavigator;
    if (nav != null && nav.canPop()) {
      nav.maybePop();
    } else if (_index != 0) {
      setState(() => _index = 0);
    } else {
      SystemNavigator.pop();
    }
  }

  /// Opens [target] (from a notification): closes full-screen flows, then
  /// shows the tab at its root. Tabs the track lacks open the first tab.
  void _open(NavTarget target) {
    ref.read(pendingNavTargetProvider.notifier).consume();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    final i = _tabs.indexOf(target.tab);
    final index = i < 0 ? 0 : i;
    _navigators[_tabs[index]]?.currentState?.popToRoot();
    setState(() {
      _index = index;
      _opened.add(_tabs[index]);
    });
  }

  Widget _root(AppTab tab) => switch (tab) {
    AppTab.learn => const _LearnRoot(),
    AppTab.practice => const PracticeHubScreen(),
    AppTab.league => const ScrollToTopOnReselect(child: LeagueScreen()),
    AppTab.quests => const ScrollToTopOnReselect(child: QuestsScreen()),
    AppTab.profile => const ScrollToTopOnReselect(child: ProfileScreen()),
    AppTab.discover => const VocabDiscoverTab(),
    AppTab.review => const VocabReviewTab(),
    AppTab.map => const VocabMapTab(),
    AppTab.scenarios => const ScrollToTopOnReselect(child: DevScenarioList()),
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            for (final (i, tab) in _tabs.indexed)
              if (_opened.contains(tab))
                TickerMode(
                  enabled: i == _index,
                  child: TabScope(
                    reselected: _reselectOf(tab),
                    child: TabNavigator(
                      key: _keyOf(tab),
                      root: (_) => Scaffold(appBar: const LingoraTopBar(), body: _root(tab)),
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          key: const Key('bottom-nav'),
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [for (final tab in _tabs) _destination(tab)],
        ),
      ),
    );
  }

  NavigationDestination _destination(AppTab tab) {
    final (IconData icon, IconData selected) = switch (tab) {
      AppTab.learn => (Icons.route_outlined, Icons.route),
      AppTab.practice => (Icons.fitness_center_outlined, Icons.fitness_center),
      AppTab.league => (Icons.emoji_events_outlined, Icons.emoji_events),
      AppTab.quests => (Icons.task_alt_outlined, Icons.task_alt),
      AppTab.profile => (Icons.person_outline, Icons.person),
      AppTab.discover => (Icons.style_outlined, Icons.style),
      AppTab.review => (Icons.replay_outlined, Icons.replay),
      AppTab.map => (Icons.grid_view_outlined, Icons.grid_view_rounded),
      AppTab.scenarios => (Icons.forum_outlined, Icons.forum),
    };
    final badge = switch (tab) {
      AppTab.quests => ref.watch(claimableQuestsProvider),
      AppTab.review => ref.watch(vocabDueProvider),
      _ => 0,
    };
    Widget withBadge(IconData i) => Badge(
      key: badge > 0 ? Key('badge-${tab.name}') : null,
      isLabelVisible: badge > 0,
      label: Text('$badge'),
      child: Icon(i),
    );
    return NavigationDestination(
      key: Key('tab-${tab.name}'),
      icon: withBadge(icon),
      selectedIcon: withBadge(selected),
      label: tab.label,
    );
  }
}

/// "Öğren" tab root: the track's home (path, exam, notes) under the
/// Lingora Kurumsal assignments card.
class _LearnRoot extends ConsumerWidget {
  const _LearnRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(trackProvider);
    return Column(
      children: [
        // Lingora Kurumsal: shrinks to nothing without assignments.
        const OrgAssignmentsCard(),
        Expanded(
          child: switch (track.kind) {
            TrackKind.exam => ScrollToTopOnReselect(
              child: ExamHomeScreen(key: ValueKey(track.id), examId: track.id),
            ),
            TrackKind.notes => const ScrollToTopOnReselect(child: NotesHomeScreen()),
            // Vocabulary tracks have their own tabs; kept for exhaustiveness.
            TrackKind.vocab => const VocabDiscoverTab(),
            TrackKind.course => const PathScreen(),
          },
        ),
      ],
    );
  }
}
