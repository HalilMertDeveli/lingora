import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_resume.dart';
import '../../data/progress.dart';
import '../firebase/firebase_providers.dart';
import 'analytics.dart';

/// Owner dashboard counters (admin panel > Panel, docs/panel-istatistik.md).
///
/// Sends single, anonymous funnel steps to the `countFunnel` callable, which
/// only adds one to that day's total (functions/src/stats.ts): no user id,
/// device id or parameters are stored. Like Firebase Analytics it runs only
/// with analytics consent, and each step goes at most once per install
/// (paywall_view and purchase_start once per day).
abstract final class FunnelStep {
  static const firstOpen = 'first_open';
  static const firstLesson = 'first_lesson';
  static const paywallView = 'paywall_view';
  static const purchaseStart = 'purchase_start';
  static const returnD1 = 'return_d1';
  static const returnD7 = 'return_d7';
}

abstract interface class FunnelReporter {
  Future<void> report(String step);
}

class CallableFunnelReporter implements FunnelReporter {
  CallableFunnelReporter(this._functions);
  final FirebaseFunctions _functions;

  @override
  Future<void> report(String step) => _functions.httpsCallable('countFunnel').call<void>({'step': step});
}

/// The reporter, or null without Firebase, sign-in (an anonymous account is
/// enough) or analytics consent.
final funnelReporterProvider = Provider<FunnelReporter?>((ref) {
  if (ref.watch(analyticsConsentProvider) != true) return null;
  final f = ref.watch(functionsProvider);
  if (f == null || ref.watch(currentUidProvider) == null) return null;
  return CallableFunnelReporter(f);
});

const _installDayKey = 'stats.installDay';
const _legacyKey = 'stats.legacy';
const _sentPrefix = 'stats.sent.';

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Listened to from the app root. Remembers the install day (on the device
/// only) and reports first open, first lesson and day-1/day-7 returns.
final funnelStatsProvider = NotifierProvider<FunnelStats, void>(FunnelStats.new);

class FunnelStats extends Notifier<void> {
  SharedPreferences get _prefs => ref.read(prefsProvider);
  DateTime get _now => ref.read(clockProvider)();

  @override
  void build() {
    final prefs = _prefs;
    if (prefs.getString(_installDayKey) == null) {
      prefs.setString(_installDayKey, _day(_now));
      // Installed before this feature: not a new install, no funnel steps.
      final p = ref.read(progressProvider);
      if (p.onboarded || p.totalXp > 0 || p.lessonsDone > 0) prefs.setBool(_legacyKey, true);
    }
    ref.watch(appResumeProvider);
    final reporter = ref.watch(funnelReporterProvider);
    if (reporter == null || prefs.getBool(_legacyKey) == true) return;

    _once(reporter, FunnelStep.firstOpen);
    final installed = DateTime.tryParse(prefs.getString(_installDayKey)!);
    if (installed != null) {
      final now = _now;
      final age = DateTime(now.year, now.month, now.day).difference(installed).inDays;
      if (age == 1) _once(reporter, FunnelStep.returnD1);
      if (age == 7) _once(reporter, FunnelStep.returnD7);
    }
    if (ref.read(progressProvider).lessonsDone > 0) _once(reporter, FunnelStep.firstLesson);
    ref.listen<int>(progressProvider.select((p) => p.lessonsDone), (_, done) {
      if (done > 0) _once(reporter, FunnelStep.firstLesson);
    });
  }

  /// Called for every analytics event that was really sent (consent given).
  void onAnalyticsEvent(AnalyticsEvent e) {
    if (e.name != FunnelStep.paywallView && e.name != FunnelStep.purchaseStart) return;
    final reporter = ref.read(funnelReporterProvider);
    if (reporter == null) return;
    _send(reporter, e.name, _day(_now));
  }

  void _once(FunnelReporter reporter, String step) => _send(reporter, step, 'yes');

  /// Sends [step] unless it was already sent with the same [mark].
  void _send(FunnelReporter reporter, String step, String mark) {
    final key = '$_sentPrefix$step';
    if (_prefs.getString(key) == mark) return;
    _prefs.setString(key, mark); // before the call: never twice, even if it is slow
    reporter.report(step).catchError((Object e) {
      // Lost counts are fine; allow one retry on a later start.
      _prefs.remove(key);
      if (kDebugMode) debugPrint('funnel $step: $e');
    });
  }
}
