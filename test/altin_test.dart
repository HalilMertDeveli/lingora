import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/data/gold_wallet.dart';
import 'package:lingora/data/progress.dart';
import 'package:lingora/data/quests.dart';
import 'package:lingora/data/shop_catalog.dart';
import 'package:lingora/models/study_plan.dart';
import 'package:lingora/screens/friend_profile_screen.dart';
import 'package:lingora/screens/friends_screen.dart';
import 'package:lingora/screens/league_screen.dart';
import 'package:lingora/screens/lesson_result_screen.dart';
import 'package:lingora/screens/shop_screen.dart';
import 'package:lingora/services/firebase/firebase_providers.dart';
import 'package:lingora/services/firebase/progress_merge.dart';
import 'package:lingora/services/friends.dart' show friendsApiProvider;
import 'package:lingora/services/profile.dart';
import 'package:lingora/services/showcase.dart';
import 'package:lingora/ui/gold_coin.dart';
import 'package:lingora/ui/mascot.dart';
import 'package:lingora/ui/my_avatar.dart';
import 'package:lingora/ui/shop_visuals.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'friends_test.dart' show FakeFriendsApi, friend;
import 'profile_test.dart' show FakeProfileApi, photoA;

/// Tuesday noon.
final _now = DateTime(2026, 11, 17, 12);

class FakeShowcaseApi implements ShowcaseApi {
  final saved = <(String, Showcase)>[];

  @override
  Future<void> save(String uid, Showcase showcase) async => saved.add((uid, showcase));
}

Future<ProviderContainer> _container({
  Progress? progress,
  DateTime? at,
  List<Override> extra = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    'wallet_device_v1': 'dtest',
    if (progress != null) 'progress_v1': jsonEncode(progress.toJson()),
  });
  final prefs = await SharedPreferences.getInstance();
  var clock = at ?? _now;
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => clock),
      ...extra,
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// A wallet holding [gold] earned on device "dtest".
Wallet rich(int gold) => Wallet(earned: {'dtest': gold});

