import 'package:flutter/foundation.dart';

import 'shop_catalog.dart';
import 'wallet.dart';

/// What others see of the learner's Mağaza items (the "vitrin"): everything
/// they wear (avatar, frame, theme, Çaycı Dayı's and Pofuduk's outfits) and
/// up to [maxShowcase] chosen items. Friends read it from the `showcase` map
/// of `profiles/{uid}` (docs/altin.md); the Dünya Ligi keeps a copy in the
/// member document (`look`). Only known catalog ids are kept.
@immutable
class Showcase {
  const Showcase({
    this.avatar,
    this.frame,
    this.theme,
    this.mascot,
    this.pofuduk,
    this.items = const [],
    this.useAvatar = false,
  });

  /// Show [avatar] instead of the photo (Profil > Fotoğraf / Avatar).
  final bool useAvatar;

  final String? avatar;
  final String? frame;

  /// Worn app theme (`th_`).
  final String? theme;

  /// Çaycı Dayı's outfit (`mx_`).
  final String? mascot;

  /// Pofuduk's outfit (`px_`, Çocuk modu).
  final String? pofuduk;
  final List<String> items;

  bool get isEmpty =>
      avatar == null && frame == null && theme == null && mascot == null && pofuduk == null && items.isEmpty;

  /// The worn items, in Mağaza tab order.
  List<ShopItem> get worn => [
    ?shopItem(avatar),
    ?shopItem(frame),
    ?shopItem(mascot),
    ?shopItem(pofuduk),
    ?shopItem(theme),
  ];

  /// The worn theme's colour pair, if any.
  ThemeAccent? get accent => shopItem(theme)?.accent;

  /// The learner's own showcase, from their wallet. Free items (everyone
  /// has them) are not worth showing and stay out.
  factory Showcase.of(Wallet w) {
    String? paid(String slot) => switch (equippedIn(w, slot)) {
      final item? when !item.free => item.id,
      _ => null,
    };
    return Showcase(
      avatar: equippedIn(w, WalletSlot.avatar)?.id,
      frame: equippedIn(w, WalletSlot.frame)?.id,
      theme: paid(WalletSlot.theme),
      mascot: paid(WalletSlot.mascot),
      pofuduk: paid(WalletSlot.pofuduk),
      useAvatar: prefersAvatar(w),
      items: [
        for (final id in w.showcase)
          if (shopItem(id) case final item? when item.showcasable && ownsItem(w, item)) id,
      ].take(maxShowcase).toList(),
    );
  }

  Map<String, Object?> toMap() => {
    'avatar': avatar,
    'frame': frame,
    'theme': theme,
    'mascot': mascot,
    'pofuduk': pofuduk,
    'items': items,
    'useAvatar': useAvatar,
  };

  /// From Firestore. Unknown ids (a newer app version, or a hand-made
  /// write) and ids in the wrong slot are skipped.
  static Showcase? fromMap(Object? raw) {
    if (raw is! Map) return null;
    String? inSlot(String key, ShopCategory category) => switch (shopItem(_id(raw[key]))) {
      final item? when item.category == category => item.id,
      _ => null,
    };
    final items = raw['items'];
    return Showcase(
      avatar: inSlot('avatar', ShopCategory.avatar),
      frame: inSlot('frame', ShopCategory.frame),
      theme: inSlot('theme', ShopCategory.theme),
      mascot: inSlot('mascot', ShopCategory.mascot),
      pofuduk: inSlot('pofuduk', ShopCategory.pofuduk),
      useAvatar: raw['useAvatar'] == true,
      items: [
        if (items is List)
          for (final id in items.take(maxShowcase))
            if (shopItem(_id(id)) case final item? when item.showcasable) item.id,
      ],
    );
  }

  static String? _id(Object? v) => v is String ? v : null;

  @override
  bool operator ==(Object other) =>
      other is Showcase &&
      other.avatar == avatar &&
      other.frame == frame &&
      other.theme == theme &&
      other.mascot == mascot &&
      other.pofuduk == pofuduk &&
      other.useAvatar == useAvatar &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(avatar, frame, theme, mascot, pofuduk, useAvatar, Object.hashAll(items));
}
