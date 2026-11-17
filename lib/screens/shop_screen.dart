import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/gold_wallet.dart';
import '../data/progress.dart';
import '../data/shop_catalog.dart';
import '../services/profile.dart';
import '../theme.dart';
import '../ui/gold_coin.dart';
import '../ui/mascot.dart';
import '../ui/motion.dart';
import '../ui/my_avatar.dart';
import '../ui/shop_visuals.dart';

/// Opens the Mağaza.
Future<void> openShop(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ShopScreen()));

/// The Mağaza: spend Altın on avatars, frames, mascot outfits, app colours
/// and streak freezes. Altın is only earned by studying; it is never sold
/// (docs/altin.md).
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key, this.initial = ShopCategory.avatar});
  final ShopCategory initial;

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  /// The item tried on in each category's live preview.
  final _preview = <ShopCategory, String>{};

  /// "Sahip olduklarım": only owned items.
  bool _ownedOnly = false;

  void _try(ShopItem item) => setState(() => _preview[item.category] = item.id);

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(goldBalanceProvider);
    final kid = context.isKid;
    final tabs = ShopCategory.tabs(kid: kid);
    final start = tabs.indexOf(widget.initial);
    return DefaultTabController(
      length: tabs.length,
      initialIndex: start < 0 ? 0 : start,
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
            SliverToBoxAdapter(child: _Featured(onTry: _try)),
            SliverToBoxAdapter(
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [for (final c in tabs) Tab(key: ValueKey('shop-tab-${c.name}'), text: c.label)],
              ),
            ),
          ],
          body: TabBarView(
            children: [
              for (final c in tabs)
                _Grid(
                  category: c,
                  previewId: _preview[c],
                  ownedOnly: _ownedOnly,
                  onOwnedOnly: (v) => setState(() => _ownedOnly = v),
                  onTry: _try,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The learner's look as friends see it, the photo / avatar choice and the
/// showcase slots.
class _LookCard extends ConsumerWidget {
  const _LookCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(walletProvider);
    final hasPhoto = !context.isKid && ref.watch(profileProvider.select((p) => p.photo != null));
    final avatar = equippedIn(w, WalletSlot.avatar);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TapCard(
        child: Row(
          children: [
            const MyAvatar(key: ValueKey('shop-my-avatar'), size: 72),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Vitrinin', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    'Arkadaşların avatarını, çerçeveni ve seçtiğin en fazla $maxShowcase ürünü görür. '
                    'Ürünün köşesindeki ☆ ile vitrine koy.',
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
                  if (hasPhoto && avatar != null) ...[
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
                      key: const ValueKey('shop-face'),
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: [
                        const ButtonSegment(value: false, label: Text('Fotoğraf')),
                        ButtonSegment(value: true, label: Text('${avatar.emoji} Avatar')),
                      ],
                      selected: {prefersAvatar(w)},
                      onSelectionChanged: (s) => ref.read(goldWalletProvider).useAvatarFace(s.first),
                    ),
                  ],
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
      border: Border.all(color: item == null ? Brand.line : item!.rarity.color),
    ),
    child: item == null
        ? Icon(Icons.star_border_rounded, color: Brand.line, size: 20)
        : FittedBox(child: ShopItemPreview(item: item!, size: 48)),
  );
}

/// "Haftanın ürünleri": three items, cheaper this week, the same for
/// everyone (featuredItems).
class _Featured extends ConsumerWidget {
  const _Featured({required this.onTry});
  final void Function(ShopItem) onTry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final items = featuredItems(now, kid: context.isKid);
    final w = ref.watch(walletProvider);
    final today = DateTime(now.year, now.month, now.day);
    final daysLeft = 8 - today.weekday;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        key: const ValueKey('shop-featured'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [goldText(context).withValues(alpha: 0.16), Brand.primary.withValues(alpha: 0.08)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: goldText(context).withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '✨ Haftanın ürünleri',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  '%${(featuredDiscount * 100).round()} indirim · $daysLeft gün',
                  style: TextStyle(color: Brand.muted, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final item in items)
                  Expanded(
                    child: InkWell(
                      key: ValueKey('shop-featured-${item.id}'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        onTry(item);
                        final tabs = ShopCategory.tabs(kid: context.isKid);
                        DefaultTabController.maybeOf(context)?.animateTo(max(0, tabs.indexOf(item.category)));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            ShopItemPreview(item: item, size: 52),
                            const SizedBox(height: 4),
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                            ownsItem(w, item)
                                ? Text('Senin', style: TextStyle(color: Brand.success, fontSize: 12))
                                : _Price(item: item, now: now, size: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A price, struck through next to the discounted one when featured.
class _Price extends StatelessWidget {
  const _Price({required this.item, required this.now, this.size = 14, this.locked = false});
  final ShopItem item;
  final DateTime now;
  final double size;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final price = priceOf(item, now);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (price != item.price) ...[
          Text(
            '${item.price}',
            style: TextStyle(color: Brand.muted, fontSize: size - 1, decoration: TextDecoration.lineThrough),
          ),
          const SizedBox(width: 4),
        ],
        PriceTag(price: price, locked: locked),
      ],
    );
  }
}

class _Grid extends ConsumerWidget {
  const _Grid({
    required this.category,
    required this.previewId,
    required this.ownedOnly,
    required this.onOwnedOnly,
    required this.onTry,
  });
  final ShopCategory category;
  final String? previewId;
  final bool ownedOnly;
  final ValueChanged<bool> onOwnedOnly;
  final void Function(ShopItem) onTry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(walletProvider);
    final all = itemsIn(category);
    final items = ownedOnly && category != ShopCategory.freeze
        ? [
            for (final i in all)
              if (ownsItem(w, i)) i,
          ]
        : all;
    final slot = category.slot;
    final tried =
        shopItem(previewId) ??
        (slot == null ? null : equippedIn(w, slot)) ??
        (all.isEmpty ? null : all.first);
    return CustomScrollView(
      key: PageStorageKey('shop-${category.name}'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.visibility_outlined, size: 18, color: Brand.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    key: ValueKey('shop-where-${category.name}'),
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Nerede görünür? ',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(text: category.where),
                      ],
                    ),
                    style: TextStyle(color: Brand.muted, fontSize: 13, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (tried != null) SliverToBoxAdapter(child: _LivePreview(item: tried)),
        if (category != ShopCategory.freeze)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  key: const ValueKey('shop-owned-filter'),
                  label: const Text('Sahip olduklarım'),
                  selected: ownedOnly,
                  onSelected: onOwnedOnly,
                ),
              ),
            ),
          ),
        if (items.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Bu kategoride henüz ürünün yok.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Brand.muted),
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
              childAspectRatio: 0.62,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) => _ItemCard(item: items[i], tried: items[i].id == tried?.id, onTry: onTry),
              childCount: items.length,
            ),
          ),
        ),
      ],
    );
  }
}