void main() {
  test('Çocuk modu Mağazası: Çaycı Dayı sekmesi yok, yalnızca Pofuduk', () {
    expect(ShopCategory.tabs(kid: true), isNot(contains(ShopCategory.mascot)));
    expect(ShopCategory.tabs(kid: true), contains(ShopCategory.pofuduk));
    expect(ShopCategory.tabs(kid: false), isNot(contains(ShopCategory.pofuduk)));
    expect(ShopCategory.tabs(kid: false), contains(ShopCategory.mascot));
  });

  group('earning', () {
    test('a lesson earns gold; a perfect one more; chests nothing', () async {
      final c = await _container();
      final n = c.read(progressProvider.notifier);
      final r1 = n.completeNode('a', xp: 5, correct: 5, answered: 6);
      expect(r1.gold, [(GoldReason.lesson, goldPerLesson)]);
      final r2 = n.completeNode('b', xp: 5, correct: 6, answered: 6, perfect: true);
      expect(r2.goldTotal, goldPerLesson + goldPerfectBonus);
      final r3 = n.completeNode('chest', xp: 5);
      expect(r3.goldTotal, 0);
      expect(c.read(goldBalanceProvider), 2 * goldPerLesson + goldPerfectBonus);
    });

    test('the daily goal pays once a day', () async {
      final c = await _container(progress: const Progress(dailyGoal: 10, onboarded: true));
      final n = c.read(progressProvider.notifier);
      expect(n.completeNode('a', xp: 6, answered: 1).gold.map((g) => g.$1), [GoldReason.lesson]);
      final r = n.completeNode('b', xp: 6, answered: 1);
      expect(r.gold, contains((GoldReason.dailyGoal, goldDailyGoal)));
      expect(n.completeNode('c', xp: 6, answered: 1).gold.map((g) => g.$1), [GoldReason.lesson]);
    });

    test('a streak milestone pays once', () async {
      final yesterday = dayKey(_now.subtract(const Duration(days: 1)));
      final c = await _container(progress: Progress(streak: 2, lastActiveDay: yesterday, dailyGoal: 500));
      final n = c.read(progressProvider.notifier);
      final r = n.completeNode('a', xp: 5, answered: 1);
      expect(r.streak, 3);
      expect(r.gold, contains((GoldReason.streak, goldStreakMilestones[3])));
      // A second lesson the same day: no second milestone.
      expect(n.completeNode('b', xp: 5, answered: 1).gold, [(GoldReason.lesson, goldPerLesson)]);
    });

    test('claiming a quest pays its gold', () async {
      final c = await _container();
      final quest = questsForDay(_now).first;
      final n = c.read(progressProvider.notifier);
      // Make the quest complete.
      for (var i = 0; i < 10 && !quest.isComplete(c.read(progressProvider), _now); i++) {
        n.completeNode(
          'n$i',
          xp: 20,
          correct: 6,
          answered: 6,
          perfect: true,
          stats: {for (final m in QuestMetric.values) m: 6},
        );
      }
      final before = c.read(goldBalanceProvider);
      expect(n.claimQuest(quest), isTrue);
      expect(c.read(goldBalanceProvider), before + quest.rewardGold);
      expect(n.claimQuest(quest), isFalse);
      expect(c.read(goldBalanceProvider), before + quest.rewardGold);
    });

    test('a finished league week pays once', () async {
      final lastWeek = dayKey(weekStartOf(_now).subtract(const Duration(days: 7)));
      final c = await _container(
        progress: Progress(leagueWeek: lastWeek, xpByDay: {lastWeek: 400}, onboarded: true),
      );
      final n = c.read(progressProvider.notifier)..settleLeague();
      final gold = c.read(goldBalanceProvider);
      expect(gold, greaterThanOrEqualTo(15));
      expect(c.read(progressProvider).wallet.once.keys, contains('league:$lastWeek'));
      n.settleLeague();
      expect(c.read(goldBalanceProvider), gold);
    });

    test('no league gold for a week without XP', () {
      expect(goldForLeague(promoted: false, demoted: false, rank: 50, xp: 0), 0);
      expect(goldForLeague(promoted: true, demoted: false, rank: 1, xp: 300), 80);
    });

    test('GoldWallet.earn is the API for other features, with an optional once key', () async {
      final c = await _container();
      final w = c.read(goldWalletProvider);
      expect(w.earn(20, GoldReason.rewardedAd, onceKey: 'ad:2026-11-17:1'), isTrue);
      expect(w.earn(20, GoldReason.rewardedAd, onceKey: 'ad:2026-11-17:1'), isFalse);
      expect(w.earn(0, GoldReason.other), isFalse);
      expect(w.earn(5, GoldReason.other), isTrue);
      expect(w.balance, 25);
    });

    test('a normal week buys one or two items', () {
      // 3 lessons a day (one perfect), the daily goal, two quests (~20).
      const perDay = 3 * goldPerLesson + goldPerfectBonus + goldDailyGoal + 20;
      final week = perDay * 7 + goldForLeague(promoted: false, demoted: false, rank: 20, xp: 300);
      final prices = [
        for (final i in shopItems)
          if (!i.free && !i.consumable) i.price,
      ]..sort();
      // About 370 gold: one or two typical items (the median price).
      final median = prices[prices.length ~/ 2];
      expect(week / median, inInclusiveRange(1, 2));
      expect(week, lessThan(prices.last * 2), reason: "the dearest item takes more than a week");
    });
  });

  group('spending', () {
    test('not enough gold: nothing changes', () async {
      final c = await _container(progress: Progress(wallet: rich(100)));
      final item = shopItem('av_tilki')!;
      expect(c.read(goldWalletProvider).buy(item), BuyResult.insufficient);
      expect(c.read(goldBalanceProvider), 100);
      expect(c.read(walletProvider).owns(item.id), isFalse);
    });

    test('buying takes the gold and owns the item; wearing is a choice', () async {
      final c = await _container(progress: Progress(wallet: rich(400)));
      final item = shopItem('av_tilki')!;
      final w = c.read(goldWalletProvider);
      expect(w.buy(item), BuyResult.bought);
      expect(c.read(goldBalanceProvider), 400 - priceOf(item, _now));
      expect(c.read(walletProvider).owns(item.id), isTrue);
      expect(equippedIn(c.read(walletProvider), WalletSlot.avatar), isNull);
      expect(w.equip(item), isTrue);
      expect(equippedIn(c.read(walletProvider), WalletSlot.avatar)?.id, 'av_tilki');
      expect(w.buy(item), BuyResult.owned);
      expect(w.buy(shopItem('av_cay')!), BuyResult.owned, reason: 'free items are owned');
    });

    test('streak freezes stack up to the limit', () async {
      final c = await _container(progress: Progress(wallet: rich(1000)));
      final w = c.read(goldWalletProvider);
      expect(w.buy(streakFreezeItem), BuyResult.bought);
      expect(w.buy(streakFreezeItem), BuyResult.bought);
      expect(w.buy(streakFreezeItem), BuyResult.stockFull);
      expect(c.read(walletProvider).freezes, maxFreezes);
      expect(c.read(goldBalanceProvider), 1000 - 2 * streakFreezeItem.price);
    });

    test('a bought freeze keeps the streak over a missed day and is used up', () async {
      final twoDaysAgo = dayKey(_now.subtract(const Duration(days: 2)));
      final c = await _container(
        progress: Progress(
          streak: 9,
          lastActiveDay: twoDaysAgo,
          wallet: const Wallet(freezeBought: {'dtest': 1}),
        ),
      );
      expect(c.read(progressProvider).streakAt(_now), 9);
      final r = c.read(progressProvider.notifier).completeNode('a', xp: 5, answered: 1);
      expect(r.streak, 10);
      expect(r.freezesUsed, 1);
      expect(c.read(walletProvider).freezes, 0);
    });

    test('two missed days need two freezes; the plan freeze counts as one', () async {
      final threeDaysAgo = dayKey(_now.subtract(const Duration(days: 3)));
      final one = Progress(
        streak: 5,
        lastActiveDay: threeDaysAgo,
        wallet: const Wallet(freezeBought: {'d': 1}),
      );
      expect(one.streakAt(_now), 0);
      expect(one.copyWith(wallet: const Wallet(freezeBought: {'d': 2})).streakAt(_now), 5);
      final plan = one.copyWith(
        studyPlan: const StudyPlan(
          exam: 'yds',
          week: 1,
          weekStart: '2026-11-02',
          dailyMinutes: 20,
          startDay: '2026-11-02',
        ),
      );
      expect(plan.streakCover(_now), (plan: true, bought: 1));
    });
  });

  group('wearing and the showcase', () {
    test('only owned items can be worn; unequip goes back to the default', () async {
      final c = await _container(progress: Progress(wallet: rich(1000)));
      final w = c.read(goldWalletProvider);
      expect(w.equip(shopItem('fr_altin')!), isFalse);
      w.buy(shopItem('fr_altin')!);
      w.equip(shopItem('fr_altin')!);
      w.equip(shopItem('av_kedi')!);
      final wallet = c.read(walletProvider);
      expect(equippedIn(wallet, WalletSlot.frame)?.id, 'fr_altin');
      expect(equippedIn(wallet, WalletSlot.avatar)?.id, 'av_kedi');
      w.unequip(WalletSlot.frame);
      expect(equippedIn(c.read(walletProvider), WalletSlot.frame), isNull);
    });

    test('the showcase holds up to three owned, bought items', () async {
      final c = await _container(progress: Progress(wallet: rich(5000)));
      final w = c.read(goldWalletProvider);
      expect(w.toggleShowcase(shopItem('mx_tac')!), isFalse, reason: 'not owned');
      expect(w.toggleShowcase(shopItem('av_cay')!), isFalse, reason: 'free items are not shown off');
      for (final id in ['mx_tac', 'th_iznik', 'fr_nazar', 'av_roket']) {
        w.buy(shopItem(id)!);
        w.equip(shopItem(id)!);
      }
      expect(w.toggleShowcase(shopItem('mx_tac')!), isTrue);
      expect(w.toggleShowcase(shopItem('th_iznik')!), isTrue);
      expect(w.toggleShowcase(shopItem('fr_nazar')!), isTrue);
      expect(w.toggleShowcase(shopItem('av_roket')!), isFalse, reason: 'full');
      expect(w.toggleShowcase(shopItem('th_iznik')!), isTrue, reason: 'taken out');
      final s = c.read(myShowcaseProvider);
      expect(s.items, ['mx_tac', 'fr_nazar']);
      expect(s.avatar, 'av_roket', reason: 'the last worn avatar');
      expect(s.frame, 'fr_nazar');
    });

    test('showcase map round trip skips unknown items', () {
      const s = Showcase(avatar: 'av_tilki', frame: 'fr_altin', items: ['mx_tac']);
      expect(Showcase.fromMap(s.toMap()), s);
      expect(
        Showcase.fromMap({
          'avatar': 'av_yeni',
          'frame': null,
          'items': ['mx_tac', 'zz', 'th_lokum', 'av_tilki', 'fr_altin'],
        }),
        const Showcase(items: ['mx_tac', 'th_lokum']),
      );
      expect(Showcase.fromMap('x'), isNull);
    });
  });

  group('sync', () {
    test('two phones never lose or double gold', () {
      const a = Wallet(earned: {'p1': 100}, spent: {'p1': 30}, owned: ['av_tilki']);
      const b = Wallet(earned: {'p1': 80, 'p2': 50}, spent: {'p2': 20}, owned: ['fr_altin']);
      final m = mergeWallets(a, b);
      expect(m.balance, 100 + 50 - 30 - 20);
      expect(m.owned, ['av_tilki', 'fr_altin']);
      expect(mergeWallets(b, a).toJson(), m.toJson());
      // Merging again changes nothing.
      expect(mergeWallets(m, b).toJson(), m.toJson());
    });

    test('the look comes from the copy styled last', () {
      const old = Wallet(equipped: {'avatar': 'av_tilki'}, styledAt: 1);
      const fresh = Wallet(equipped: {'avatar': 'av_kedi'}, showcase: ['mx_tac'], styledAt: 2);
      final m = mergeWallets(old, fresh);
      expect(m.equipped['avatar'], 'av_kedi');
      expect(m.showcase, ['mx_tac']);
    });

    test('the wallet travels with the progress merge and JSON', () {
      final local = Progress(
        wallet: const Wallet(earned: {'p1': 40}, once: {'goal:2026-11-17': '2026-11-17'}),
      );
      final remote = Progress(
        wallet: const Wallet(earned: {'p2': 60}, freezeBought: {'p2': 1}),
      );
      final merged = mergeProgress(local, remote, localNewer: true);
      expect(merged.wallet.balance, 100);
      expect(merged.wallet.freezes, 1);
      final back = progressFromFirestore(jsonDecode(jsonEncode(merged.toJson())) as Map<String, dynamic>);
      expect(back.wallet.toJson(), merged.wallet.toJson());
    });

    test('old one-off keys are dropped after two months', () {
      const w = Wallet(once: {'goal:2026-08-01': '2026-08-01', 'goal:2026-11-10': '2026-11-10'});
      expect(w.pruned('2026-11-17').once.keys, ['goal:2026-11-10']);
    });

    test('an account pushes its showcase to profiles; a guest does not', () async {
      final api = FakeShowcaseApi();
      final c = await _container(
        progress: Progress(wallet: rich(500)),
        extra: [
          showcaseApiProvider.overrideWithValue(api),
          showcaseDebounceProvider.overrideWithValue(Duration.zero),
          authStateProvider.overrideWithValue(const AsyncData(AppUser(uid: 'ali', isAnonymous: false))),
        ],
      );
      c.listen(showcaseSyncProvider, (_, _) {});
      c.read(goldWalletProvider)
        ..buy(shopItem('av_tilki')!)
        ..equip(shopItem('av_tilki')!);
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(api.saved.last.$1, 'ali');
      expect(api.saved.last.$2.avatar, 'av_tilki');
      final count = api.saved.length;
      // The same showcase is not written twice.
      c.read(goldWalletProvider).earn(5, GoldReason.other);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(api.saved.length, count);

      final guestApi = FakeShowcaseApi();
      final g = await _container(
        extra: [
          showcaseApiProvider.overrideWithValue(guestApi),
          showcaseDebounceProvider.overrideWithValue(Duration.zero),
          authStateProvider.overrideWithValue(const AsyncData(AppUser(uid: 'g1'))),
        ],
      );
      g.listen(showcaseSyncProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(guestApi.saved, isEmpty);
    });
  });

  group('Mağaza v2', () {
    test('the week\'s featured items are the same all week and change weekly', () {
      final mon = DateTime(2026, 11, 16, 8);
      final sun = DateTime(2026, 11, 22, 23);
      final next = DateTime(2026, 11, 23, 8);
      List<String> ids(DateTime d) => [for (final i in featuredItems(d)) i.id];
      expect(ids(mon), ids(sun));
      expect(ids(mon), hasLength(3));
      expect(ids(mon), isNot(ids(next)));
      for (final i in featuredItems(mon)) {
        expect(i.free || i.consumable, isFalse);
        expect(priceOf(i, mon), (i.price * (1 - featuredDiscount)).round());
      }
      expect([
        for (final i in featuredItems(mon, kid: true)) i.category,
      ], isNot(contains(ShopCategory.mascot)));
    });

    test('a featured item is bought at the discounted price', () async {
      final item = featuredItems(_now).first;
      final c = await _container(progress: Progress(wallet: rich(1000)));
      expect(c.read(goldWalletProvider).buy(item), BuyResult.bought);
      expect(c.read(goldBalanceProvider), 1000 - priceOf(item, _now));
      expect(priceOf(item, _now), lessThan(item.price));
    });

    test('rarity follows price unless set; every item id passes the rules pattern', () {
      expect(shopItem('av_tilki')!.rarity, Rarity.common);
      expect(shopItem('fr_iznik')!.rarity, Rarity.rare);
      expect(shopItem('fr_gokkusagi')!.rarity, Rarity.epic);
      final pattern = RegExp(r'^(av|fr|mx|th|px|fz)_[a-z0-9_]{1,20}$');
      for (final i in shopItems) {
        expect(pattern.hasMatch(i.id), isTrue, reason: i.id);
      }
      expect({for (final i in shopItems) i.id}.length, shopItems.length, reason: 'unique ids');
      expect(itemsIn(ShopCategory.pofuduk), isNotEmpty);
      expect([for (final i in itemsIn(ShopCategory.frame)) i.frame!.motion], contains(FrameMotion.spin));
    });

    test('choosing an avatar shows it instead of the photo; the learner can go back', () async {
      final c = await _container(progress: Progress(wallet: rich(500)));
      final w = c.read(goldWalletProvider);
      expect(prefersAvatar(c.read(walletProvider)), isFalse);
      w.equip(shopItem('av_kedi')!);
      expect(prefersAvatar(c.read(walletProvider)), isTrue);
      expect(c.read(myShowcaseProvider).useAvatar, isTrue);
      w.useAvatarFace(false);
      expect(prefersAvatar(c.read(walletProvider)), isFalse);
      expect(c.read(myShowcaseProvider).useAvatar, isFalse);
      // A frame does not change the choice.
      w.useAvatarFace(true);
      w.buy(shopItem('fr_bakir')!);
      w.equip(shopItem('fr_bakir')!);
      expect(prefersAvatar(c.read(walletProvider)), isTrue);
      expect(Showcase.fromMap(c.read(myShowcaseProvider).toMap())!.useAvatar, isTrue);
    });
  });

  group('screens', () {
    Future<List<Override>> base(Progress p, {AppUser? user, List<Override> extra = const []}) async {
      SharedPreferences.setMockInitialValues({
        'wallet_device_v1': 'dtest',
        'progress_v1': jsonEncode(p.toJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      return [
        prefsProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => _now),
        authStateProvider.overrideWithValue(AsyncData(user)),
        ...extra,
      ];
    }

    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    /// No looping animations (animated frames), so pumpAndSettle settles.
    Widget still(Widget home) => MaterialApp(
      builder: (c, child) =>
          MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: child!),
      home: home,
    );

    testWidgets('the Mağaza: locked, buy, celebrate, use now', (tester) async {
      tall(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: await base(Progress(wallet: rich(200))),
          child: still(const ShopScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(const ValueKey('shop-balance')), matching: find.text('200')),
        findsOne,
      );
      expect(find.byKey(const ValueKey('shop-featured')), findsOne);
      expect(find.byKey(const ValueKey('shop-where-avatar')), findsOne);
      // Too expensive: the button cannot be pressed.
      final lion = find.byKey(const ValueKey('shop-buy-av_aslan'));
      await tester.scrollUntilVisible(lion, 200, scrollable: find.byType(Scrollable).last);
      expect(tester.widget<FilledButton>(lion).onPressed, isNull);
      // Trying the lion on shows it in the live preview.
      await tester.tap(find.byKey(const ValueKey('shop-item-av_aslan')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).last, const Offset(0, 3000));
      await tester.pumpAndSettle();
      expect(find.text('Önizleme: Aslan'), findsOne);
      // Buy the fox: a celebration, then "Hemen kullan".
      final fox = shopItem('av_tilki')!;
      await tester.tap(find.byKey(const ValueKey('shop-buy-av_tilki')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shop-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shop-celebrate')), findsOne);
      await tester.tap(find.byKey(const ValueKey('shop-use-now')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('shop-balance')),
          matching: find.text('${200 - priceOf(fox, _now)}'),
        ),
        findsOne,
      );
      expect(find.byKey(const ValueKey('shop-unequip-av_tilki')), findsOne);
      expect(
        find.descendant(of: find.byKey(const ValueKey('shop-my-avatar')), matching: find.text('🦊')),
        findsOne,
      );
      // "Sahip olduklarım" hides what is not owned.
      await tester.tap(find.byKey(const ValueKey('shop-owned-filter')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shop-item-av_aslan')), findsNothing);
      expect(find.byKey(const ValueKey('shop-item-av_tilki')), findsOne);
      // Wear a free one instead.
      await tester.tap(find.byKey(const ValueKey('shop-use-av_kedi')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shop-use-av_tilki')), findsOne);
      expect(
        find.descendant(of: find.byKey(const ValueKey('shop-my-avatar')), matching: find.text('🐈')),
        findsOne,
      );
    });

    testWidgets('the lesson result shows "+N altın"', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LessonResultScreen(
            reward: LessonReward(
              xp: 10,
              streak: 1,
              streakExtended: false,
              todayXp: 10,
              dailyGoal: 20,
              gold: [(GoldReason.lesson, 5), (GoldReason.perfect, 3)],
            ),
            accuracy: 100,
            duration: Duration(minutes: 2),
            perfect: true,
          ),
        ),
      );
      // The mascot and the tea celebration loop: step time instead of settling.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(GoldGain), findsOne);
      expect(find.text('+8 altın'), findsOne);
      expect(find.text('Ders 5 · Hatasız 3'), findsOne);
    });

    testWidgets('friends see the showcase on the card and the profile', (tester) async {
      tall(tester);
      final api = FakeProfileApi(
        docs: {
          'zeynep': const ProfileData(
            name: 'Zeyno',
            owner: 'zeynep',
            showcase: Showcase(avatar: 'av_baykus', frame: 'fr_altin', items: ['mx_tac', 'th_iznik']),
          ),
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: await base(
            const Progress(),
            user: const AppUser(uid: 'me', isAnonymous: false),
            extra: [
              profileApiProvider.overrideWithValue(api),
              friendsApiProvider.overrideWithValue(FakeFriendsApi(friends: [friend()])),
            ],
          ),
          child: const MaterialApp(home: FriendsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('friend-zeynep'));
      expect(find.descendant(of: card, matching: find.text('🦉')), findsOne);
      expect(
        find.descendant(of: card, matching: find.byKey(const ValueKey('showcase-item-mx_tac'))),
        findsOne,
      );
      await tester.tap(find.text('Zeyno'));
      await tester.pumpAndSettle();
      expect(find.byType(FriendProfileScreen), findsOne);
      expect(find.byKey(const ValueKey('friend-showcase-th_iznik')), findsOne);
    });

    testWidgets('the league row shows the worn avatar and showcase', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: await base(
            const Progress(
              wallet: Wallet(
                owned: ['av_roket', 'mx_tac'],
                equipped: {'avatar': 'av_roket'},
                showcase: ['mx_tac'],
              ),
            ),
          ),
          child: const MaterialApp(home: Scaffold(body: LeagueScreen())),
        ),
      );
      await tester.pumpAndSettle();
      final mine = find.byKey(const ValueKey('league-my-avatar'));
      await tester.scrollUntilVisible(
        mine,
        200,
        scrollable: find
            .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .first,
      );
      expect(find.descendant(of: mine, matching: find.text('🚀')), findsOne);
      expect(find.byKey(const ValueKey('showcase-item-mx_tac')), findsOne);
    });

    testWidgets('MyAvatar: photo by default, the avatar once chosen', (tester) async {
      Future<void> pump(Wallet w) async {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: await base(
              Progress(wallet: w),
              extra: [profileProvider.overrideWith(() => _FixedProfile(ProfileData(photo: photoA)))],
            ),
            child: still(const Scaffold(body: MyAvatar(size: 64))),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pump(const Wallet(equipped: {'avatar': 'av_kedi'}));
      expect(find.byKey(const ValueKey('avatar-photo')), findsOne);
      await pump(const Wallet(equipped: {'avatar': 'av_kedi', 'face': 'avatar'}));
      expect(find.byKey(const ValueKey('avatar-photo')), findsNothing);
      expect(find.text('🐈'), findsOne);
    });

    testWidgets('a friend who chose the avatar shows it instead of the photo', (tester) async {
      tall(tester);
      final api = FakeProfileApi(
        docs: {
          'zeynep': ProfileData(
            name: 'Zeyno',
            photo: photoA,
            owner: 'zeynep',
            showcase: const Showcase(avatar: 'av_ejderha', useAvatar: true),
          ),
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: await base(
            const Progress(),
            user: const AppUser(uid: 'me', isAnonymous: false),
            extra: [
              profileApiProvider.overrideWithValue(api),
              friendsApiProvider.overrideWithValue(FakeFriendsApi(friends: [friend()])),
            ],
          ),
          child: still(const FriendsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('friend-zeynep'));
      expect(find.descendant(of: card, matching: find.text('🐉')), findsOne);
      expect(find.descendant(of: card, matching: find.byKey(const ValueKey('avatar-photo'))), findsNothing);
    });

    testWidgets('Pofuduk wears the bought outfit', (tester) async {
      await tester.pumpWidget(
        still(
          const MascotOutfitScope(
            accessory: null,
            pofuduk: MascotAccessory('👑', 0.5, 0.04, 0.26),
            child: Center(child: Pofuduk(size: 160)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('👑'), findsOne);
    });

    testWidgets('the lesson result shows the learner\'s avatar next to the gold', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: await base(
            const Progress(wallet: Wallet(equipped: {'avatar': 'av_kedi', 'face': 'avatar'})),
          ),
          child: still(
            const LessonResultScreen(
              reward: LessonReward(
                xp: 10,
                streak: 1,
                streakExtended: false,
                todayXp: 10,
                dailyGoal: 20,
                gold: [(GoldReason.lesson, 5)],
              ),
              accuracy: 90,
              duration: Duration(minutes: 2),
              perfect: false,
            ),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.descendant(of: find.byKey(const ValueKey('result-avatar')), matching: find.text('🐈')),
        findsOne,
      );
    });
  });
}

DateTime weekStartOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

class _FixedProfile extends ProfileNotifier {
  _FixedProfile(this.value);
  final ProfileData value;

  @override
  ProfileData build() => value;
}
