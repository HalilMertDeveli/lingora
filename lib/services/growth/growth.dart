import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../data/progress.dart';
import '../billing/premium.dart';
import 'analytics.dart';
import 'remote_flags.dart';

/// Real Analytics and Remote Config, for production Firebase builds only
/// (`--dart-define=LINGORA_FIREBASE=prod`). The emulator's demo project has
/// neither, and builds without Firebase keep the no-op defaults.
List<Override> growthOverrides({required bool enabled}) => enabled
    ? [
        analyticsSinkProvider.overrideWithValue(FirebaseAnalyticsSink()),
        remoteConfigSourceProvider.overrideWithValue(FirebaseRemoteConfigSource()),
      ]
    : const [];

/// App-start churn signals and analytics user properties. Listened to from
/// the app root; does nothing without analytics consent.
final growthSignalsProvider = Provider<void>((ref) {
  ref.watch(analyticsConsentSyncProvider);
  final analytics = ref.read(analyticsProvider);

  // Churn signals, from the progress saved before this session.
  final p = ref.read(progressProvider);
  final now = ref.read(clockProvider)();
  if (p.onboarded && p.lastActiveDay != null) {
    final last = DateTime.tryParse(p.lastActiveDay!);
    if (last != null) {
      final today = DateTime(now.year, now.month, now.day);
      final away = today.difference(DateTime(last.year, last.month, last.day)).inDays;
      if (away >= 2) analytics.log(AnalyticsEvent.sessionReturn(away));
      if (p.streak > 0 && p.streakAt(now) == 0) analytics.log(AnalyticsEvent.streakLost(p.streak));
    }
  }

  ref.listen<bool>(premiumProvider, (before, now) {
    final a = ref.read(analyticsProvider);
    a.setUserProperty('premium', now ? 'yes' : 'no');
    if (before == true && !now) {
      final source = ref.read(premiumControllerProvider).productId == referralProductId
          ? 'referral'
          : 'store';
      a.log(AnalyticsEvent.premiumLapsed(source: source));
    }
  }, fireImmediately: true);
  ref.listen<String>(progressProvider.select((p) => p.trackId), (_, track) {
    ref.read(analyticsProvider).setUserProperty('track', track);
  }, fireImmediately: true);
  ref.listen<String>(remoteFlagsProvider.select((f) => f.paywallVariant), (_, v) {
    ref.read(analyticsProvider).setUserProperty('paywall_variant', v);
  }, fireImmediately: true);
});
