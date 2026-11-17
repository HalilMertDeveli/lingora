import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_settings.dart';
import '../../data/progress.dart';
import '../../data/wallet.dart';
import '../growth/remote_flags.dart';
import 'premium.dart';

/// What Premium adds on top of the paid features (docs/abonelik.md §6):
/// the daily "Neden yanlış?" limit, twice the gold, two streak freezes a
/// month, and how often the paywall may open by itself.

// "Neden yanlış?" ---------------------------------------------------------

/// Wrong answers a day whose "Neden yanlış?" is shown without Premium.
const freeWhyWrongPerDay = 3;

/// One day's "Neden yanlış?" use: the questions whose explanation was shown
/// and those whose explanation stayed locked (both distinct keys).
class WhyWrongDay {
  const WhyWrongDay({this.shown = const [], this.locked = const []});
  final List<String> shown;
  final List<String> locked;

  Map<String, dynamic> toJson() => {'shown': shown, 'locked': locked};

  factory WhyWrongDay.fromJson(Object? j) {
    List<String> list(Object? v) => [
      for (final e in (v is List ? v : const []))
        if (e is String) e,
    ];
    return j is Map ? WhyWrongDay(shown: list(j['shown']), locked: list(j['locked'])) : const WhyWrongDay();
  }
}

/// Counts the "Neden yanlış?" explanations shown today. Without Premium the
/// first [freeWhyWrongPerDay] wrong answers (distinct questions) get theirs;
/// later ones show a blurred preview and the Premium card. Seeing the same
/// question again the same day never costs a second one.
///
/// State: day key → that day's use, for the last 7 days (the paywall's
/// "Bu hafta …" line).
class WhyWrongQuota extends Notifier<Map<String, WhyWrongDay>> {
  static const _key = 'premium.why_wrong_v1';
  static const _keepDays = 7;

  String _today() => dayKey(ref.read(clockProvider)());

  @override
  Map<String, WhyWrongDay> build() {
    final raw = ref.read(prefsProvider).getString(_key);
    if (raw == null) return const {};
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final oldest = dayKey(ref.read(clockProvider)().subtract(const Duration(days: _keepDays - 1)));
      return {
        for (final e in j.entries)
          if (e.key.compareTo(oldest) >= 0) e.key: WhyWrongDay.fromJson(e.value),
      };
    } on Object {
      return const {};
    }
  }

  void _save(Map<String, WhyWrongDay> days) {
    final oldest = dayKey(ref.read(clockProvider)().subtract(const Duration(days: _keepDays - 1)));
    final kept = {
      for (final e in days.entries)
        if (e.key.compareTo(oldest) >= 0) e.key: e.value,
    };
    state = kept;
    ref
        .read(prefsProvider)
        .setString(_key, jsonEncode({for (final e in kept.entries) e.key: e.value.toJson()}));
  }

  WhyWrongDay get _day => state[_today()] ?? const WhyWrongDay();

  /// Explanations still free today (Premium: unlimited, see [premiumProvider]).
  int get leftToday => (freeWhyWrongPerDay - _day.shown.length).clamp(0, freeWhyWrongPerDay);

  /// Whether question [key]'s explanation is open now, without using one.
  bool isUnlocked(String key) => ref.read(premiumProvider) || _day.shown.contains(key);

  /// Called once when question [key] was answered wrongly and has an
  /// explanation. Returns whether it may be shown (and uses one of today's
  /// free ones when needed). A locked one is remembered for the paywall.
  bool claim(String key) {
    final day = _day;
    if (day.shown.contains(key)) return true;
    if (ref.read(premiumProvider)) {
      // Premium: unlimited; still counted for the week's numbers.
      _save({
        ...state,
        _today(): WhyWrongDay(shown: [...day.shown, key], locked: day.locked),
      });
      return true;
    }
    if (day.shown.length < freeWhyWrongPerDay) {
      _save({
        ...state,
        _today(): WhyWrongDay(shown: [...day.shown, key], locked: day.locked),
      });
      return true;
    }
    if (!day.locked.contains(key)) {
      _save({
        ...state,
        _today(): WhyWrongDay(shown: day.shown, locked: [...day.locked, key]),
      });
    }
    return false;
  }

  /// The last 7 days: wrong answers with an explanation, and how many of
  /// them stayed locked.
  ({int wrong, int locked}) week() => whyWrongWeek(state);
}

/// The last 7 days' numbers of a [WhyWrongQuota] state.
({int wrong, int locked}) whyWrongWeek(Map<String, WhyWrongDay> days) {
  var wrong = 0;
  var locked = 0;
  for (final d in days.values) {
    wrong += d.shown.length + d.locked.length;
    locked += d.locked.length;
  }
  return (wrong: wrong, locked: locked);
}

final whyWrongQuotaProvider = NotifierProvider<WhyWrongQuota, Map<String, WhyWrongDay>>(WhyWrongQuota.new);

// Gold and streak freezes --------------------------------------------------

