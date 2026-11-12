import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/screens/consent_sheet.dart';
import 'package:lingora/screens/invite_screen.dart';
import 'package:lingora/screens/paywall_screen.dart';
import 'package:lingora/services/billing/billing_service.dart';
import 'package:lingora/services/billing/iap_billing_service.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/firebase/firebase_providers.dart';
import 'package:lingora/services/growth/analytics.dart';
import 'package:lingora/services/growth/growth.dart';
import 'package:lingora/services/growth/paywall_trigger.dart';
import 'package:lingora/services/growth/referral.dart';
import 'package:lingora/services/growth/remote_flags.dart';
import 'package:lingora/services/speech.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'premium_test.dart' show FakeBilling, FakeSpeech;

class FakeSink implements AnalyticsSink {
  final events = <String>[];
  final params = <Map<String, Object>>[];
  final props = <String, String?>{};
  final collection = <bool>[];
  int resets = 0;

  @override
  Future<void> log(String name, Map<String, Object> p) async {
    events.add(name);
    params.add(p);
  }

  @override
  Future<void> setUserProperty(String name, String? value) async => props[name] = value;

  @override
  Future<void> setCollectionEnabled(bool enabled) async => collection.add(enabled);

  @override
  Future<void> reset() async => resets++;
}

class FakeRemote implements RemoteConfigSource {
  FakeRemote(this.values);
  final Map<String, String> values;
  int fetches = 0;

  @override
  Future<Map<String, String>> activeValues() async => values;

  @override
  Future<void> fetchForNextStart() async => fetches++;
}

class FakeReferral implements ReferralService {
  final redeemed = <String>[];
  String? failWith;

  @override
  Future<InviteInfo> myInvite() async => const InviteInfo(code: 'K7M3QXA', rewardedThisMonth: 2);

  @override
  Future<void> redeem(String code, {required String deviceId}) async {
    if (failWith case final r?) throw ReferralException(r);
    redeemed.add('$code@$deviceId');
  }
}

/// A store whose yearly plan comes with a 7-day free trial.
class TrialBilling extends FakeBilling {
  @override
  Future<List<StoreProduct>> loadProducts(Set<String> ids) async => const [
    StoreProduct(id: 'lingora_premium_monthly', title: 'Aylık', price: '₺100,00', rawPrice: 100),
    StoreProduct(
      id: 'lingora_premium_yearly',
      title: 'Yıllık',
      price: '₺600,00',
      rawPrice: 600,
      freeTrialDays: 7,
    ),
  ];
}