/// Before buying: the item on the learner's own profile and league row
/// (avatars, frames), on the mascot, or as the app colour.
class _LivePreview extends ConsumerWidget {
  const _LivePreview({required this.item});
  final ShopItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(walletProvider);
    final name = ref.watch(myDisplayNameProvider);
    final photo = context.isKid ? null : ref.watch(profileProvider.select((p) => p.photo));
    final avatarId = item.category == ShopCategory.avatar ? item.id : equippedIn(w, WalletSlot.avatar)?.id;
    final frameId = item.category == ShopCategory.frame ? item.id : equippedIn(w, WalletSlot.frame)?.id;
    final preferAvatar = item.category == ShopCategory.avatar || context.isKid || prefersAvatar(w);
    Widget face(double size) => StyledAvatar(
      size: size,
      photo: photo,
      avatarId: avatarId,
      frameId: frameId,
      preferAvatar: preferAvatar,
      fallback: AvatarFace(emoji: '🙂', size: size),
    );

    final Widget body = switch (item.category) {
      ShopCategory.avatar || ShopCategory.frame => Column(
        children: [
          // Profile header.
          Row(
            children: [
              face(56),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              Text('Profil', style: TextStyle(color: Brand.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          // League row.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Brand.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Brand.primary, width: 1.5),
            ),
            child: Row(
              children: [
                Text(
                  '4',
                  style: TextStyle(color: Brand.success, fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 12),
                face(36),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$name (Sen)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '120 XP',
                  style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
      ShopCategory.mascot => Center(
        child: dressedMascot(Image.asset(mascotAsset, width: 120, height: 120), 120, item.accessory),
      ),
      ShopCategory.pofuduk => Center(
        child: dressedMascot(
          Image.asset(pofudukPose(Mood.idle), width: 120, height: 120, fit: BoxFit.contain),
          120,
          item.accessory,
        ),
      ),
      ShopCategory.theme => _ThemeSample(accent: item.accent!),
      ShopCategory.freeze => Row(
        children: [
          const Text('🔥🧊', style: TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Salı unuttun, çarşamba döndün: serin dondurmayla devam eder. '
              'Her kaçırılan gün bir tane kullanır; en fazla $maxFreezes tane saklanır.',
              style: TextStyle(color: Brand.muted, height: 1.35),
            ),
          ),
        ],
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Container(
        key: const ValueKey('shop-preview'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Brand.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: item.rarity.color.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Önizleme: ${item.name}',
              key: const ValueKey('shop-preview-title'),
              style: TextStyle(color: Brand.muted, fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }
}

class _ThemeSample extends StatelessWidget {
  const _ThemeSample({required this.accent});
  final ThemeAccent accent;

  @override
  Widget build(BuildContext context) {
    final c = context.palette.isDark ? accent.dark : accent.light;
    final on = onColor(c);
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(12)),
            child: Text(
              'DEVAM',
              style: TextStyle(color: on, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c),
          ),
          child: Text(
            'Seçili',
            style: TextStyle(color: c, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Icon(Icons.check_circle_rounded, color: c, size: 28),
      ],
    );
  }
}

class _ItemCard extends ConsumerWidget {
  const _ItemCard({required this.item, required this.tried, required this.onTry});
  final ShopItem item;
  final bool tried;
  final void Function(ShopItem) onTry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(walletProvider);
    final now = ref.watch(clockProvider)();
    final owned = ownsItem(w, item);
    final slot = item.category.slot;
    final worn = slot != null && (equippedIn(w, slot)?.id ?? _defaultOf(slot)) == item.id;
    final price = priceOf(item, now);
    final locked = !owned && w.balance < price;
    final inShowcase = w.showcase.contains(item.id);
    final featured = price != item.price;
    final p = context.palette;
    final edge = worn ? p.primary : item.rarity.color.withValues(alpha: tried ? 1 : 0.55);

    return InkWell(
      onTap: () => onTry(item),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        key: ValueKey('shop-item-${item.id}'),
        decoration: BoxDecoration(
          color: Brand.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: edge, width: worn || tried ? 2.5 : 1.5),
          boxShadow: item.rarity == Rarity.epic
              ? [BoxShadow(color: item.rarity.color.withValues(alpha: 0.25), blurRadius: 10)]
              : null,
        ),
        padding: const EdgeInsets.all(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: item.rarity.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      featured
                          ? '${item.rarity.label} · %${(featuredDiscount * 100).round()}'
                          : item.rarity.label,
                      key: ValueKey('shop-rarity-${item.id}'),
                      style: TextStyle(color: item.rarity.color, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
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
                SizedBox(height: 18, child: _status(owned, worn, locked, w, now)),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: _button(context, ref, owned, worn, locked, w, price),
                ),
              ],
            ),
            if (owned && item.showcasable)
              Positioned(
                right: -10,
                top: -12,
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
      ),
    );
  }

  /// The look worn when nothing is chosen (shown as "Kullanılıyor").
  static String? _defaultOf(String slot) => slot == WalletSlot.theme ? 'th_cay' : null;

  Widget _status(bool owned, bool worn, bool locked, Wallet w, DateTime now) {
    if (item.consumable) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Price(item: item, now: now, locked: locked),
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
      child: _Price(item: item, now: now, locked: locked),
    );
  }

  Widget _button(
    BuildContext context,
    WidgetRef ref,
    bool owned,
    bool worn,
    bool locked,
    Wallet w,
    int price,
  ) {
    final wallet = ref.read(goldWalletProvider);
    const pad = EdgeInsets.symmetric(horizontal: 6);
    if (item.consumable || !owned) {
      final full = item.consumable && w.freezes >= maxFreezes;
      return FilledButton(
        key: ValueKey('shop-buy-${item.id}'),
        style: FilledButton.styleFrom(padding: pad),
        onPressed: locked || full ? null : () => _buy(context, ref, price),
        child: FittedBox(
          child: Text(
            full
                ? 'Stok dolu'
                : locked
                ? '${price - w.balance} eksik'
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
      onPressed: () {
        wallet.equip(item);
        onTry(item);
      },
      child: const FittedBox(child: Text('Kullan')),
    );
  }

  Future<void> _buy(BuildContext context, WidgetRef ref, int price) async {
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
                children: [GoldAmount(price, size: 16), const Text(' karşılığında alınsın mı?')],
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
    final wallet = ref.read(goldWalletProvider);
    final result = wallet.buy(item);
    if (result != BuyResult.bought) {
      _toast(context, switch (result) {
        BuyResult.insufficient => 'Yeterli altının yok. Ders bitirerek altın kazanabilirsin.',
        BuyResult.owned => 'Bu ürün zaten sende.',
        BuyResult.stockFull => 'En fazla $maxFreezes seri dondurma saklayabilirsin.',
        BuyResult.bought => '',
      });
      return;
    }
    final use = await showPurchaseCelebration(context, item);
    if (use == true) {
      wallet.equip(item);
      onTry(item);
    }
  }

  static void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

/// The moment after a purchase: the item pops in among coins and stars.
/// Returns true for "Hemen kullan" (wearable items).
Future<bool?> showPurchaseCelebration(BuildContext context, ShopItem item) => showDialog<bool>(
  context: context,
  builder: (c) => Dialog(
    key: const ValueKey('shop-celebrate'),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 150, width: 200, child: _Sparkles(item: item)),
          const SizedBox(height: 8),
          Text(
            item.consumable ? 'Seri dondurma stokta!' : '${item.name} senin!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            item.rarity.label,
            style: TextStyle(color: item.rarity.color, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          if (item.category.slot != null)
            Row(
              children: [
                Expanded(
                  child: TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Sonra')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const ValueKey('shop-use-now'),
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Hemen kullan'),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Tamam')),
            ),
        ],
      ),
    ),
  ),
);

/// The bought item scaling in, with coins and stars flying out once.
class _Sparkles extends StatefulWidget {
  const _Sparkles({required this.item});
  final ShopItem item;

  @override
  State<_Sparkles> createState() => _SparklesState();
}

class _SparklesState extends State<_Sparkles> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.value > 0) return;
    if (loopsEnabled(context)) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) {
      final t = _c.value;
      final pop = Curves.elasticOut.transform(const Interval(0, 0.8).transform(t));
      final burst = Curves.easeOut.transform(t);
      const n = 10;
      return Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < n; i++)
            Transform.translate(
              offset: Offset.fromDirection(i * 2 * pi / n - pi / 2, 20 + 70 * burst),
              child: Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: i.isEven
                    ? const GoldCoin(size: 16)
                    : Icon(Icons.star_rounded, size: 16, color: widget.item.rarity.color),
              ),
            ),
          Transform.scale(
            scale: 0.3 + 0.7 * pop,
            child: ShopItemPreview(item: widget.item, size: 96),
          ),
        ],
      );
    },
  );
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
