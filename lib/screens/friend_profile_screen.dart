import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../data/shop_catalog.dart';
import '../services/friends.dart';
import '../services/profile.dart';
import '../services/showcase.dart';
import '../theme.dart';
import '../ui/shop_visuals.dart';

/// The worn theme's colour for this brightness, if any.
Color? lookAccent(BuildContext context, Showcase? showcase) => switch (showcase?.accent) {
  final a? => context.palette.isDark ? a.dark : a.light,
  null => null,
};

/// Whether [ShowcaseStrip] has anything to draw for [showcase].
bool hasStrip(Showcase? showcase, {required bool kid}) =>
    showcase != null &&
    (showcase.items.isNotEmpty ||
        showcase.theme != null ||
        (kid ? showcase.pofuduk : showcase.mascot) != null);

/// A row's small view of someone's Mağaza look: the worn theme as a colour
/// dot, the mascot outfit, then the chosen showcase items as tiles (nothing
/// when all are empty).
class ShowcaseStrip extends StatelessWidget {
  const ShowcaseStrip({super.key, required this.showcase, this.size = 28});
  final Showcase? showcase;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = showcase;
    if (s == null || !hasStrip(s, kid: context.isKid)) return const SizedBox.shrink();
    final theme = shopItem(s.theme);
    final outfit = shopItem(context.isKid ? s.pofuduk : s.mascot);
    final items = [for (final id in s.items) ?shopItem(id)];
    final accent = lookAccent(context, s);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (theme != null && accent != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Tooltip(
              message: 'Tema: ${theme.name}',
              child: Container(
                key: ValueKey('look-theme-${theme.id}'),
                width: size * 0.6,
                height: size * 0.6,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Brand.line),
                ),
              ),
            ),
          ),
        if (outfit != null && outfit.accessory != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Tooltip(
              message: outfit.name,
              child: SizedBox.square(
                key: ValueKey('look-outfit-${outfit.id}'),
                dimension: size,
                child: FittedBox(child: Text(outfit.accessory!.emoji, style: const TextStyle(height: 1))),
              ),
            ),
          ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Tooltip(
              message: item.name,
              child: SizedBox.square(
                key: ValueKey('showcase-item-${item.id}'),
                dimension: size,
                child: FittedBox(child: ShopItemPreview(item: item, size: 56)),
              ),
            ),
          ),
      ],
    );
  }
}

/// A Mağaza item as a captioned tile.
class _ItemTile extends StatelessWidget {
  const _ItemTile({super.key, required this.item, this.caption});
  final ShopItem item;
  final String? caption;

  @override
  Widget build(BuildContext context) => Container(
    width: 100,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Brand.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Brand.line),
    ),
    child: Column(
      children: [
        ShopItemPreview(item: item, size: 56),
        const SizedBox(height: 6),
        Text(
          item.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        if (caption case final c?) Text(c, style: TextStyle(color: Brand.muted, fontSize: 11)),
      ],
    ),
  );
}

/// A friend's profile in their worn Mağaza theme: photo or Mağaza avatar
/// in their frame, name, shared streak, what they wear and the showcase
/// they chose.
class FriendProfileScreen extends ConsumerWidget {
  const FriendProfileScreen({super.key, required this.friend});
  final Friendship friend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(friendProfileProvider(friend.friendUid)).value;
    final showcase = profile?.showcase;
    final today = friendDay(ref.watch(clockProvider)());
    final name = profile?.name ?? friend.name;
    final items = [for (final id in showcase?.items ?? const <String>[]) ?shopItem(id)];
    // Çocuk modu shows Pofuduk's outfit, adults Çaycı Dayı's.
    final hidden = context.isKid ? ShopCategory.mascot : ShopCategory.pofuduk;
    final worn = [
      for (final item in showcase?.worn ?? const <ShopItem>[])
        if (item.category != hidden) item,
    ];
    final accent = lookAccent(context, showcase);
    final base = Theme.of(context);
    final themed = accent == null
        ? base
        : base.copyWith(
            colorScheme: base.colorScheme.copyWith(primary: accent, onPrimary: onColor(accent)),
          );
    return Theme(
      data: themed,
      child: Scaffold(
        appBar: AppBar(title: Text(name)),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              key: const ValueKey('friend-profile-header'),
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                // Tinted with the friend's worn theme.
                color: accent?.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  StyledAvatar(
                    key: const ValueKey('friend-profile-avatar'),
                    size: 120,
                    photo: profile?.photo,
                    avatarId: showcase?.avatar,
                    frameId: showcase?.frame,
                    preferAvatar: showcase?.useAvatar ?? false,
                    fallback: AvatarFace(emoji: friend.avatar, size: 100),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ortak seri: ${friend.streakOn(today)} gün · En iyi: ${friend.best} gün',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Brand.muted),
                  ),
                ],
              ),
            ),
            if (worn.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Kuşandıkları', style: base.textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final item in worn)
                    _ItemTile(
                      key: ValueKey('friend-worn-${item.id}'),
                      item: item,
                      caption: item.category.label,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Text('Vitrin', style: base.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text(
                '$name vitrinine henüz bir şey koymadı.',
                key: const ValueKey('friend-showcase-empty'),
                style: TextStyle(color: Brand.muted),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final item in items)
                    _ItemTile(key: ValueKey('friend-showcase-${item.id}'), item: item),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
