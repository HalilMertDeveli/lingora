import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';

/// Every bottom tab Lingora can show. Which five appear depends on the
/// track kind, see [tabsFor].
enum AppTab {
  learn('Öğren'),
  practice('Pratik'),
  league('Lig'),
  quests('Görevler'),
  profile('Profil'),
  // Yazılımcı İngilizcesi (vocab tracks).
  discover('Keşfet'),
  review('Tekrar'),
  map('Harita'),
  scenarios('Senaryolar');

  const AppTab(this.label);
  final String label;
}

/// Tabs for a track kind. The first one is "home": back from another tab's
/// root lands there, and a track change opens it.
List<AppTab> tabsFor(TrackKind kind) => kind == TrackKind.vocab
    ? const [AppTab.discover, AppTab.review, AppTab.map, AppTab.scenarios, AppTab.profile]
    : const [AppTab.learn, AppTab.practice, AppTab.league, AppTab.quests, AppTab.profile];

/// Where a notification tap (or another deep link) should take the user.
///
/// Payloads are plain strings so they survive the OS round trip:
/// `tab:<AppTab.name>`. A tab that the current track does not have falls
/// back to its home tab ("review" on a course track opens "Öğren").
class NavTarget {
  const NavTarget(this.tab);
  final AppTab tab;

  String get payload => 'tab:${tab.name}';

  static NavTarget? parse(String? payload) {
    if (payload == null || !payload.startsWith('tab:')) return null;
    final name = payload.substring(4);
    for (final t in AppTab.values) {
      if (t.name == name) return NavTarget(t);
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is NavTarget && other.tab == tab;

  @override
  int get hashCode => tab.hashCode;
}

/// A navigation request waiting for the tab shell (set by a notification
/// tap, consumed by the shell).
class PendingNavTarget extends Notifier<NavTarget?> {
  @override
  NavTarget? build() => null;

  void open(NavTarget? target) {
    if (target != null) state = target;
  }

  void consume() => state = null;
}

final pendingNavTargetProvider = NotifierProvider<PendingNavTarget, NavTarget?>(PendingNavTarget.new);
