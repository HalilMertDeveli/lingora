import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/core/app_resume.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/services/growth/analytics.dart';
import 'package:lingora/services/growth/funnel_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeReporter implements FunnelReporter {
  final sent = <String>[];
  bool fail = false;

  @override
  Future<void> report(String step) {
    sent.add(step);
    return fail ? Future.error(Exception('offline')) : Future.value();
  }
}

void main() {
  late FakeReporter reporter;
  late DateTime now;

  setUp(() {
    reporter = FakeReporter();
    now = DateTime(2026, 11, 19, 10);
  });

  Future<ProviderContainer> start(
    Map<String, Object> prefs, {
    FunnelReporter? withReporter,
    bool noReporter = false,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(p),
        clockProvider.overrideWithValue(() => now),
        funnelReporterProvider.overrideWithValue(noReporter ? null : (withReporter ?? reporter)),
      ],
    );
    addTearDown(c.dispose);
    c.listen(funnelStatsProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  test('a new install reports first_open once', () async {
    final c = await start({});
    expect(reporter.sent, ['first_open']);
    c.read(appResumeProvider.notifier).bump();
    await Future<void>.delayed(Duration.zero);
    expect(reporter.sent, ['first_open']);
    final prefs = c.read(prefsProvider);
    expect(prefs.getString('stats.installDay'), '2026-11-19');
  });

  test('installs from before the feature report nothing', () async {
    await start({'progress_v1': jsonEncode(const Progress(onboarded: true, lessonsDone: 3).toJson())});
    expect(reporter.sent, isEmpty);
  });

  test('day 1 and day 7 returns, nothing on other days', () async {
    var c = await start({'stats.installDay': '2026-11-18', 'stats.sent.first_open': 'yes'});
    expect(reporter.sent, ['return_d1']);
    c.read(appResumeProvider.notifier).bump();
    await Future<void>.delayed(Duration.zero);
    expect(reporter.sent, ['return_d1'], reason: 'once');

    reporter.sent.clear();
    c = await start({'stats.installDay': '2026-11-17', 'stats.sent.first_open': 'yes'});
    expect(reporter.sent, isEmpty);

    c = await start({'stats.installDay': '2026-11-12', 'stats.sent.first_open': 'yes'});
    expect(reporter.sent, ['return_d7']);
  });

  test('the first finished lesson is reported once', () async {
    final c = await start({'stats.sent.first_open': 'yes', 'stats.installDay': '2026-11-19'});
    expect(reporter.sent, isEmpty);
    c.read(progressProvider.notifier).applySynced(const Progress(onboarded: true, lessonsDone: 1));
    await Future<void>.delayed(Duration.zero);
    c.read(progressProvider.notifier).applySynced(const Progress(onboarded: true, lessonsDone: 2));
    await Future<void>.delayed(Duration.zero);
    expect(reporter.sent, ['first_lesson']);
  });

  test('paywall_view and purchase_start once a day; other events ignored', () async {
    final c = await start({'stats.sent.first_open': 'yes', 'stats.installDay': '2026-11-01'});
    final f = c.read(funnelStatsProvider.notifier);
    f.onAnalyticsEvent(AnalyticsEvent.paywallView(placement: 'profile', variant: 'a'));
    f.onAnalyticsEvent(AnalyticsEvent.paywallView(placement: 'shop', variant: 'a'));
    f.onAnalyticsEvent(AnalyticsEvent.purchaseStart(plan: 'yearly', placement: 'profile'));
    f.onAnalyticsEvent(AnalyticsEvent.paywallClose(placement: 'profile', variant: 'a'));
    expect(reporter.sent, ['paywall_view', 'purchase_start']);
    now = now.add(const Duration(days: 1));
    f.onAnalyticsEvent(AnalyticsEvent.paywallView(placement: 'profile', variant: 'a'));
    expect(reporter.sent, ['paywall_view', 'purchase_start', 'paywall_view']);
  });

  test('a failed report is retried on a later start', () async {
    reporter.fail = true;
    final c = await start({});
    expect(reporter.sent, ['first_open']);
    expect(c.read(prefsProvider).getString('stats.sent.first_open'), isNull);
    reporter.fail = false;
    c.read(appResumeProvider.notifier).bump();
    await Future<void>.delayed(Duration.zero);
    expect(reporter.sent, ['first_open', 'first_open']);
  });

  test('without consent or Firebase nothing is sent', () async {
    final c = await start({}, noReporter: true);
    c
        .read(funnelStatsProvider.notifier)
        .onAnalyticsEvent(AnalyticsEvent.paywallView(placement: 'p', variant: 'a'));
    expect(reporter.sent, isEmpty);
    // The real provider is null without consent.
    final plain = ProviderContainer(overrides: [prefsProvider.overrideWithValue(c.read(prefsProvider))]);
    addTearDown(plain.dispose);
    expect(plain.read(funnelReporterProvider), isNull);
  });
}
