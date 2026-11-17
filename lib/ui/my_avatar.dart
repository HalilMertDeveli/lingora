import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/gold_wallet.dart';
import '../data/shop_catalog.dart';
import '../services/profile.dart';
import '../theme.dart';
import 'mascot.dart';
import 'shop_visuals.dart';

/// The learner's own face as everyone sees it: the photo or the Mağaza
/// avatar (Profil > Fotoğraf / Avatar), inside the worn frame. Çocuk modu
/// has no photos: the Mağaza avatar, else Pofuduk's face.
///
/// Used in the top bar, the profile header, the lesson result, the league
/// row and the Mağaza.
class MyAvatar extends ConsumerWidget {
  const MyAvatar({super.key, required this.size, this.fallback, this.kidKey});
  final double size;

  /// Shown when there is neither a photo nor an avatar (adult mode);
  /// defaults to a person icon.
  final Widget? fallback;

  /// Key of the Pofuduk face (Çocuk modu without an avatar).
  final Key? kidKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(walletProvider);
    final kid = Brand.isKid;
    final photo = kid ? null : ref.watch(profileProvider.select((p) => p.photo));
    final avatar = equippedIn(w, WalletSlot.avatar)?.id;
    final frame = equippedIn(w, WalletSlot.frame)?.id;
    return StyledAvatar(
      size: size,
      photo: photo,
      avatarId: avatar,
      frameId: frame,
      preferAvatar: kid || prefersAvatar(w),
      fallback: kid
          ? ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.28),
              child: Image.asset(pofudukAvatar, key: kidKey, width: size, height: size),
            )
          : fallback ??
                CircleAvatar(
                  radius: size / 2,
                  backgroundColor: Brand.surface,
                  child: Icon(Icons.person_rounded, color: Brand.muted, size: size * 0.6),
                ),
    );
  }
}
