import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress.dart';
import 'analytics_events.dart';

export 'analytics_events.dart';

/// Where events end up. [FirebaseAnalyticsSink] in production builds; tests
/// use a fake. Never receives anything without consent.
abstract class AnalyticsSink {
  Future<void> log(String name, Map<String, Object> params);
  Future<void> setUserProperty(String name, String? value);

  /// Turns collection on or off on the device (consent granted / withdrawn).
  Future<void> setCollectionEnabled(bool enabled);

  /// Deletes the analytics instance id and the data stored on the device.
  Future<void> reset();
}

/// Firebase Analytics, configured for privacy: collection starts disabled
/// (AndroidManifest / Info.plist), no user id is ever set, advertising
/// signals are always denied.
class FirebaseAnalyticsSink implements AnalyticsSink {
  FirebaseAnalyticsSink([FirebaseAnalytics? fa]) : _fa = fa ?? FirebaseAnalytics.instance;
  final FirebaseAnalytics _fa;

  @override
  Future<void> log(String name, Map<String, Object> params) =>
      _fa.logEvent(name: name, parameters: params.isEmpty ? null : params);

  @override
  Future<void> setUserProperty(String name, String? value) => _fa.setUserProperty(name: name, value: value);

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    await _fa.setConsent(
      analyticsStorageConsentGranted: enabled,
      adStorageConsentGranted: false,
      adUserDataConsentGranted: false,
      adPersonalizationSignalsConsentGranted: false,
    );
    await _fa.setAnalyticsCollectionEnabled(enabled);
  }

  @override
  Future<void> reset() => _fa.resetAnalyticsData();
}

/// The analytics backend, or null (Firebase off, emulator, tests). Overridden
/// in `main()` for production Firebase builds only.
final analyticsSinkProvider = Provider<AnalyticsSink?>((ref) => null);

/// The user's analytics choice: null = not asked yet, true = allowed,
/// false = declined. Stored on the device only.
class AnalyticsConsent extends Notifier<bool?> {
  static const key = 'analytics.consent';

  @override
  bool? build() => ref.read(prefsProvider).getBool(key);

  void set(bool allowed) {
    state = allowed;
    ref.read(prefsProvider).setBool(key, allowed);
  }
}

final analyticsConsentProvider = NotifierProvider<AnalyticsConsent, bool?>(AnalyticsConsent.new);

/// Should the consent question be shown (analytics exists, not asked yet)?
final shouldAskAnalyticsConsentProvider = Provider<bool>(
  (ref) => ref.watch(analyticsSinkProvider) != null && ref.watch(analyticsConsentProvider) == null,
);

/// Events logged before the consent answer. In memory only, never stored.
final analyticsBufferProvider = Provider<List<AnalyticsEvent>>((ref) => []);

/// Logs [AnalyticsEvent]s, but only when a sink exists **and** the user said
/// yes. While the question is still open, events wait in a small in-memory
/// buffer: sent if the user agrees, dropped if not.
class AnalyticsService {
  AnalyticsService(this._sink, this._consent, this._buffer);

  final AnalyticsSink? _sink;
  final bool? _consent;
  final List<AnalyticsEvent> _buffer;
  static const maxBuffered = 30;

  bool get enabled => _sink != null && _consent == true;

  void log(AnalyticsEvent e) {
    final sink = _sink;
    if (sink == null || _consent == false) return;
    if (_consent == null) {
      if (_buffer.length < maxBuffered) _buffer.add(e);
      return;
    }
    // Analytics must never break the app.
    sink.log(e.name, e.params).catchError((Object err) {
      if (kDebugMode) debugPrint('analytics: $err');
    });
  }

  void setUserProperty(String name, String? value) {
    if (!enabled) return;
    _sink!.setUserProperty(name, value).catchError((Object _) {});
  }
}

final analyticsProvider = Provider<AnalyticsService>(
  (ref) => AnalyticsService(
    ref.watch(analyticsSinkProvider),
    ref.watch(analyticsConsentProvider),
    ref.watch(analyticsBufferProvider),
  ),
);

/// Applies the consent to the SDK and flushes or drops buffered events.
/// Listened to from the app root.
final analyticsConsentSyncProvider = Provider<void>((ref) {
  final sink = ref.watch(analyticsSinkProvider);
  if (sink == null) return;
  ref.listen<bool?>(analyticsConsentProvider, (before, now) {
    if (now == null) return;
    sink.setCollectionEnabled(now).catchError((Object _) {});
    final buffer = ref.read(analyticsBufferProvider);
    final waiting = List.of(buffer);
    buffer.clear();
    if (now) {
      for (final e in waiting) {
        sink.log(e.name, e.params).catchError((Object _) {});
      }
    } else if (before == true) {
      // Withdrawn: delete the instance id and the analytics data on the device.
      sink.reset().catchError((Object _) {});
    }
  }, fireImmediately: true);
});

/// Shorthand for widgets: `logEvent(ref, AnalyticsEvent.featureUse(...))`.
void logEvent(WidgetRef ref, AnalyticsEvent e) => ref.read(analyticsProvider).log(e);

/// Same as [logEvent] for widgets without a `ref` (plain StatelessWidgets).
void logEventFrom(BuildContext context, AnalyticsEvent e) =>
    ProviderScope.containerOf(context, listen: false).read(analyticsProvider).log(e);
