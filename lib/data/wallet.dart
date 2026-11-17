import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Altın: the in-app currency (docs/altin.md). It is only earned by
/// studying (lessons, daily goal, quests, streak milestones, the weekly
/// league) and spent in the Mağaza. It is never sold for real money.
///
/// The wallet is part of [Progress] (key `wallet`), so it syncs with the
/// account like the rest of the progress and stays on the device for guests.
///
/// Balances are grow-only counters per device (a G-counter): every device
/// only ever raises its own `earned` and `spent` totals, and merging two
/// copies takes the maximum per device. So nothing earned on one phone is
/// lost when another phone syncs, and the merge never double-counts.

/// Gold for a finished lesson (not for chests or reviews without answers).
const goldPerLesson = 5;

/// Extra gold for a lesson without mistakes.
const goldPerfectBonus = 3;

/// Gold the first time the daily XP goal is reached on a day.
const goldDailyGoal = 10;

/// Gold for reaching a streak length (days → gold), once per streak.
const goldStreakMilestones = {3: 15, 7: 30, 14: 50, 30: 100, 60: 150, 100: 300, 200: 500, 365: 1000};

/// Gold for a finished league week. Nothing for a week without XP.
int goldForLeague({required bool promoted, required bool demoted, required int rank, required int xp}) {
  if (xp <= 0) return 0;
  final base = promoted ? 60 : (demoted ? 15 : 30);
  return base + (rank >= 1 && rank <= 3 ? 20 : 0);
}

/// Most streak freezes that can be kept in stock.
const maxFreezes = 2;

/// Why gold was earned (shown in tests and analytics; the ad session adds
/// [rewardedAd]).
enum GoldReason {
  lesson,
  perfect,
  dailyGoal,
  quest,
  streak,
  league,
  rewardedAd,
  other,

  /// Premium's second helping (Premium earns twice the gold).
  premium,
}

/// Days one-off reward keys are kept (see [Wallet.once]).
const _onceKeepDays = 60;

/// The slots an item can be worn in.
abstract final class WalletSlot {
  static const avatar = 'avatar';
  static const frame = 'frame';
  static const mascot = 'mascot';
  static const theme = 'theme';

  /// Pofuduk's outfit (Çocuk modu only).
  static const pofuduk = 'pofuduk';
  static const all = [avatar, frame, mascot, theme, pofuduk];

  /// Not an item slot: [faceAvatar] when the learner shows their Mağaza
  /// avatar instead of their photo.
  static const face = 'face';
  static const faceAvatar = 'avatar';
}

/// Most showcase items shown to friends.
const maxShowcase = 3;

class Wallet {
  const Wallet({
    this.earned = const {},
    this.spent = const {},
    this.owned = const [],
    this.freezeBought = const {},
    this.freezeUsed = const {},
    this.once = const {},
    this.equipped = const {},
    this.showcase = const [],
    this.styledAt = 0,
  });

  /// Gold earned, per device id (grow-only).
  final Map<String, int> earned;

  /// Gold spent, per device id (grow-only).
  final Map<String, int> spent;

  /// Bought item ids (never removed).
  final List<String> owned;

  /// Streak freezes bought / used up, per device id (grow-only).
  final Map<String, int> freezeBought;
  final Map<String, int> freezeUsed;

  /// One-off rewards already given (e.g. `goal:2026-11-17`,
  /// `streak:7:2026-11-11`, `league:2026-11-09`) → day key it was given.
  final Map<String, String> once;

  /// Worn item per [WalletSlot].
  final Map<String, String> equipped;

  /// Up to [maxShowcase] owned items shown to friends.
  final List<String> showcase;

  /// When [equipped] or [showcase] last changed (ms), for the merge.
  final int styledAt;

  static int _sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

  int get totalEarned => _sum(earned);

  /// Gold to spend. Two phones spending offline at the same time could
  /// overdraw; then the balance shows 0 until new gold covers it.
  int get balance => max(0, _sum(earned) - _sum(spent));

  /// Streak freezes in stock.
  int get freezes => max(0, _sum(freezeBought) - _sum(freezeUsed));

  bool owns(String id) => owned.contains(id);

