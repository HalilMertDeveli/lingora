import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase/firebase_providers.dart';
import 'analytics.dart';

/// Where crash reports go. [FirebaseCrashSink] in production builds; tests
/// use a fake.
abstract class CrashSink {
  Future<void> setCollectionEnabled(bool enabled);
  Future<void> record(Object error, StackTrace? stack, {required bool fatal, String? reason});
  Future<void> recordFlutterError(FlutterErrorDetails details, {required bool fatal});

  /// The Firebase Auth uid, or '' to clear it. Nothing else identifies the user.
  Future<void> setUserId(String uid);

  /// Drops the reports stored on the device that were never sent.
  Future<void> deleteUnsent();
}

/// Firebase Crashlytics. Collection starts disabled (AndroidManifest /
/// Info.plist) and follows the analytics consent (docs/analitik.md).
class FirebaseCrashSink implements CrashSink {
  FirebaseCrashSink([FirebaseCrashlytics? c]) : _c = c ?? FirebaseCrashlytics.instance;
  final FirebaseCrashlytics _c;

  @override
  Future<void> setCollectionEnabled(bool enabled) => _c.setCrashlyticsCollectionEnabled(enabled);

  @override
  Future<void> record(Object error, StackTrace? stack, {required bool fatal, String? reason}) =>
      _c.recordError(error, stack, fatal: fatal, reason: reason);

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details, {required bool fatal}) =>
      fatal ? _c.recordFlutterFatalError(details) : _c.recordFlutterError(details);

  @override
  Future<void> setUserId(String uid) => _c.setUserIdentifier(uid);

  @override
  Future<void> deleteUnsent() => _c.deleteUnsentReports();
}

/// Crash and error reporting for the whole app. Static, because the Flutter
/// and platform error hooks run outside any widget or provider.
///
/// Nothing is sent unless a sink is attached (production Firebase builds
/// only) **and** the user allowed analytics. Errors that happen before the
/// sink is ready wait in a tiny in-memory buffer.
class CrashReporter {
  CrashReporter._();

  static CrashSink? _sink;
  static bool? _consent;
  static final _pending = <(Object, StackTrace?, bool, String?)>[];
  static const maxPending = 5;

  static bool get enabled => _sink != null && _consent == true;

  /// Hooks FlutterError and PlatformDispatcher. Call once from `main()`
  /// with the stored analytics consent.
  static void install({bool? consent}) {
    _consent = consent;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      (previous ?? FlutterError.presentError)(details);
      _report(details.exception, details.stack, fatal: false, details: details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Uncaught: $error');
      _report(error, stack, fatal: true);
      // Handled: the app keeps running (the default would only print it).
      return true;
    };
  }

  /// Production builds: the Firebase sink, once Firebase is ready.
  static void attach(CrashSink sink) {
    _sink = sink;
    _applyConsent();
    final waiting = List.of(_pending);
    _pending.clear();
    if (_consent != true) return;
    for (final (e, st, fatal, reason) in waiting) {
      _safe(sink.record(e, st, fatal: fatal, reason: reason));
    }
  }

  /// The analytics consent changed (null = not asked yet).
  static void setConsent(bool? consent) {
    final before = _consent;
    _consent = consent;
    if (consent == false) _pending.clear();
    if (before != consent) _applyConsent();
    final sink = _sink;
    if (consent == true && sink != null && _pending.isNotEmpty) {
      final waiting = List.of(_pending);
      _pending.clear();
      for (final (e, st, fatal, reason) in waiting) {
        _safe(sink.record(e, st, fatal: fatal, reason: reason));
      }
    }
  }

  /// Signed-in uid (Firebase Auth) or null after sign-out.
  static void setUser(String? uid) {
    if (!enabled) return;
    _safe(_sink!.setUserId(uid ?? ''));
  }

  /// A handled failure worth knowing about (billing, sync, account…).
  /// [reason] is a short fixed key like `billing_buy`, never user text.
  static void nonFatal(Object error, StackTrace? stack, {required String reason}) {
    if (kDebugMode) debugPrint('non-fatal [$reason]: $error');
    _report(error, stack ?? StackTrace.current, fatal: false, reason: reason);
  }

  static void _report(
    Object error,
    StackTrace? stack, {
    required bool fatal,
    String? reason,
    FlutterErrorDetails? details,
  }) {
    if (_consent == false) return;
    final sink = _sink;
    if (sink == null || _consent == null) {
      if (_pending.length < maxPending) _pending.add((error, stack, fatal, reason));
      return;
    }
    if (details != null) {
      _safe(sink.recordFlutterError(details, fatal: fatal));
    } else {
      _safe(sink.record(error, stack, fatal: fatal, reason: reason));
    }
  }

  static void _applyConsent() {
    final sink = _sink;
    if (sink == null || _consent == null) return;
    _safe(sink.setCollectionEnabled(_consent!));
    if (_consent == false) _safe(sink.deleteUnsent());
  }

  // Reporting must never break the app.
  static void _safe(Future<void> f) => unawaited(f.catchError((Object _) {}));

  @visibleForTesting
  static void reset() {
    _sink = null;
    _consent = null;
    _pending.clear();
  }
}

/// Keeps [CrashReporter] in step with the analytics consent and the signed-in
/// uid. Listened to from the app root; a no-op without a sink.
final crashReportingSyncProvider = Provider<void>((ref) {
  ref.listen<bool?>(analyticsConsentProvider, (_, now) {
    CrashReporter.setConsent(now);
    if (now == true) CrashReporter.setUser(ref.read(currentUidProvider));
  }, fireImmediately: true);
  ref.listen<String?>(currentUidProvider, (_, uid) => CrashReporter.setUser(uid), fireImmediately: true);
});
