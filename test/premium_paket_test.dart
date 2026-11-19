// Premium paketi: "Neden yanlış?" günlük sınırı, 2 kat altın, aylık seri
// dondurma, paywall gösterim sıklığı ve Premium'a özel Mağaza ürünleri.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/app_settings.dart';
import 'package:lingora/data/gold_wallet.dart';
import 'package:lingora/data/option_glosses.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/shop_catalog.dart';
import 'package:lingora/models/course.dart';
import 'package:lingora/screens/lesson_screen.dart';
import 'package:lingora/screens/paywall_screen.dart';
import 'package:lingora/services/billing/entitlement_backend.dart';
import 'package:lingora/services/billing/premium.dart';
import 'package:lingora/services/billing/premium_perks.dart';
import 'package:lingora/services/growth/remote_flags.dart';
import 'package:lingora/services/notifications.dart';
import 'package:lingora/services/speech.dart';
import 'package:lingora/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeNotifications, FakeSpeech;

/// The test clock; tests move it.
var _now = DateTime(2026, 11, 17, 12);

Future<ProviderContainer> _container({bool premium = false, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(p),
      clockProvider.overrideWithValue(() => _now),
      premiumDevOverrideProvider.overrideWithValue(premium),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

const _choice = Exercise(
  type: ExerciseType.choice,
  question: 'Farmers depend on an ancient ---- system that carries water to their fields.',
  options: ['emission', 'archive', 'irrigation', 'expedition', 'pottery'],
  answerIndex: 2,
  explanation: 'Su taşıyan sistem sulama sistemidir.',
);

const _gloss = {
  'tr': ['salım, yayım', 'arşiv', 'sulama', 'keşif gezisi', 'çömlekçilik'],
  'why': [
    'Olmaz: salım su taşımaz.',
    'Olmaz: arşiv belge saklar.',
    'Doğru: tarlaya su taşıyan sistem sulamadır.',
    'Olmaz: keşif gezisi bir sistem değildir.',
    'Olmaz: çömlek suyla taşımaz.',
  ],
};

void main() {
  setUp(() => _now = DateTime(2026, 11, 17, 12));

  group('"Neden yanlış?" günlük sınırı', () {
    test('ücretsiz: günde 3 farklı soru, aynı soru tekrar sayılmaz, ertesi gün yenilenir', () async {
      final c = await _container();
      final q = c.read(whyWrongQuotaProvider.notifier);
      expect(q.claim('a'), isTrue);
      expect(q.claim('a'), isTrue, reason: 'aynı soru ikinci kez hak harcamaz');
      expect(q.claim('b'), isTrue);
      expect(q.claim('c'), isTrue);
      expect(q.leftToday, 0);
      expect(q.claim('d'), isFalse);
      expect(q.claim('e'), isFalse);
      expect(q.claim('d'), isFalse, reason: 'kilitli soru iki kez sayılmaz');
      expect(q.isUnlocked('a'), isTrue);
      expect(q.isUnlocked('d'), isFalse);
      expect(q.week(), (wrong: 5, locked: 2));
      expect(personalLine(q.week()), "Bu hafta 5 yanlışın var; 2 tanesinin açıklaması Premium'da.");

      _now = _now.add(const Duration(days: 1));
      expect(q.leftToday, freeWhyWrongPerDay);
      expect(q.claim('d'), isTrue);
      // The week still counts yesterday.
      expect(q.week(), (wrong: 6, locked: 2));

      // Kept on the device.
      final again = await _container(
        prefs: {'premium.why_wrong_v1': c.read(prefsProvider).getString('premium.why_wrong_v1')!},
      );
      expect(again.read(whyWrongQuotaProvider.notifier).isUnlocked('d'), isTrue);
    });

    test('bir haftadan eski günler sayılmaz', () async {
      final c = await _container(
        prefs: {
          'premium.why_wrong_v1': jsonEncode({
            '2026-11-01': {
              'shown': ['x'],
              'locked': ['y', 'z'],
            },
            '2026-11-16': {
              'shown': ['a'],
              'locked': [],
            },
          }),
        },
      );
      expect(c.read(whyWrongQuotaProvider.notifier).week(), (wrong: 1, locked: 0));
      expect(personalLine((wrong: 1, locked: 0)), isNull);
    });

    test('Premium: sınır yok', () async {
      final c = await _container(premium: true);
      final q = c.read(whyWrongQuotaProvider.notifier);
      for (var i = 0; i < 20; i++) {
        expect(q.claim('q$i'), isTrue);
      }
      expect(q.isUnlocked('hiç-görülmemiş'), isTrue);
      expect(q.week().locked, 0);
    });
  });

  group('2 kat altın', () {
    test('GoldWallet.earn Premium ile iki katı verir, aynı ödül iki kez verilmez', () async {
      final free = await _container();
      expect(free.read(goldWalletProvider).earn(20, GoldReason.rewardedAd, onceKey: 'ad:1'), isTrue);
      expect(free.read(goldBalanceProvider), 20);

      final c = await _container(premium: true);
      final w = c.read(goldWalletProvider);
      expect(w.earn(20, GoldReason.rewardedAd, onceKey: 'ad:1'), isTrue);
      expect(c.read(goldBalanceProvider), 40);
      expect(w.earn(20, GoldReason.rewardedAd, onceKey: 'ad:1'), isFalse);
      expect(c.read(goldBalanceProvider), 40, reason: 'aynı ödül ikinci kez gelmez');
      expect(w.earn(5, GoldReason.other), isTrue);
      expect(c.read(goldBalanceProvider), 50);
    });

    test('ders ödülleri Premium ile ikiye katlanır; günlük hedef ödülü bir kez', () async {
      final c = await _container(premium: true);
      final n = c.read(progressProvider.notifier);
      final r = n.completeNode('u1_l1', xp: 20, correct: 5, answered: 5, perfect: true);
      // Lesson 5 + perfect 3 + daily goal 10 (the 20 XP goal reached) = 18, doubled.
      final base = goldPerLesson + goldPerfectBonus + goldDailyGoal;
      expect(r.gold.last, (GoldReason.premium, base));
      expect(r.goldTotal, base * 2);
      expect(c.read(goldBalanceProvider), base * 2);
      final r2 = n.completeNode('u1_l2', xp: 10, correct: 5, answered: 5);
      expect(r2.gold.where((g) => g.$1 == GoldReason.dailyGoal), isEmpty);
      expect(r2.goldTotal, goldPerLesson * 2);
      expect(c.read(goldBalanceProvider), base * 2 + goldPerLesson * 2);
    });

    test('ücretsiz kullanıcıda bonus satırı yok', () async {
      final c = await _container();
      final r = c.read(progressProvider.notifier).completeNode('u1_l1', xp: 5, correct: 3, answered: 3);
      expect(r.gold.any((g) => g.$1 == GoldReason.premium), isFalse);
      expect(r.goldTotal, goldPerLesson);
    });
  });

  group('aylık seri dondurma', () {
    test('Premium: ayda 2 dondurma bir kez, stok en fazla 4', () async {
      final c = await _container(premium: true);
      Wallet wallet() => c.read(progressProvider).wallet;
      final ref = c.read(_refProvider);
      expect(grantMonthlyFreezes(ref), 2);
      expect(wallet().freezes, 2);
      expect(wallet().once.containsKey('pfz:2026-11'), isTrue);
      expect(grantMonthlyFreezes(ref), 0, reason: 'aynı ay ikinci kez yok');
      expect(wallet().freezes, 2);

      _now = DateTime(2026, 12, 2);
      expect(grantMonthlyFreezes(ref), 2);
      expect(wallet().freezes, premiumMaxFreezes);
      _now = DateTime(2027, 1, 3);
      expect(grantMonthlyFreezes(ref), 0, reason: 'stok dolu');
      expect(wallet().freezes, premiumMaxFreezes);
    });

    test('ücretsiz kullanıcıya dondurma eklenmez', () async {
      final c = await _container();
      expect(grantMonthlyFreezes(c.read(_refProvider)), 0);
      expect(c.read(progressProvider).wallet.freezes, 0);
    });

    test('Premium açılınca kendiliğinden eklenir', () async {
      final c = await _container(premium: true);
      c.listen(premiumPerksSyncProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(c.read(progressProvider).wallet.freezes, premiumFreezesPerMonth);
    });
  });

  group('paywall gösterim sıklığı', () {
    test('günde en fazla bir kendiliğinden paywall', () async {
      final c = await _container();
      final pacer = c.read(paywallPacerProvider);
      expect(pacer.canAutoShow, isTrue);
      expect(pacer.takeAuto(), isTrue);
      expect(pacer.canAutoShow, isFalse);
      expect(pacer.takeAuto(), isFalse);
      _now = _now.add(const Duration(days: 1));
      expect(pacer.takeAuto(), isTrue);
    });

    test('kapatılırsa 3 gün kendiliğinden gelmez, yumuşak öneri de gizlenir', () async {
      final c = await _container();
      final pacer = c.read(paywallPacerProvider);
      pacer.recordClosed();
      for (final days in [1, 2]) {
        _now = DateTime(2026, 11, 17 + days, 12);
        expect(pacer.canAutoShow, isFalse, reason: 'gün $days');
        expect(pacer.canOffer, isFalse, reason: 'gün $days');
      }
      _now = DateTime(2026, 11, 20, 12);
      expect(pacer.canAutoShow, isTrue);
      expect(pacer.canOffer, isTrue);
    });

    test('Premium ve Çocuk modunda hiç yok', () async {
      final p = await _container(premium: true);
      expect(p.read(paywallPacerProvider).canAutoShow, isFalse);
      expect(p.read(paywallPacerProvider).canOffer, isFalse);
      final kid = await _container();
      kid.read(appSettingsProvider.notifier).setMode(AppMode.kid);
      expect(kid.read(paywallPacerProvider).canAutoShow, isFalse);
      expect(kid.read(paywallPacerProvider).canOffer, isFalse);
    });

    test('deneme vurgusu yalnızca Remote Config ve Play izin verince', () {
      const s = PremiumState();
      expect(trialOfferDaysOf(const RemoteFlags(trialDays: 7), s), 7);
      expect(trialOfferDaysOf(const RemoteFlags(trialDays: 0), s), 0);
      const noTrial = PremiumState(
        products: [StoreProduct(id: 'lingora_premium_yearly', title: 'Y', price: '₺600', rawPrice: 600)],
      );
      expect(trialOfferDaysOf(const RemoteFlags(trialDays: 7), noTrial), 0);
    });
  });

  group("Premium'a özel ürünler", () {
    final premiumItems = shopItems.where((i) => i.premiumOnly).toList();

    test('katalogda avatar ve çerçeve var, kimlikler kurallara uyuyor, haftanın ürünü olmuyor', () {
      expect(premiumItems.map((i) => i.category).toSet(), {ShopCategory.avatar, ShopCategory.frame});
      for (final i in premiumItems) {
        expect(RegExp(r'^(av|fr|mx|th)_[a-z0-9_]{1,20}$').hasMatch(i.id), isTrue, reason: i.id);
        expect(i.free, isFalse, reason: 'Premium ürünü herkese açık değil');
        expect(i.rarity, Rarity.premium);
        expect(i.rarity.label, 'Premium');
      }
      for (var w = 0; w < 60; w++) {
        final day = DateTime(2026, 1, 5).add(Duration(days: 7 * w));
        expect(featuredItems(day).where((i) => i.premiumOnly), isEmpty);
        expect(featuredItems(day, kid: true).where((i) => i.premiumOnly), isEmpty);
      }
    });

    test('ücretsiz kullanıcı alamaz, Premium altınsız alır ve giyer', () async {
      final item = premiumItems.first;
      final free = await _container();
      final fw = free.read(goldWalletProvider);
      fw.earn(5000, GoldReason.other);
      expect(fw.buy(item), BuyResult.needsPremium);
      expect(fw.claimPremium(item, premium: false), BuyResult.needsPremium);
      expect(ownsItem(free.read(walletProvider), item), isFalse);
      expect(fw.equip(item), isFalse);
      expect(free.read(goldBalanceProvider), 5000);

      final c = await _container(premium: true);
      final w = c.read(goldWalletProvider);
      expect(w.claimPremium(item, premium: true), BuyResult.bought);
      expect(w.claimPremium(item, premium: true), BuyResult.owned);
      expect(ownsItem(c.read(walletProvider), item), isTrue);
      expect(c.read(goldBalanceProvider), 0, reason: 'altın harcanmaz');
      expect(w.equip(item), isTrue);
    });
  });

  group('paywall', () {
    testWidgets('yeni özellik listesi ve kişisel cümle', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'premium.why_wrong_v1': jsonEncode({
          '2026-11-15': {
            'shown': ['a', 'b', 'c'],
            'locked': ['d', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l'],
          },
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prefsProvider.overrideWithValue(prefs),
            clockProvider.overrideWithValue(() => _now),
            premiumDevOverrideProvider.overrideWithValue(false),
          ],
          child: const MaterialApp(home: PaywallScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("Bu hafta 12 yanlışın var; 9 tanesinin açıklaması Premium'da."), findsOneWidget);
      for (final title in [
        'Yapay zekâ sohbet partneri',
        '"Neden yanlış?" açıklamaları',
        'Sınırsız deneme',
        'Detaylı hata analizi ve tahmini puan',
        'Ayda 2 seri dondurma',
        '2 kat altın',
        'Premium avatarlar',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
    });
  });

  group('derste "Neden yanlış?"', () {
    Future<ProviderContainer> pump(WidgetTester tester, {bool premium = false, int usedToday = 3}) async {
      SharedPreferences.setMockInitialValues({
        'progress_v1': jsonEncode(const Progress(onboarded: true, remindersEnabled: false).toJson()),
        'premium.why_wrong_v1': jsonEncode({
          '2026-11-17': {
            'shown': [for (var i = 0; i < usedToday; i++) 'q$i'],
            'locked': [],
          },
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          speechProvider.overrideWithValue(FakeSpeech()),
          notificationServiceProvider.overrideWithValue(FakeNotifications()),
          clockProvider.overrideWithValue(() => _now),
          premiumDevOverrideProvider.overrideWithValue(premium),
          optionGlossesProvider.overrideWith((ref) async => const OptionGlosses({'ys1u1l1#0': _gloss})),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildTheme(mode: AppMode.adult, brightness: Brightness.light),
            home: LessonScreen(
              nodeId: 'ys1u1l1',
              title: 'Test',
              items: const [(key: 'ys1u1l1#0', ex: _choice)],
              color: Brand.primary,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    Future<void> answerWrong(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('choice-option-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('check')));
      await tester.pumpAndSettle();
    }

    testWidgets('hak varken açıklama görünür ve bir hak harcanır', (tester) async {
      final c = await pump(tester, usedToday: 2);
      await answerWrong(tester);
      expect(find.byKey(const Key('option-gloss-toggle')), findsOneWidget);
      expect(find.text('salım, yayım'), findsOneWidget);
      expect(find.byKey(const Key('why-wrong-locked')), findsNothing);
      expect(c.read(whyWrongQuotaProvider.notifier).leftToday, 0);
    });

    testWidgets(
      'hak bitince temel neden, bulanık önizleme ve deneme vurgulu kart; paywall kendiliğinden açılmaz',
      (tester) async {
        final c = await pump(tester);
        await answerWrong(tester);
        expect(find.byKey(const Key('why-wrong-locked')), findsOneWidget);
        expect(
          find.byKey(const Key('why-wrong-basic')),
          findsOneWidget,
          reason: 'öğrenme döngüsü tamamlanır',
        );
        expect(find.text('salım, yayım'), findsNothing, reason: 'şıkların Türkçesi Premium');
        expect(find.byKey(const Key('option-gloss-why')), findsNothing);
        expect(find.textContaining("Premium'da · 7 gün ücretsiz dene"), findsOneWidget);
        expect(find.text('7 GÜN ÜCRETSİZ DENE'), findsOneWidget);
        // Answering and reading are never interrupted.
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.byType(PaywallScreen), findsNothing);
        expect(c.read(paywallPacerProvider).canAutoShow, isTrue);
      },
    );

    testWidgets('Premium alınınca kilitli açıklama hemen açılır', (tester) async {
      final c = await pump(tester);
      await answerWrong(tester);
      expect(find.byKey(const Key('why-wrong-locked')), findsOneWidget);
      c
          .read(premiumControllerProvider.notifier)
          .applyServer(
            ServerEntitlement(premium: true, status: 'active', expiresAt: _now.add(const Duration(days: 30))),
          );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('why-wrong-locked')), findsNothing);
      expect(find.text('salım, yayım'), findsOneWidget);
      // No paywall any more: the learner just bought Premium.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsNothing);
    });

    testWidgets('Premium: sınır yok, kart yok', (tester) async {
      await pump(tester, premium: true, usedToday: 10);
      await answerWrong(tester);
      expect(find.text('salım, yayım'), findsOneWidget);
      expect(find.byKey(const Key('why-wrong-locked')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsNothing);
    });
  });
}

/// A provider whose `ref` the tests hand to plain functions taking a [Ref].
final _refProvider = Provider<Ref>((ref) => ref);
