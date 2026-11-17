import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/gold_wallet.dart';
import '../data/shop_catalog.dart';
import '../services/profile.dart';
import '../theme.dart';
import '../ui/gold_coin.dart';
import '../ui/shop_visuals.dart';

/// Opens the Mağaza.
Future<void> openShop(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ShopScreen()));

/// The Mağaza: spend Altın on avatars, frames, Çaycı Dayı accessories, app
/// colours and streak freezes. Altın is only earned by studying; it is never
/// sold (docs/altin.md).
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key, this.initial = ShopCategory.avatar});
  final ShopCategory initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(goldBalanceProvider);
    return DefaultTabController(
      length: ShopCategory.values.length,
      initialIndex: initial.index,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mağaza'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Tooltip(
                message: 'Altın: ders bitirerek, görevlerle ve ligde kazanılır',
                child: InkWell(
                  key: const ValueKey('shop-balance'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => showGoldHelp(context),
                  child: Padding(padding: const EdgeInsets.all(6), child: GoldAmount(balance, size: 18)),
                ),
              ),
            ),
          ],
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            const SliverToBoxAdapter(child: _LookCard()),
            SliverToBoxAdapter(
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final c in ShopCategory.values)
                    Tab(key: ValueKey('shop-tab-${c.name}'), text: c.label),
                ],
              ),
            ),
          ],
          body: TabBarView(children: [for (final c in ShopCategory.values) _Grid(category: c)]),
        ),
      ),
    );
  }
}