  Wallet copyWith({
    Map<String, int>? earned,
    Map<String, int>? spent,
    List<String>? owned,
    Map<String, int>? freezeBought,
    Map<String, int>? freezeUsed,
    Map<String, String>? once,
    Map<String, String>? equipped,
    List<String>? showcase,
    int? styledAt,
  }) => Wallet(
    earned: earned ?? this.earned,
    spent: spent ?? this.spent,
    owned: owned ?? this.owned,
    freezeBought: freezeBought ?? this.freezeBought,
    freezeUsed: freezeUsed ?? this.freezeUsed,
    once: once ?? this.once,
    equipped: equipped ?? this.equipped,
    showcase: showcase ?? this.showcase,
    styledAt: styledAt ?? this.styledAt,
  );

  /// Adds [amount] gold earned on [device].
  Wallet credit(String device, int amount) =>
      amount <= 0 ? this : copyWith(earned: {...earned, device: (earned[device] ?? 0) + amount});

  /// Takes [amount] gold on [device]; the caller checks the balance.
  Wallet debit(String device, int amount) =>
      amount <= 0 ? this : copyWith(spent: {...spent, device: (spent[device] ?? 0) + amount});

  /// Uses [n] streak freezes on [device].
  Wallet useFreezes(String device, int n) =>
      n <= 0 ? this : copyWith(freezeUsed: {...freezeUsed, device: (freezeUsed[device] ?? 0) + n});

  /// Drops one-off keys older than [_onceKeepDays] days before [today].
  Wallet pruned(String today) {
    final cut = DateTime.parse(today).subtract(const Duration(days: _onceKeepDays));
    final oldest = _day(cut);
    if (once.values.every((d) => d.compareTo(oldest) >= 0)) return this;
    return copyWith(
      once: {
        for (final e in once.entries)
          if (e.value.compareTo(oldest) >= 0) e.key: e.value,
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'earned': earned,
    'spent': spent,
    'owned': owned,
    'freezeBought': freezeBought,
    'freezeUsed': freezeUsed,
    'once': once,
    'equipped': equipped,
    'showcase': showcase,
    'styledAt': styledAt,
  };

  factory Wallet.fromJson(Map<String, dynamic> j) {
    Map<String, int> ints(Object? v) => {
      for (final e in ((v as Map?) ?? const {}).entries)
        if (e.value is num) '${e.key}': max(0, (e.value as num).toInt()),
    };
    Map<String, String> strs(Object? v) => {
      for (final e in ((v as Map?) ?? const {}).entries)
        if (e.value is String) '${e.key}': e.value as String,
    };
    List<String> list(Object? v) => [
      for (final e in (v as List?) ?? const [])
        if (e is String) e,
    ];
    return Wallet(
      earned: ints(j['earned']),
      spent: ints(j['spent']),
      owned: list(j['owned']),
      freezeBought: ints(j['freezeBought']),
      freezeUsed: ints(j['freezeUsed']),
      once: strs(j['once']),
      equipped: strs(j['equipped']),
      showcase: list(j['showcase']).take(maxShowcase).toList(),
      styledAt: (j['styledAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Merges two wallets without losing gold: the maximum per device for the
/// counters, the union of owned items and given rewards, and the look
/// (equipped items, showcase) of the copy styled last.
Wallet mergeWallets(Wallet a, Wallet b) {
  Map<String, int> maxMap(Map<String, int> x, Map<String, int> y) => {
    ...x,
    for (final e in y.entries)
      if (!x.containsKey(e.key) || e.value > x[e.key]!) e.key: e.value,
  };
  final style = b.styledAt > a.styledAt ? b : a;
  return Wallet(
    earned: maxMap(a.earned, b.earned),
    spent: maxMap(a.spent, b.spent),
    // Sorted, so both sides end with the same list.
    owned: ({...a.owned, ...b.owned}.toList()..sort()),
    freezeBought: maxMap(a.freezeBought, b.freezeBought),
    freezeUsed: maxMap(a.freezeUsed, b.freezeUsed),
    once: {
      ...a.once,
      for (final e in b.once.entries)
        if ((a.once[e.key] ?? '').compareTo(e.value) < 0) e.key: e.value,
    },
    equipped: style.equipped,
    showcase: style.showcase,
    styledAt: style.styledAt,
  );
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _deviceKey = 'wallet_device_v1';

/// This install's id in the wallet counters (random, made once).
String walletDevice(SharedPreferences prefs) {
  final have = prefs.getString(_deviceKey);
  if (have != null && have.isNotEmpty) return have;
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random.secure();
  final id =
      'd${String.fromCharCodes([for (var i = 0; i < 11; i++) chars.codeUnitAt(r.nextInt(chars.length))])}';
  prefs.setString(_deviceKey, id);
  return id;
}