/// Premium earns twice the gold. Every gold credit (lessons, quests, the
/// league, [GoldWallet.earn]) multiplies by this.
final goldMultiplierProvider = Provider<int>((ref) => ref.watch(premiumProvider) ? 2 : 1);

/// Streak freezes Premium adds to the stock each calendar month.
const premiumFreezesPerMonth = 2;

/// Premium may keep this many freezes (bought ones stop at [maxFreezes]).
const premiumMaxFreezes = maxFreezes + premiumFreezesPerMonth;

/// One-off wallet key of a month's Premium freezes, e.g. `pfz:2026-11`.
String premiumFreezeKey(DateTime now) => 'pfz:${now.year}-${now.month.toString().padLeft(2, '0')}';

/// Adds this month's Premium streak freezes to the wallet, once a month
/// (kept in [Wallet.once], so it syncs with the progress). The stock never
/// goes above [premiumMaxFreezes]. Returns how many were added.
int grantMonthlyFreezes(Ref ref) {
  if (!ref.read(premiumProvider)) return 0;
  final now = ref.read(clockProvider)();
  final key = premiumFreezeKey(now);
  final w = ref.read(progressProvider).wallet;
  if (w.once.containsKey(key)) return 0;
  final add = (premiumMaxFreezes - w.freezes).clamp(0, premiumFreezesPerMonth);
  final today = dayKey(now);
  ref.read(progressProvider.notifier).updateWallet((w, device) {
    final marked = w.pruned(today).copyWith(once: {...w.once, key: today});
    if (add == 0) return marked;
    return marked.copyWith(freezeBought: {...w.freezeBought, device: (w.freezeBought[device] ?? 0) + add});
  });
  return add;
}

/// Grants the month's freezes whenever Premium is (or becomes) active.
/// Listened to in main.dart.
final premiumPerksSyncProvider = Provider<void>((ref) {
  if (!ref.watch(premiumProvider)) return;
  Future.microtask(() {
    if (ref.mounted) grantMonthlyFreezes(ref);
  });
});

// Paywall pacing -----------------------------------------------------------

/// Days the paywall does not open by itself after it was closed.
const paywallSnoozeDays = 3;

/// How often a full-screen paywall may open by itself (after a lesson run,
/// when the day's mini mock exam or "Neden yanlış?" is used up): at most
/// once a day, and not for [paywallSnoozeDays] days after one was closed.
/// Never for Premium users or in Çocuk modu. Paywalls the learner opens
/// (a button, a card) are never limited.
class PaywallPacer {
  PaywallPacer(this._ref);
  final Ref _ref;

  static const _autoDayKey = 'paywall.pace.auto_day';
  static const _closedKey = 'paywall.pace.closed_ms';

  DateTime _now() => _ref.read(clockProvider)();

  /// Whether a paywall closed without buying in the last [paywallSnoozeDays] days.
  bool get snoozed {
    final ms = _ref.read(prefsProvider).getInt(_closedKey);
    if (ms == null) return false;
    return _now().difference(DateTime.fromMillisecondsSinceEpoch(ms)) <
        const Duration(days: paywallSnoozeDays);
  }

  /// A full-screen paywall may open by itself now.
  bool get canAutoShow {
    if (_ref.read(premiumProvider)) return false;
    if (_ref.read(appSettingsProvider).isKid) return false;
    if (_ref.read(prefsProvider).getString(_autoDayKey) == dayKey(_now())) return false;
    return !snoozed;
  }

  /// A soft Premium card (streak milestone, …) may show: not for Premium,
  /// Çocuk modu, or while [snoozed].
  bool get canOffer => !_ref.read(premiumProvider) && !_ref.read(appSettingsProvider).isKid && !snoozed;

  /// Remembers that a paywall opened by itself today.
  void recordAutoShown() => _ref.read(prefsProvider).setString(_autoDayKey, dayKey(_now()));

  /// Remembers that a paywall was closed without buying.
  void recordClosed() => _ref.read(prefsProvider).setInt(_closedKey, _now().millisecondsSinceEpoch);

  /// Checks and records in one step: true when the caller should open the
  /// paywall now.
  bool takeAuto() {
    if (!canAutoShow) return false;
    recordAutoShown();
    return true;
  }
}

final paywallPacerProvider = Provider<PaywallPacer>(PaywallPacer.new);

/// Days of free trial to mention on Premium cards: Remote Config's
/// `trial_days` (0 = never), and once Google Play's offers are loaded, only
/// if Play really returns a free trial for the yearly plan.
final trialOfferDaysProvider = Provider<int>(
  (ref) => trialOfferDaysOf(ref.watch(remoteFlagsProvider), ref.watch(premiumControllerProvider)),
);

int trialOfferDaysOf(RemoteFlags flags, PremiumState s) {
  if (flags.trialDays <= 0) return 0;
  if (s.products.isEmpty) return flags.trialDays;
  final yearly = s.product(PremiumPlan.yearly) ?? s.products.first;
  return yearly.freeTrialDays;
}
