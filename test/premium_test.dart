import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/course_repository.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/scenarios.dart';
import 'package:lingora/models/exam.dart';
import 'package:lingora/screens/conversation_screen.dart';
import 'package:lingora/screens/exam_screen.dart';
import 'package:lingora/screens/paywall_screen.dart';
import 'package:lingora/services/billing/billing_service.dart';
import 'package:lingora/services/billing/entitlement_backend.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/conversation.dart';
import 'package:lingora/services/speech.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Store double: [owned] products are re-delivered on restore; [autoResult]
/// is what a purchase sheet "returns".
class FakeBilling implements BillingService {
  FakeBilling({this.available = true});
  bool available;
  StorePurchaseStatus autoResult = StorePurchaseStatus.purchased;
  final owned = <String>{};
  final bought = <String>[];
  final completed = <String>[];
  final _ctrl = StreamController<List<StorePurchase>>.broadcast();

  void emit(String id, StorePurchaseStatus status, {bool needsCompletion = true}) => _ctrl.add([
    StorePurchase(productId: id, status: status, token: 'tok-$id', needsCompletion: needsCompletion),
  ]);

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<StoreProduct>> loadProducts(Set<String> ids) async => [
    const StoreProduct(id: 'lingora_premium_monthly', title: 'Aylık', price: '₺100,00', rawPrice: 100),
    const StoreProduct(id: 'lingora_premium_yearly', title: 'Yıllık', price: '₺600,00', rawPrice: 600),
  ].where((p) => ids.contains(p.id)).toList();

  @override
  Future<void> buy(String productId) async {
    bought.add(productId);
    scheduleMicrotask(
      () => emit(productId, autoResult, needsCompletion: autoResult != StorePurchaseStatus.pending),
    );
  }

  @override
  Future<void> restore() async {
    for (final id in owned) {
      scheduleMicrotask(() => emit(id, StorePurchaseStatus.restored));
    }
  }

  @override
  Stream<List<StorePurchase>> get purchases => _ctrl.stream;

  @override
  Future<void> complete(StorePurchase purchase) async => completed.add(purchase.productId);
}

class FakeBackend implements EntitlementBackend {
  FakeBackend(this.result);
  ServerEntitlement result;
  Object? error;
  final verified = <String>[];
  final server = StreamController<ServerEntitlement?>.broadcast();

  @override
  Future<ServerEntitlement> verify({required String productId, required String purchaseToken}) async {
    verified.add(purchaseToken);
    if (error case final e?) throw e;
    return result;
  }

  @override
  Stream<ServerEntitlement?> watch() => server.stream;
}

class FakeSpeech implements SpeechService {
  @override
  Future<void> say(String text, {String lang = 'en', bool slow = false}) async {}
  @override
  Future<bool> get canListen async => false;
  @override
  Future<void> listen({required void Function(String) onWords, required void Function() onDone}) async =>
      onDone();
  @override
  Future<void> stopListening() async {}
}

class LiveFake implements ConversationService {
  @override
  bool get isLive => true;
  @override
  Future<ChatTurn> send(Scenario scenario, List<ChatMessage> history) async => const ChatTurn(reply: 'Hi');
}

final now = DateTime(2026, 11, 10, 12);

Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<ProviderContainer> makeContainer({
  required FakeBilling billing,
  EntitlementBackend? backend,
  Map<String, Object> prefs = const {},
  bool dev = false,
}) async {
  final p = await prefsWith(prefs);
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(p),
      clockProvider.overrideWithValue(() => now),
      billingServiceProvider.overrideWithValue(billing),
      entitlementBackendProvider.overrideWithValue(backend),
      premiumDevOverrideProvider.overrideWithValue(dev),
    ],
  );
  addTearDown(c.dispose);
  c.read(premiumControllerProvider); // subscribe to the store
  return c;
}

Widget app(List<Override> overrides, Widget home) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(home: Scaffold(body: home)),
);