final now = DateTime(2026, 11, 10, 12);

Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<ProviderContainer> container({
  AnalyticsSink? sink,
  RemoteConfigSource? remote,
  Map<String, Object> prefs = const {},
  BillingService? billing,
}) async {
  final p = await prefsWith(prefs);
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(p),
      clockProvider.overrideWithValue(() => now),
      analyticsSinkProvider.overrideWithValue(sink),
      remoteConfigSourceProvider.overrideWithValue(remote),
      billingServiceProvider.overrideWithValue(billing ?? FakeBilling()),
      premiumDevOverrideProvider.overrideWithValue(false),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<List<Override>> widgetOverrides(
  WidgetTester tester, {
  AnalyticsSink? sink,
  Override? sinkOverride,
  Map<String, Object> prefs = const {},
  RemoteConfigSource? remote,
  ReferralService? referral,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // The mascot animates forever otherwise.
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final p = await prefsWith(prefs);
  return [
    prefsProvider.overrideWithValue(p),
    clockProvider.overrideWithValue(() => now),
    billingServiceProvider.overrideWithValue(FakeBilling()),
    premiumDevOverrideProvider.overrideWithValue(false),
    sinkOverride ?? analyticsSinkProvider.overrideWithValue(sink),
    remoteConfigSourceProvider.overrideWithValue(remote),
    referralServiceProvider.overrideWithValue(referral),
    speechProvider.overrideWithValue(FakeSpeech()),
  ];
}

Widget app(List<Override> overrides, Widget home) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(home: home),
);

void main() {
  group('analytics', () {
    test('does nothing when Firebase/analytics is off', () async {
      final c = await container();
      final a = c.read(analyticsProvider);
      expect(a.enabled, isFalse);
      a.log(AnalyticsEvent.lessonStart('n1', mode: 'lesson'));
      expect(c.read(analyticsBufferProvider), isEmpty);
      expect(c.read(shouldAskAnalyticsConsentProvider), isFalse);
    });

    test('nothing is sent before consent; agreeing flushes the buffer', () async {
      final sink = FakeSink();
      final c = await container(sink: sink);
      c.listen(analyticsConsentSyncProvider, (_, _) {});
      expect(c.read(shouldAskAnalyticsConsentProvider), isTrue);
      c.read(analyticsProvider).log(AnalyticsEvent.onboardingStep('welcome', 0));
      await pumpEventQueue();
      expect(sink.events, isEmpty);
      c.read(analyticsConsentProvider.notifier).set(true);
      await pumpEventQueue();
      expect(sink.collection, [true]);
      expect(sink.events, ['onboarding_step']);
      c.read(analyticsProvider).log(AnalyticsEvent.featureUse(AppFeature.reading));
      await pumpEventQueue();
      expect(sink.events, ['onboarding_step', 'feature_use']);
      expect(c.read(prefsProvider).getBool(AnalyticsConsent.key), isTrue);
    });

    test('declining drops buffered events and sends nothing', () async {
      final sink = FakeSink();
      final c = await container(sink: sink);
      c.listen(analyticsConsentSyncProvider, (_, _) {});
      c.read(analyticsProvider).log(AnalyticsEvent.placementStart());
      c.read(analyticsConsentProvider.notifier).set(false);
      c.read(analyticsProvider).log(AnalyticsEvent.featureUse(AppFeature.reading));
      c.read(analyticsProvider).setUserProperty('premium', 'no');
      await pumpEventQueue();
      expect(sink.events, isEmpty);
      expect(sink.props, isEmpty);
      expect(sink.collection, [false]);
      expect(c.read(analyticsBufferProvider), isEmpty);
    });

    test('withdrawing consent stops logging and deletes analytics data', () async {
      final sink = FakeSink();
      final c = await container(sink: sink, prefs: {AnalyticsConsent.key: true});
      c.listen(analyticsConsentSyncProvider, (_, _) {});
      c.read(analyticsProvider).log(AnalyticsEvent.inviteShare());
      c.read(analyticsConsentProvider.notifier).set(false);
      c.read(analyticsProvider).log(AnalyticsEvent.inviteShare());
      await pumpEventQueue();
      expect(sink.events, ['invite_share']);
      expect(sink.collection, [true, false]);
      expect(sink.resets, 1);
    });

    test('churn signals at start-up', () async {
      final sink = FakeSink();
      final progress = const Progress(onboarded: true, streak: 6, lastActiveDay: '2026-11-05').toJson();
      final c = await container(
        sink: sink,
        prefs: {AnalyticsConsent.key: true, 'progress_v1': jsonEncode(progress)},
      );
      c.listen(growthSignalsProvider, (_, _) {});
      await pumpEventQueue();
      expect(sink.events, containsAll(['session_return', 'streak_lost']));
      expect(sink.params[sink.events.indexOf('session_return')], {'days_away': 5});
      expect(sink.params[sink.events.indexOf('streak_lost')], {'length': 6});
      expect(sink.props['premium'], 'no');
      expect(sink.props['paywall_variant'], 'a');
    });

    test('event names and parameters follow the taxonomy and are documented', () {
      final events = [
        AnalyticsEvent.onboardingStep('welcome', 0),
        AnalyticsEvent.placementStart(),
        AnalyticsEvent.onboardingComplete(method: 'scratch', dailyGoal: 20, track: 'general'),
        AnalyticsEvent.lessonStart('u1_l1', mode: 'lesson'),
        AnalyticsEvent.lessonFinish('u1_l1', mode: 'lesson', accuracy: 140, xp: 15, durationSec: 80),
        AnalyticsEvent.trackChosen('yds', source: 'home'),
        for (final f in AppFeature.values) AnalyticsEvent.featureUse(f),
        AnalyticsEvent.paywallView(placement: PaywallPlacement.aiChat, variant: 'a'),
        AnalyticsEvent.paywallClose(placement: PaywallPlacement.profile, variant: 'b'),
        AnalyticsEvent.purchaseStart(plan: 'yearly', placement: 'profile'),
        AnalyticsEvent.trialStart(plan: 'yearly', trialDays: 7),
        AnalyticsEvent.purchase(plan: 'monthly'),
        AnalyticsEvent.purchaseRestore(found: true),
        AnalyticsEvent.sessionReturn(400),
        AnalyticsEvent.streakLost(3),
        AnalyticsEvent.premiumLapsed(source: 'store'),
        AnalyticsEvent.inviteShare(),
        AnalyticsEvent.inviteRedeem('ok'),
      ];
      final docs = File('docs/analitik.md').readAsStringSync();
      final nameRe = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
      for (final e in events) {
        expect(nameRe.hasMatch(e.name), isTrue, reason: e.name);
        expect(AnalyticsEvent.names, contains(e.name));
        expect(e.params.length, lessThanOrEqualTo(25));
        for (final MapEntry(:key, :value) in e.params.entries) {
          expect(nameRe.hasMatch(key), isTrue, reason: '${e.name}.$key');
          expect(value is int || (value is String && value.length <= 100), isTrue, reason: '${e.name}.$key');
          expect(docs, contains('`$key`'), reason: 'docs/analitik.md must describe ${e.name}.$key');
        }
      }
      expect({for (final e in events) e.name}, AnalyticsEvent.names.toSet());
      for (final name in AnalyticsEvent.names) {
        expect(docs, contains('`$name`'), reason: 'docs/analitik.md must list $name');
      }
      expect(events[4].params['accuracy'], 100);
      expect(events.firstWhere((e) => e.name == 'session_return').params['days_away'], 60);
    });
  });

  group('remote config', () {
    test('bundled defaults match the typed defaults', () {
      final asStrings = {for (final e in remoteDefaults.entries) e.key: '${e.value}'};
      expect(RemoteFlags.fromValues(asStrings), RemoteFlags.defaults);
      expect(RemoteFlags.fromValues(const {}), RemoteFlags.defaults);
      expect(RemoteFlags.defaults.trialDays, 0);
      expect(RemoteFlags.defaults.paywallAfterLessons, 5);
    });

    test('bad values fall back to the defaults', () {
      final f = RemoteFlags.fromValues(const {
        'paywall_variant': 'zzz',
        'trial_days': '-3',
        'price_copy': 'free!',
        'paywall_after_lessons': 'lots',
        'paywall_cooldown_days': '0',
        'referral_enabled': 'maybe',
      });
      expect(f, RemoteFlags.defaults);
    });

    test('values from Remote Config are applied and the next fetch starts', () async {
      final remote = FakeRemote({
        'paywall_variant': 'B',
        'trial_days': '7',
        'price_copy': 'monthly_equivalent',
        'paywall_after_lessons': '0',
        'referral_enabled': 'false',
        'ai_chat_enabled': 'false',
      });
      final c = await container(remote: remote);
      c.listen(remoteFlagsProvider, (_, _) {});
      expect(c.read(remoteFlagsProvider), RemoteFlags.defaults);
      await pumpEventQueue();
      final f = c.read(remoteFlagsProvider);
      expect(f.paywallVariant, 'b');
      expect(f.trialDays, 7);
      expect(f.priceCopy, PriceCopy.monthlyEquivalent);
      expect(f.paywallAfterLessons, 0);
      expect(f.referralEnabled, isFalse);
      expect(f.aiChatEnabled, isFalse);
      expect(remote.fetches, 1);
    });

    test('paywall after N lessons respects the count and the cooldown', () async {
      Future<ProviderContainer> at(int lessons, [Map<String, Object> extra = const {}]) => container(
        prefs: {
          'progress_v1': jsonEncode(Progress(onboarded: true, lessonsDone: lessons).toJson()),
          ...extra,
        },
      );
      expect((await at(4)).read(paywallTriggerProvider).takeAfterLesson(), isFalse);
      final c = await at(5);
      expect(c.read(paywallTriggerProvider).takeAfterLesson(), isTrue);
      expect(c.read(paywallTriggerProvider).takeAfterLesson(), isFalse); // once per N lessons
      // 5 more lessons, but only 3 days later: still in the cooldown.
      final soon = await at(10, {
        'paywall.auto.lessons': 5,
        'paywall.auto.day': now.subtract(const Duration(days: 3)).toIso8601String(),
      });
      expect(soon.read(paywallTriggerProvider).takeAfterLesson(), isFalse);
      final later = await at(10, {
        'paywall.auto.lessons': 5,
        'paywall.auto.day': now.subtract(const Duration(days: 8)).toIso8601String(),
      });
      expect(later.read(paywallTriggerProvider).takeAfterLesson(), isTrue);
    });
  });

  group('paywall and billing', () {
    testWidgets('logs paywall_view with placement and variant, then the purchase', (tester) async {
      final sink = FakeSink();
      await tester.pumpWidget(
        app(
          await widgetOverrides(tester, sink: sink, prefs: {AnalyticsConsent.key: true}),
          const PaywallScreen(feature: PremiumFeature.aiConversation),
        ),
      );
      await tester.pumpAndSettle();
      expect(sink.events, ['paywall_view']);
      expect(sink.params.single, {'placement': 'ai_chat', 'variant': 'a'});
      await tester.tap(find.byKey(const ValueKey('paywall-buy')));
      await tester.pumpAndSettle();
      expect(sink.events, ['paywall_view', 'purchase_start', 'purchase']);
    });

    testWidgets('variant b and monthly-equivalent price copy', (tester) async {
      await tester.pumpWidget(
        app(
          await widgetOverrides(
            tester,
            remote: FakeRemote({'paywall_variant': 'b', 'price_copy': 'monthly_equivalent'}),
          ),
          Consumer(
            builder: (_, ref, _) {
              // Wait until Remote Config applied before opening the paywall.
              final f = ref.watch(remoteFlagsProvider);
              return f.paywallVariant == 'b' ? const PaywallScreen() : const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Konuşarak öğren, sınırsız deneme çöz'), findsOneWidget);
      expect(find.text('Aylık yalnızca ₺50,00'), findsOneWidget);
      expect(find.textContaining('tasarruf'), findsNothing);
      // Plans come before the feature list.
      final plan = tester.getTopLeft(find.byKey(const ValueKey('plan-yearly'))).dy;
      final features = tester.getTopLeft(find.text('Premium ile')).dy;
      expect(plan, lessThan(features));
    });

    test('a trial purchase logs trial_start, a normal one purchase', () async {
      final sink = FakeSink();
      final c = await container(sink: sink, billing: TrialBilling(), prefs: {AnalyticsConsent.key: true});
      c.read(premiumControllerProvider);
      await c.read(premiumControllerProvider.notifier).loadProducts();
      await c.read(premiumControllerProvider.notifier).buy(PremiumPlan.yearly);
      await pumpEventQueue();
      expect(sink.events, ['trial_start']);
      expect(sink.params.single, {'plan': 'yearly', 'trial_days': 7});
    });

    test('ISO periods and per-month prices', () {
      expect(IapBillingService.isoPeriodDays('P7D'), 7);
      expect(IapBillingService.isoPeriodDays('P1W'), 7);
      expect(IapBillingService.isoPeriodDays('P1M'), 30);
      expect(IapBillingService.isoPeriodDays('nonsense'), 0);
      expect(formatPerMonth('₺799,99', 799.99 / 12), '₺66,67');
      expect(formatPerMonth('799,99 TL', 799.99 / 12), '66,67 TL');
      expect(formatPerMonth(r'$59.99', 59.99 / 12), r'$5.00');
      expect(formatPerMonth('free', 1), isNull);
    });
  });

  group('consent UI', () {
    testWidgets('asks once at start with two equal choices', (tester) async {
      final sink = FakeSink();
      await tester.pumpWidget(
        app(await widgetOverrides(tester, sink: sink), const ConsentGate(child: Text('home'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Anonim kullanım istatistikleri'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('consent-no')));
      await tester.pumpAndSettle();
      expect(find.text('Anonim kullanım istatistikleri'), findsNothing);
      final container = ProviderScope.containerOf(tester.element(find.text('home')));
      expect(container.read(analyticsConsentProvider), isFalse);
    });

    testWidgets('asks once Firebase is ready, after the first frame', (tester) async {
      // main() does not wait for Firebase: the sink appears a moment later.
      final firebase = Completer<bool>();
      final sink = FakeSink();
      await tester.pumpWidget(
        app([
          ...await widgetOverrides(
            tester,
            sinkOverride: analyticsSinkProvider.overrideWith(
              (ref) => ref.watch(firebaseReadyProvider) ? sink : null,
            ),
          ),
          firebaseInitProvider.overrideWith((ref) => firebase.future),
        ], const ConsentGate(child: Text('home'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Anonim kullanım istatistikleri'), findsNothing);
      firebase.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Anonim kullanım istatistikleri'), findsOneWidget);
    });

    testWidgets('never asks when analytics is off', (tester) async {
      await tester.pumpWidget(app(await widgetOverrides(tester), const ConsentGate(child: Text('home'))));
      await tester.pumpAndSettle();
      expect(find.text('Anonim kullanım istatistikleri'), findsNothing);
    });

    testWidgets('Profil switch changes the decision', (tester) async {
      final sink = FakeSink();
      await tester.pumpWidget(
        app(
          await widgetOverrides(tester, sink: sink, prefs: {AnalyticsConsent.key: false}),
          const Scaffold(body: AnalyticsConsentTile()),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('analytics-consent-switch')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(AnalyticsConsentTile)));
      expect(container.read(analyticsConsentProvider), isTrue);
    });
  });

  group('invite screen', () {
    testWidgets('shows the code and redeems a friend code', (tester) async {
      final referral = FakeReferral();
      await tester.pumpWidget(app(await widgetOverrides(tester, referral: referral), const InviteScreen()));
      await tester.pumpAndSettle();
      expect(find.text('K7M3QXA'), findsOneWidget);
      expect(find.text('Bu ay 2/5 ödül kazandın.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('invite-code-field')), 'abcd234');
      await tester.tap(find.text('Kodu kullan'));
      await tester.pumpAndSettle();
      expect(referral.redeemed.single, startsWith('abcd234@'));
      expect(find.textContaining('Kod kabul edildi'), findsOneWidget);
    });

    testWidgets('explains a refused code in Turkish', (tester) async {
      final referral = FakeReferral()..failWith = 'device_used';
      await tester.pumpWidget(app(await widgetOverrides(tester, referral: referral), const InviteScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('invite-code-field')), 'ABCD234');
      await tester.tap(find.text('Kodu kullan'));
      await tester.pumpAndSettle();
      expect(find.text('Bu cihazda daha önce bir davet kodu kullanıldı.'), findsOneWidget);
    });

    testWidgets('needs an account when Firebase is off', (tester) async {
      await tester.pumpWidget(app(await widgetOverrides(tester), const InviteScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Dilbaz hesabı gerekir'), findsOneWidget);
    });
  });
}
