import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Remote Config parameters with the defaults bundled in the app. The app
/// works with these alone (offline, Firebase off); Remote Config only
/// changes them. Keys and meanings: docs/analitik.md.
const remoteDefaults = <String, Object>{
  'paywall_variant': 'a',
  'trial_days': 0,
  'price_copy': 'savings',
  'paywall_after_lessons': 5,
  'paywall_cooldown_days': 7,
  'referral_enabled': true,
  'ai_chat_enabled': true,
};

/// Typed view of the parameters. Out-of-range values fall back to defaults.
@immutable
class RemoteFlags {
  const RemoteFlags({
    this.paywallVariant = 'a',
    this.trialDays = 0,
    this.priceCopy = PriceCopy.savings,
    this.paywallAfterLessons = 5,
    this.paywallCooldownDays = 7,
    this.referralEnabled = true,
    this.aiChatEnabled = true,
  });

  /// Bundled defaults.
  static const defaults = RemoteFlags();

  factory RemoteFlags.fromValues(Map<String, String> v) {
    int intOf(String key, int fallback, int min, int max) {
      final n = int.tryParse(v[key]?.trim() ?? '');
      return n == null || n < min || n > max ? fallback : n;
    }

    bool boolOf(String key, bool fallback) => switch (v[key]?.trim().toLowerCase()) {
      'true' || '1' => true,
      'false' || '0' => false,
      _ => fallback,
    };

    final variant = v['paywall_variant']?.trim().toLowerCase();
    return RemoteFlags(
      paywallVariant: variant != null && paywallVariants.contains(variant)
          ? variant
          : defaults.paywallVariant,
      trialDays: intOf('trial_days', defaults.trialDays, 0, 31),
      priceCopy: PriceCopy.parse(v['price_copy']) ?? defaults.priceCopy,
      paywallAfterLessons: intOf('paywall_after_lessons', defaults.paywallAfterLessons, 0, 1000),
      paywallCooldownDays: intOf('paywall_cooldown_days', defaults.paywallCooldownDays, 1, 365),
      referralEnabled: boolOf('referral_enabled', defaults.referralEnabled),
      aiChatEnabled: boolOf('ai_chat_enabled', defaults.aiChatEnabled),
    );
  }

  static const paywallVariants = {'a', 'b'};

  /// `a`: feature list first (control). `b`: plans first, short header.
  final String paywallVariant;

  /// Free trial length the Play offer gives (0 = no trial). The paywall
  /// mentions a trial only when the store also reports one.
  final int trialDays;

  /// How the yearly price is explained (always computed from real prices).
  final PriceCopy priceCopy;

  /// Show the paywall once after this many finished lessons (0 = never).
  final int paywallAfterLessons;

  /// Minimum days between two such automatic paywalls.
  final int paywallCooldownDays;

  /// "Arkadaşını davet et" in Profil.
  final bool referralEnabled;

  /// Live AI conversation (the demo mode stays available when off).
  final bool aiChatEnabled;

  @override
  bool operator ==(Object other) =>
      other is RemoteFlags &&
      other.paywallVariant == paywallVariant &&
      other.trialDays == trialDays &&
      other.priceCopy == priceCopy &&
      other.paywallAfterLessons == paywallAfterLessons &&
      other.paywallCooldownDays == paywallCooldownDays &&
      other.referralEnabled == referralEnabled &&
      other.aiChatEnabled == aiChatEnabled;

  @override
  int get hashCode => Object.hash(
    paywallVariant,
    trialDays,
    priceCopy,
    paywallAfterLessons,
    paywallCooldownDays,
    referralEnabled,
    aiChatEnabled,
  );
}

/// Yearly plan subline on the paywall.
enum PriceCopy {
  /// "%49 tasarruf" badge.
  savings('savings'),

  /// "Aylık yalnızca ₺66,67" under the yearly price.
  monthlyEquivalent('monthly_equivalent'),

  /// Plain prices only.
  plain('plain');

  const PriceCopy(this.id);
  final String id;

  static PriceCopy? parse(String? raw) {
    for (final c in values) {
      if (c.id == raw?.trim().toLowerCase()) return c;
    }
    return null;
  }
}

/// Reads parameter values. [FirebaseRemoteConfigSource] in production.
abstract class RemoteConfigSource {
  /// Values active now (last fetched ones, or the defaults).
  Future<Map<String, String>> activeValues();

  /// Fetches new values in the background; they apply at the next start so
  /// the paywall never changes in front of the user.
  Future<void> fetchForNextStart();
}

class FirebaseRemoteConfigSource implements RemoteConfigSource {
  FirebaseRemoteConfigSource([FirebaseRemoteConfig? rc]) : _rc = rc ?? FirebaseRemoteConfig.instance;
  final FirebaseRemoteConfig _rc;

  @override
  Future<Map<String, String>> activeValues() async {
    await _rc.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kReleaseMode ? const Duration(hours: 12) : const Duration(minutes: 5),
      ),
    );
    await _rc.setDefaults(remoteDefaults);
    await _rc.activate();
    return {for (final e in _rc.getAll().entries) e.key: e.value.asString()};
  }

  @override
  Future<void> fetchForNextStart() => _rc.fetch();
}

/// Overridden in `main()` for production Firebase builds; null otherwise.
final remoteConfigSourceProvider = Provider<RemoteConfigSource?>((ref) => null);

/// Current flags: bundled defaults until Remote Config answered.
class RemoteFlagsNotifier extends Notifier<RemoteFlags> {
  @override
  RemoteFlags build() {
    final source = ref.watch(remoteConfigSourceProvider);
    if (source != null) Future.microtask(() => _load(source));
    return RemoteFlags.defaults;
  }

  Future<void> _load(RemoteConfigSource source) async {
    try {
      final values = await source.activeValues();
      if (!ref.mounted) return;
      state = RemoteFlags.fromValues(values);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('remote config: $e');
    }
    try {
      await source.fetchForNextStart();
    } on Object {
      // Offline: try again next start.
    }
  }
}

final remoteFlagsProvider = NotifierProvider<RemoteFlagsNotifier, RemoteFlags>(RemoteFlagsNotifier.new);
