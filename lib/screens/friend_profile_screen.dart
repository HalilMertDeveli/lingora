import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress.dart';
import '../data/shop_catalog.dart';
import '../services/friends.dart';
import '../services/profile.dart';
import '../services/showcase.dart';
import '../theme.dart';
import '../ui/shop_visuals.dart';

/// The friend's showcase items as small tiles (nothing when empty).
class ShowcaseStrip extends StatelessWidget {
  const ShowcaseStrip({super.key, required this.showcase, this.size = 28});
  final Showcase? showcase;
  final double size;

  @override
  Widget build(BuildContext context) {
    final items = [for (final id in showcase?.items ?? const <String>[]) ?shopItem(id)];
    if (items.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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

/// A friend's profile: photo or Mağaza avatar in their frame, name, shared
/// streak and the showcase they chose.
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
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: StyledAvatar(
              key: const ValueKey('friend-profile-avatar'),
              size: 120,
              photo: profile?.photo,
              avatarId: showcase?.avatar,
              frameId: showcase?.frame,
              fallback: AvatarFace(emoji: friend.avatar, size: 100),
            ),
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
          const SizedBox(height: 24),
          Text('Vitrin', style: Theme.of(context).textTheme.titleLarge),
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
                  Container(
                    key: ValueKey('friend-showcase-${item.id}'),
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
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