Future<List<Override>> widgetOverrides(
  WidgetTester tester,
  FakeBilling billing, {
  Map<String, Object> prefs = const {},
  bool dev = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final p = await prefsWith(prefs);
  return [
    prefsProvider.overrideWithValue(p),
    clockProvider.overrideWithValue(() => now),
    billingServiceProvider.overrideWithValue(billing),
    premiumDevOverrideProvider.overrideWithValue(dev),
    speechProvider.overrideWithValue(FakeSpeech()),
  ];
}

void main() {
  group('premium controller', () {
    test('free by default, dev override unlocks', () async {
      final c = await makeContainer(billing: FakeBilling());
      expect(c.read(premiumProvider), isFalse);
      final d = await makeContainer(billing: FakeBilling(), dev: true);
      expect(d.read(premiumProvider), isTrue);
    });

    test('a purchase unlocks Premium, is acknowledged and cached', () async {
      final billing = FakeBilling();
      final c = await makeContainer(billing: billing);
      await c.read(premiumControllerProvider.notifier).loadProducts();
      await c.read(premiumControllerProvider.notifier).buy(PremiumPlan.monthly);
      await pumpEventQueue();
      final s = c.read(premiumControllerProvider);
      expect(c.read(premiumProvider), isTrue);
      expect(s.source, PremiumSource.store);
      expect(s.justPurchased, isTrue);
      expect(s.expiresAt, now.add(const Duration(days: 31 + offlineGraceDays)));
      expect(billing.completed, ['lingora_premium_monthly']);
      expect(c.read(prefsProvider).getString('premium.cache'), contains('lingora_premium_monthly'));
    });

    test('the cache survives a restart and lapses after expiry', () async {
      final until = now.add(const Duration(days: 5)).millisecondsSinceEpoch;
      final cache = jsonEncode({'productId': 'lingora_premium_yearly', 'until': until, 'source': 'store'});
      final c = await makeContainer(billing: FakeBilling(), prefs: {'premium.cache': cache});
      expect(c.read(premiumProvider), isTrue);
      final old = jsonEncode({
        'productId': 'lingora_premium_yearly',
        'until': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        'source': 'store',
      });
      final d = await makeContainer(billing: FakeBilling(), prefs: {'premium.cache': old});
      expect(d.read(premiumProvider), isFalse);
    });

    test('pending and cancelled purchases do not unlock', () async {
      final billing = FakeBilling()..autoResult = StorePurchaseStatus.pending;
      final c = await makeContainer(billing: billing);
      await c.read(premiumControllerProvider.notifier).buy(PremiumPlan.yearly);
      await pumpEventQueue();
      expect(c.read(premiumControllerProvider).pending, isTrue);
      expect(c.read(premiumProvider), isFalse);
      expect(billing.completed, isEmpty);
      billing.emit('lingora_premium_yearly', StorePurchaseStatus.canceled, needsCompletion: false);
      await pumpEventQueue();
      expect(c.read(premiumControllerProvider).pending, isFalse);
      expect(c.read(premiumProvider), isFalse);
      // The payment clears later: Premium turns on by itself.
      billing.emit('lingora_premium_yearly', StorePurchaseStatus.purchased);
      await pumpEventQueue();
      expect(c.read(premiumProvider), isTrue);
    });

    test('store errors are shown in Turkish', () async {
      final billing = FakeBilling()..autoResult = StorePurchaseStatus.error;
      final c = await makeContainer(billing: billing);
      await c.read(premiumControllerProvider.notifier).buy(PremiumPlan.yearly);
      await pumpEventQueue();
      expect(c.read(premiumControllerProvider).error, startsWith('Satın alma tamamlanamadı'));
      expect(c.read(premiumProvider), isFalse);
    });

    test('with a server, the verified entitlement wins', () async {
      final expires = now.add(const Duration(days: 365));
      final backend = FakeBackend(
        ServerEntitlement(
          premium: true,
          status: 'active',
          productId: 'lingora_premium_yearly',
          expiresAt: expires,
        ),
      );
      final c = await makeContainer(billing: FakeBilling(), backend: backend);
      await c.read(premiumControllerProvider.notifier).buy(PremiumPlan.yearly);
      await pumpEventQueue();
      final s = c.read(premiumControllerProvider);
      expect(backend.verified, ['tok-lingora_premium_yearly']);
      expect(s.source, PremiumSource.server);
      expect(s.expiresAt, expires);
      expect(c.read(premiumProvider), isTrue);

      // Cancelled/refunded on the server: Premium ends and the cache is cleared.
      backend.server.add(const ServerEntitlement(premium: false, status: 'expired'));
      await pumpEventQueue();
      expect(c.read(premiumProvider), isFalse);
      expect(c.read(prefsProvider).getString('premium.cache'), isNull);
    });

    test('parses the verifyPurchase output', () {
      final e = ServerEntitlement.fromJson({
        'active': true,
        'productId': 'lingora_premium_yearly',
        'expiresAt': now.add(const Duration(days: 365)).millisecondsSinceEpoch,
      });
      expect(e.premium, isTrue);
      expect(e.status, 'active');
      expect(e.activeAt(now), isTrue);
      expect(e.activeAt(now.add(const Duration(days: 400))), isFalse);
      expect(ServerEntitlement.fromJson({'active': false}).activeAt(now), isFalse);
    });

    test('a token bound to another account is refused', () async {
      final backend = FakeBackend(const ServerEntitlement(premium: true, status: 'active'))
        ..error = const EntitlementRejected('already-exists');
      final c = await makeContainer(billing: FakeBilling(), backend: backend);
      await c.read(premiumControllerProvider.notifier).buy(PremiumPlan.monthly);
      await pumpEventQueue();
      expect(c.read(premiumProvider), isFalse);
      expect(c.read(premiumControllerProvider).error, contains('başka bir Dilbaz hesabına'));
    });

    test('server unreachable or not ready: the store is trusted for now', () async {
      final backend = FakeBackend(const ServerEntitlement(premium: false, status: 'invalid'))
        ..error = Exception('unimplemented');
      final c = await makeContainer(billing: FakeBilling(), backend: backend);
      await c.read(premiumControllerProvider.notifier).buy(PremiumPlan.monthly);
      await pumpEventQueue();
      expect(c.read(premiumProvider), isTrue);
      expect(c.read(premiumControllerProvider).source, PremiumSource.store);
    });

    test('a purchase the server rejects does not unlock', () async {
      final backend = FakeBackend(const ServerEntitlement(premium: false, status: 'invalid'));
      final c = await makeContainer(billing: FakeBilling(), backend: backend);
      await c.read(premiumControllerProvider.notifier).buy(PremiumPlan.monthly);
      await pumpEventQueue();
      expect(c.read(premiumProvider), isFalse);
      expect(c.read(premiumControllerProvider).error, contains('doğrulanamadı'));
    });

    test('server entitlement from Firestore unlocks on a new device', () async {
      final backend = FakeBackend(const ServerEntitlement(premium: false, status: 'invalid'));
      final c = await makeContainer(billing: FakeBilling(), backend: backend);
      backend.server.add(
        ServerEntitlement(premium: true, status: 'active', expiresAt: now.add(const Duration(days: 20))),
      );
      await pumpEventQueue();
      expect(c.read(premiumProvider), isTrue);
    });

    test('mock exam quota: one free per day, unlimited with Premium', () async {
      final c = await makeContainer(billing: FakeBilling());
      expect(c.read(mockExamQuotaProvider), 0);
      c.read(mockExamQuotaProvider.notifier).recordStart();
      expect(c.read(mockExamQuotaProvider), 1);
      expect(c.read(prefsProvider).getString('premium.mock_quota'), '2026-11-10:1');
      final tomorrow = await makeContainer(
        billing: FakeBilling(),
        prefs: {'premium.mock_quota': '2026-11-9:1'},
      );
      expect(tomorrow.read(mockExamQuotaProvider), 0);
    });
  });

  group('paywall', () {
    testWidgets('shows free vs Premium, store prices and the yearly saving', (tester) async {
      await tester.pumpWidget(app(await widgetOverrides(tester, FakeBilling()), const PaywallScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Her zaman ücretsiz'), findsOneWidget);
      for (final f in PremiumFeature.values) {
        expect(find.text(f.title), findsOneWidget);
      }
      expect(find.text('₺100,00 / ay'), findsOneWidget);
      expect(find.text('₺600,00 / yıl'), findsOneWidget);
      expect(find.text('%50 tasarruf'), findsOneWidget);
      expect(find.text('Yıllık · ₺600,00'), findsOneWidget);
      expect(find.text('Satın alımları geri yükle'), findsOneWidget);
      expect(find.textContaining('iptal edebilirsin'), findsOneWidget);
    });

    testWidgets('store unavailable: honest notice, buying disabled', (tester) async {
      await tester.pumpWidget(
        app(await widgetOverrides(tester, FakeBilling(available: false)), const PaywallScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('şu an kullanılamıyor'), findsOneWidget);
      expect(find.text('₺100,00 / ay'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('paywall-buy')));
      await tester.pumpAndSettle();
      expect(find.text("Premium'a geç"), findsOneWidget);
    });

    testWidgets('buying the monthly plan unlocks and closes the paywall', (tester) async {
      final billing = FakeBilling();
      await tester.pumpWidget(
        app(
          await widgetOverrides(tester, billing),
          Consumer(
            builder: (context, ref, _) => Column(
              children: [
                Text(ref.watch(premiumProvider) ? 'PREMIUM' : 'FREE'),
                TextButton(
                  onPressed: () => requirePremium(context, ref, PremiumFeature.errorAnalytics),
                  child: const Text('open'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('FREE'), findsOneWidget);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.textContaining('“Detaylı hata analizi” Premium ile açılır'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plan-monthly')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aylık · ₺100,00'));
      await tester.pumpAndSettle();
      expect(billing.bought, ['lingora_premium_monthly']);
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.text('PREMIUM'), findsOneWidget);
      expect(find.textContaining('Premium açıldı'), findsOneWidget);
    });

    testWidgets('restore brings back an owned subscription', (tester) async {
      final billing = FakeBilling()..owned.add('lingora_premium_yearly');
      final overrides = await widgetOverrides(tester, billing);
      await tester.pumpWidget(app(overrides, const PaywallScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Satın alımları geri yükle'));
      await tester.pump();
      await tester.pump(restoreSettle);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      expect(container.read(premiumProvider), isTrue);
    });

    testWidgets('restore with nothing to restore says so', (tester) async {
      await tester.pumpWidget(app(await widgetOverrides(tester, FakeBilling()), const PaywallScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Satın alımları geri yükle'));
      await tester.pump();
      await tester.pump(restoreSettle);
      await tester.pumpAndSettle();
      expect(find.textContaining('geri yüklenecek aktif abonelik bulunamadı'), findsOneWidget);
    });

    testWidgets('pending payment is explained', (tester) async {
      final billing = FakeBilling()..autoResult = StorePurchaseStatus.pending;
      await tester.pumpWidget(app(await widgetOverrides(tester, billing), const PaywallScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yıllık · ₺600,00'));
      await tester.pumpAndSettle();
      expect(find.textContaining('onay bekliyor'), findsOneWidget);
      expect(find.byType(PaywallScreen), findsOneWidget);
    });

    testWidgets('Premium users see their active subscription', (tester) async {
      await tester.pumpWidget(
        app(await widgetOverrides(tester, FakeBilling(), dev: true), const PaywallScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Premium aktif'), findsOneWidget);
      expect(find.textContaining('aboneliğin aktif'), findsOneWidget);
      expect(find.byKey(const ValueKey('paywall-buy')), findsNothing);
    });
  });

  group('gating', () {
    final scenario = scenarios.first;

    testWidgets('demo conversation (no server) stays free', (tester) async {
      final overrides = await widgetOverrides(tester, FakeBilling());
      await tester.pumpWidget(app(overrides, const ConversationHomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('PREMIUM'), findsNothing);
      await tester.tap(find.text(scenario.title));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.byType(ConversationScreen), findsOneWidget);
    });

    testWidgets('live AI conversation opens the paywall; demo is offered', (tester) async {
      final overrides = [
        ...await widgetOverrides(tester, FakeBilling()),
        conversationServiceProvider.overrideWithValue(LiveFake()),
      ];
      await tester.pumpWidget(app(overrides, const ConversationHomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('PREMIUM'), findsWidgets);
      await tester.tap(find.text(scenario.title));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text(PremiumFeature.aiConversation.title), findsOneWidget);

      await tester.tap(find.text('Ücretsiz demo ile dene'));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.byType(ConversationScreen)));
      expect(container.read(conversationServiceProvider), isA<DemoConversationService>());
    });

    testWidgets('closing the paywall opens nothing', (tester) async {
      final overrides = [
        ...await widgetOverrides(tester, FakeBilling()),
        conversationServiceProvider.overrideWithValue(LiveFake()),
      ];
      await tester.pumpWidget(app(overrides, const ConversationHomeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text(scenario.title));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.byType(ConversationScreen), findsNothing);
    });

    testWidgets('Premium users talk to the live AI directly', (tester) async {
      final overrides = [
        ...await widgetOverrides(tester, FakeBilling(), dev: true),
        conversationServiceProvider.overrideWithValue(LiveFake()),
      ];
      await tester.pumpWidget(app(overrides, const ConversationHomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('PREMIUM'), findsNothing);
      await tester.tap(find.text(scenario.title));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsNothing);
      final container = ProviderScope.containerOf(tester.element(find.byType(ConversationScreen)));
      expect(container.read(conversationServiceProvider), isA<LiveFake>());
    });

    testWidgets('first mock exam of the day is free, the second needs Premium', (tester) async {
      final exam = Exam.fromJson(
        jsonDecode(File('assets/exams/yds.json').readAsStringSync()) as Map<String, dynamic>,
      );
      final overrides = [
        ...await widgetOverrides(tester, FakeBilling()),
        examProvider(exam.id).overrideWith((ref) async => exam),
      ];
      await tester.pumpWidget(app(overrides, ExamHomeScreen(examId: exam.id)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Bugün 1 ücretsiz deneme'), findsOneWidget);
      await tester.tap(find.text('Mini deneme başlat'));
      await tester.pumpAndSettle();
      expect(find.byType(ExamSessionScreen), findsOneWidget);
      expect(find.byType(PaywallScreen), findsNothing);

      // Leave without finishing.
      Navigator.of(tester.element(find.byType(ExamSessionScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.textContaining('ücretsiz denemeni kullandın'), findsOneWidget);
      await tester.tap(find.text('Mini deneme başlat'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text(PremiumFeature.unlimitedMockExams.title), findsOneWidget);

      // Buying Premium continues straight into the exam.
      await tester.tap(find.text('Yıllık · ₺600,00'));
      await tester.pumpAndSettle();
      expect(find.byType(ExamSessionScreen), findsOneWidget);
    });
  });
}