/// The learner's look as friends see it, with the showcase slots.
class _LookCard extends ConsumerWidget {
  const _LookCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(walletProvider);
    final photo = Brand.isKid ? null : ref.watch(profileProvider.select((p) => p.photo));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TapCard(
        child: Row(
          children: [
            StyledAvatar(
              key: const ValueKey('shop-my-avatar'),
              size: 72,
              photo: photo,
              avatarId: equippedIn(w, WalletSlot.avatar)?.id,
              frameId: equippedIn(w, WalletSlot.frame)?.id,
              fallback: AvatarFace(emoji: '🙂', size: 60),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Vitrinin', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    'Arkadaşların avatarını, çerçeveni ve seçtiğin en fazla $maxShowcase ürünü görür.',
                    style: TextStyle(color: Brand.muted, fontSize: 12, height: 1.3),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 0; i < maxShowcase; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _ShowcaseSlot(item: i < w.showcase.length ? shopItem(w.showcase[i]) : null),
                        ),
                    ],
                  ),
                  if (w.freezes > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '🧊 Seri dondurma: ${w.freezes}',
                      key: const ValueKey('shop-freezes'),
                      style: TextStyle(color: Brand.muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShowcaseSlot extends StatelessWidget {
  const _ShowcaseSlot({required this.item});
  final ShopItem? item;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Brand.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Brand.line),
    ),
    child: item == null
        ? Icon(Icons.star_border_rounded, color: Brand.line, size: 20)
        : FittedBox(child: ShopItemPreview(item: item!, size: 48)),
  );
}

class _Grid extends ConsumerWidget {
  const _Grid({required this.category});
  final ShopCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = itemsIn(category);
    return CustomScrollView(
      key: PageStorageKey('shop-${category.name}'),
      slivers: [
        if (category == ShopCategory.freeze)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Bir gün çalışamazsan seri dondurma serini korur: her kaçırılan gün için bir tane kullanılır. '
                'En fazla $maxFreezes tane saklayabilirsin.',
                style: TextStyle(color: Brand.muted, height: 1.35),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.68,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) => _ItemCard(item: items[i]),
              childCount: items.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _ItemCard extends ConsumerWidget {
  const _ItemCard({required this.item});
  final ShopItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(walletProvider);
    final owned = ownsItem(w, item);
    final slot = item.category.slot;
    final worn = slot != null && (equippedIn(w, slot)?.id ?? _defaultOf(slot)) == item.id;
    final locked = !owned && w.balance < item.price;
    final inShowcase = w.showcase.contains(item.id);
    final p = context.palette;

    return Container(
      key: ValueKey('shop-item-${item.id}'),
      decoration: BoxDecoration(
        color: Brand.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: worn ? p.primary : Brand.line, width: worn ? 2 : 1),
      ),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Center(
                  child: Opacity(
                    opacity: locked ? 0.55 : 1,
                    child: ShopItemPreview(item: item, size: 60),
                  ),
                ),
              ),
              Text(
                item.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.2),
              ),
              const SizedBox(height: 4),
              SizedBox(height: 18, child: _status(owned, worn, locked, w)),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 34,
                child: _button(context, ref, owned, worn, locked, w),
              ),
            ],
          ),
          if (owned && item.showcasable)
            Positioned(
              right: -6,
              top: -10,
              child: IconButton(
                key: ValueKey('shop-showcase-${item.id}'),
                tooltip: inShowcase ? 'Vitrinden çıkar' : 'Vitrine koy',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  inShowcase ? Icons.star_rounded : Icons.star_border_rounded,
                  color: inShowcase ? goldText(context) : Brand.muted,
                ),
                onPressed: () {
                  final ok = ref.read(goldWalletProvider).toggleShowcase(item);
                  if (!ok) _toast(context, 'Vitrinde en fazla $maxShowcase ürün olabilir.');
                },
              ),
            ),
        ],
      ),
    );
  }

  /// The look worn when nothing is chosen (shown as "Kullanılıyor").
  static String? _defaultOf(String slot) => slot == WalletSlot.theme ? 'th_cay' : null;

  Widget _status(bool owned, bool worn, bool locked, Wallet w) {
    if (item.consumable) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PriceTag(price: item.price, locked: locked),
          const SizedBox(width: 6),
          Text('· ${w.freezes}/$maxFreezes', style: TextStyle(color: Brand.muted, fontSize: 12)),
        ],
      );
    }
    if (worn) {
      return Text(
        'Kullanılıyor',
        style: TextStyle(color: Brand.success, fontWeight: FontWeight.w700, fontSize: 12),
      );
    }
    if (owned) {
      return Text(
        item.free ? 'Ücretsiz' : 'Senin',
        style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w600, fontSize: 12),
      );
    }
    return Center(
      child: PriceTag(price: item.price, locked: locked),
    );
  }

  Widget _button(BuildContext context, WidgetRef ref, bool owned, bool worn, bool locked, Wallet w) {
    final wallet = ref.read(goldWalletProvider);
    const pad = EdgeInsets.symmetric(horizontal: 6);
    if (item.consumable || !owned) {
      final full = item.consumable && w.freezes >= maxFreezes;
      return FilledButton(
        key: ValueKey('shop-buy-${item.id}'),
        style: FilledButton.styleFrom(padding: pad),
        onPressed: locked || full ? null : () => _buy(context, ref),
        child: FittedBox(
          child: Text(
            full
                ? 'Stok dolu'
                : locked
                ? '${item.price - w.balance} eksik'
                : 'Satın al',
          ),
        ),
      );
    }
    if (worn) {
      final slot = item.category.slot!;
      final removable = slot != WalletSlot.theme && w.equipped.containsKey(slot);
      return OutlinedButton(
        key: ValueKey('shop-unequip-${item.id}'),
        style: OutlinedButton.styleFrom(padding: pad),
        onPressed: removable ? () => wallet.unequip(slot) : null,
        child: FittedBox(child: Text(removable ? 'Çıkar' : 'Kullanılıyor')),
      );
    }
    return FilledButton.tonal(
      key: ValueKey('shop-use-${item.id}'),
      style: FilledButton.styleFrom(padding: pad),
      onPressed: () => wallet.equip(item),
      child: const FittedBox(child: Text('Kullan')),
    );
  }

  Future<void> _buy(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(item.name),
        content: Row(
          children: [
            ShopItemPreview(item: item, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [GoldAmount(item.price, size: 16), const Text(' karşılığında alınsın mı?')],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(
            key: const ValueKey('shop-confirm'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Satın al'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final result = ref.read(goldWalletProvider).buy(item);
    final message = switch (result) {
      BuyResult.bought =>
        item.consumable ? 'Seri dondurma stoğa eklendi.' : '${item.name} senin! Hemen kullanılıyor.',
      BuyResult.insufficient => 'Yeterli altının yok. Ders bitirerek altın kazanabilirsin.',
      BuyResult.owned => 'Bu ürün zaten sende.',
      BuyResult.stockFull => 'En fazla $maxFreezes seri dondurma saklayabilirsin.',
    };
    _toast(context, message);
  }

  static void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

/// How Altın is earned (from the balance chips).
Future<void> showGoldHelp(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (c) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              GoldCoin(size: 28),
              SizedBox(width: 10),
              Text('Altın nasıl kazanılır?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          _HelpLine('Her bitirdiğin ders', '+$goldPerLesson'),
          _HelpLine('Hatasız ders', '+$goldPerfectBonus'),
          _HelpLine('Günlük hedefe ulaşmak', '+$goldDailyGoal'),
          const _HelpLine('Günlük görev ödülü', '+5–15'),
          _HelpLine('Seri: 3, 7, 14, 30… gün', '+${goldStreakMilestones[3]}–${goldStreakMilestones[365]}'),
          const _HelpLine('Haftalık lig sonucu', '+15–80'),
          const SizedBox(height: 10),
          Text('Altın yalnızca çalışarak kazanılır, parayla satılmaz.', style: TextStyle(color: Brand.muted)),
        ],
      ),
    ),
  ),
);

class _HelpLine extends StatelessWidget {
  const _HelpLine(this.label, this.amount);
  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          amount,
          style: TextStyle(color: goldText(context), fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}
