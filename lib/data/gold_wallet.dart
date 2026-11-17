import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/billing/premium_perks.dart' show goldMultiplierProvider;

import 'progress.dart';
import 'shop_catalog.dart';
import 'shop_catalog.dart' as catalog show priceOf;
import 'wallet.dart';

export 'wallet.dart';

/// Outcome of [GoldWallet.buy].
enum BuyResult {
  bought,

  /// Not enough gold.
  insufficient,

  /// Already owned (or free).
  owned,

  /// Streak freezes: the stock is full ([maxFreezes]).
  stockFull,

  /// A Premium-only item, and the learner has no Premium.
  needsPremium,
}

/// The one place gold is earned and spent outside lessons, quests and the
/// league (which credit it inside [ProgressNotifier] together with the rest
/// of the progress). Other features (e.g. a rewarded ad) call [earn].
class GoldWallet {
  GoldWallet(this._ref);
  final Ref _ref;

  ProgressNotifier get _progress => _ref.read(progressProvider.notifier);
  Wallet get _wallet => _ref.read(progressProvider).wallet;
  String _today() => dayKey(_ref.read(clockProvider)());
  int _nowMs() => _ref.read(clockProvider)().millisecondsSinceEpoch;

  int get balance => _wallet.balance;

  /// Adds [amount] gold for [reason], twice that with Premium. With
  /// [onceKey] the reward (Premium's double included) is given at most once
  /// (for about two months; e.g. `ad:2026-11-17:1`). Returns whether gold
  /// was added.
  bool earn(int amount, GoldReason reason, {String? onceKey}) {
    if (amount <= 0) return false;
    if (onceKey != null && _wallet.once.containsKey(onceKey)) return false;
    final today = _today();
    final int multiplier = _ref.read(goldMultiplierProvider);
    final total = amount * multiplier;
    _progress.updateWallet((w, device) {
      final next = onceKey == null ? w : w.copyWith(once: {...w.once, onceKey: today});
      return next.pruned(today).credit(device, total);
    });
    return true;
  }

  /// Takes a Premium-only Mağaza item (no gold): only while Premium is
  /// active. It stays the learner's afterwards.
  BuyResult claimPremium(ShopItem item, {required bool premium}) {
    if (!item.premiumOnly) return BuyResult.owned;
    if (ownsItem(_wallet, item)) return BuyResult.owned;
    if (!premium) return BuyResult.needsPremium;
    _progress.updateWallet((w, _) => w.copyWith(owned: [...w.owned, item.id]));
    return BuyResult.bought;
  }

  /// The price of [item] today (featured items are cheaper this week).
  int priceOf(ShopItem item) => catalog.priceOf(item, _ref.read(clockProvider)());

  /// Buys [item] with gold. It is not worn yet: the Mağaza offers
  /// "Hemen kullan" after the purchase.
  BuyResult buy(ShopItem item) {
    if (item.premiumOnly) return ownsItem(_wallet, item) ? BuyResult.owned : BuyResult.needsPremium;
    final price = priceOf(item);
    final w = _wallet;
    if (item.consumable) {
      if (w.freezes >= maxFreezes) return BuyResult.stockFull;
    } else if (ownsItem(w, item)) {
      return BuyResult.owned;
    }
    if (w.balance < price) return BuyResult.insufficient;
    _progress.updateWallet((w, device) {
      final paid = w.debit(device, price);
      if (item.consumable) {
        return paid.copyWith(
          freezeBought: {...paid.freezeBought, device: (paid.freezeBought[device] ?? 0) + 1},
        );
      }
      return paid.copyWith(owned: [...paid.owned, item.id]);
    });
    return BuyResult.bought;
  }

  Wallet _wear(Wallet w, ShopItem item) {
    final slot = item.category.slot;
    if (slot == null) return w;
    // Choosing an avatar shows it instead of the photo (until the learner
    // picks the photo again).
    return w.copyWith(
      equipped: {
        ...w.equipped,
        slot: item.id,
        if (slot == WalletSlot.avatar) WalletSlot.face: WalletSlot.faceAvatar,
      },
      styledAt: _nowMs(),
    );
  }

  /// Wears an owned [item] ("Kullan"). Returns false when it is not owned.
  bool equip(ShopItem item) {
    if (item.category.slot == null || !ownsItem(_wallet, item)) return false;
    _progress.updateWallet((w, _) => _wear(w, item));
    return true;
  }

  /// Shows the Mağaza avatar ([avatar] true) or the photo everywhere.
  void useAvatarFace(bool avatar) {
    final w = _wallet;
    if ((w.equipped[WalletSlot.face] == WalletSlot.faceAvatar) == avatar) return;
    _progress.updateWallet(
      (w, _) => w.copyWith(
        equipped: avatar
            ? {...w.equipped, WalletSlot.face: WalletSlot.faceAvatar}
            : ({...w.equipped}..remove(WalletSlot.face)),
        styledAt: _nowMs(),
      ),
    );
  }

  /// Takes off what is worn in [slot] (back to the default look).
  void unequip(String slot) {
    if (!_wallet.equipped.containsKey(slot)) return;
    _progress.updateWallet((w, _) => w.copyWith(equipped: {...w.equipped}..remove(slot), styledAt: _nowMs()));
  }

  /// Puts an owned item in the friends' showcase or takes it out. Returns
  /// false when it cannot go there or the showcase is full.
  bool toggleShowcase(ShopItem item) {
    final w = _wallet;
    if (w.showcase.contains(item.id)) {
      _progress.updateWallet(
        (w, _) => w.copyWith(showcase: [...w.showcase]..remove(item.id), styledAt: _nowMs()),
      );
      return true;
    }
    if (!item.showcasable || !ownsItem(w, item) || w.showcase.length >= maxShowcase) return false;
    _progress.updateWallet((w, _) => w.copyWith(showcase: [...w.showcase, item.id], styledAt: _nowMs()));
    return true;
  }

  /// Gold for a finished Dünya Ligi week (once per week key).
  bool earnLeague({
    required String weekKey,
    required bool promoted,
    required bool demoted,
    required int rank,
    required int xp,
  }) => earn(
    goldForLeague(promoted: promoted, demoted: demoted, rank: rank, xp: xp),
    GoldReason.league,
    onceKey: 'league:$weekKey',
  );
}

final goldWalletProvider = Provider<GoldWallet>(GoldWallet.new);

/// The wallet, live.
final walletProvider = Provider<Wallet>((ref) => ref.watch(progressProvider.select((p) => p.wallet)));

/// Gold to spend, live.
final goldBalanceProvider = Provider<int>((ref) => ref.watch(walletProvider).balance);
