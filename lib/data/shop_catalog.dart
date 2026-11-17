import 'package:flutter/painting.dart';

import 'wallet.dart';

/// Mağaza categories, in tab order.
enum ShopCategory {
  avatar('Avatarlar', WalletSlot.avatar),
  frame('Çerçeveler', WalletSlot.frame),
  mascot('Çaycı Dayı', WalletSlot.mascot),
  theme('Temalar', WalletSlot.theme),
  freeze('Seri dondurma', null);

  const ShopCategory(this.label, this.slot);

  /// Tabs shown in the Mağaza. Çocuk modu has no Çaycı Dayı tab: kids only
  /// ever see Pofuduk.
  static List<ShopCategory> tabs({required bool kid}) => [
    for (final c in values)
      if (!kid || c != mascot) c,
  ];
  final String label;

  /// Where the item is worn; null for consumables.
  final String? slot;
}

/// Where a mascot accessory sits on the Çaycı Dayı tile (fractions of its
/// side) and how big it is.
class MascotAccessory {
  const MascotAccessory(this.emoji, this.x, this.y, this.size);
  final String emoji;
  final double x;
  final double y;
  final double size;
}

/// An accent colour pair for the app (light / dark brightness).
class ThemeAccent {
  const ThemeAccent(this.light, this.dark);
  final Color light;
  final Color dark;
}

/// A ring drawn around avatars: a sweep of [colors].
class FrameStyle {
  const FrameStyle(this.colors, {this.width = 0.09});
  final List<Color> colors;

  /// Ring width as a fraction of the avatar side.
  final double width;
}

/// One Mağaza item. Everything is our own: emoji, colours and drawings made
/// in code (docs/varliklar.md). Ids match `validItemId` in firestore.rules.
class ShopItem {
  const ShopItem({
    required this.id,
    required this.category,
    required this.name,
    required this.price,
    this.emoji,
    this.frame,
    this.accessory,
    this.accent,
  });

  final String id;
  final ShopCategory category;
  final String name;

  /// Gold; 0 means everyone has it from the start.
  final int price;

  /// Avatar face / freeze icon.
  final String? emoji;
  final FrameStyle? frame;
  final MascotAccessory? accessory;
  final ThemeAccent? accent;

  bool get free => price == 0;
  bool get consumable => category == ShopCategory.freeze;

  /// Can be put in the friends' showcase.
  bool get showcasable => !consumable && !free;
}

const streakFreezeItem = ShopItem(
  id: 'fz_buz',
  category: ShopCategory.freeze,
  name: 'Seri dondurma',
  price: 100,
  emoji: '🧊',
);

/// The whole Mağaza. Prices aim at one or two items a week for a learner
/// who studies most days (about 300–400 gold a week, see docs/altin.md).
const shopItems = <ShopItem>[
  // Avatars: emoji faces on a round tile.
  ShopItem(id: 'av_cay', category: ShopCategory.avatar, name: 'Çay bardağı', price: 0, emoji: '🍵'),
  ShopItem(id: 'av_kedi', category: ShopCategory.avatar, name: 'Sokak kedisi', price: 0, emoji: '🐈'),
  ShopItem(id: 'av_tilki', category: ShopCategory.avatar, name: 'Tilki', price: 150, emoji: '🦊'),
  ShopItem(id: 'av_baykus', category: ShopCategory.avatar, name: 'Baykuş', price: 150, emoji: '🦉'),
  ShopItem(id: 'av_kaplumbaga', category: ShopCategory.avatar, name: 'Kaplumbağa', price: 150, emoji: '🐢'),
  ShopItem(id: 'av_yunus', category: ShopCategory.avatar, name: 'Yunus', price: 180, emoji: '🐬'),
  ShopItem(id: 'av_ari', category: ShopCategory.avatar, name: 'Arı', price: 180, emoji: '🐝'),
  ShopItem(id: 'av_lale', category: ShopCategory.avatar, name: 'Lale', price: 200, emoji: '🌷'),
  ShopItem(id: 'av_nazar', category: ShopCategory.avatar, name: 'Nazar boncuğu', price: 220, emoji: '🧿'),
  ShopItem(id: 'av_marti', category: ShopCategory.avatar, name: 'Martı', price: 0, emoji: '🐦'),
  ShopItem(id: 'av_ahtapot', category: ShopCategory.avatar, name: 'Ahtapot', price: 250, emoji: '🐙'),
  ShopItem(id: 'av_aslan', category: ShopCategory.avatar, name: 'Aslan', price: 250, emoji: '🦁'),
  ShopItem(id: 'av_roket', category: ShopCategory.avatar, name: 'Roket', price: 300, emoji: '🚀'),
  // Frames: rings drawn in code.
  ShopItem(
    id: 'fr_bakir',
    category: ShopCategory.frame,
    name: 'Bakır',
    price: 200,
    frame: FrameStyle([Color(0xFFB0703C), Color(0xFFE0A170), Color(0xFFB0703C)]),
  ),
  ShopItem(
    id: 'fr_gumus',
    category: ShopCategory.frame,
    name: 'Gümüş',
    price: 250,
    frame: FrameStyle([Color(0xFF8A94A6), Color(0xFFE3E8EF), Color(0xFF8A94A6)]),
  ),
  ShopItem(
    id: 'fr_altin',
    category: ShopCategory.frame,
    name: 'Altın',
    price: 350,
    frame: FrameStyle([Color(0xFFC88A00), Color(0xFFFFE07A), Color(0xFFC88A00)]),
  ),
  ShopItem(
    id: 'fr_iznik',
    category: ShopCategory.frame,
    name: 'İznik',
    price: 300,
    frame: FrameStyle([Color(0xFF1F5FA8), Color(0xFF2BB3A6), Color(0xFFD12E4A), Color(0xFF1F5FA8)]),
  ),
  ShopItem(
    id: 'fr_gunbatimi',
    category: ShopCategory.frame,
    name: 'Gün batımı',
    price: 300,
    frame: FrameStyle([Color(0xFFF17F04), Color(0xFFD12E4A), Color(0xFF8E5BD8), Color(0xFFF17F04)]),
  ),
  ShopItem(
    id: 'fr_nazar',
    category: ShopCategory.frame,
    name: 'Nazar',
    price: 400,
    frame: FrameStyle([
      Color(0xFF0D3B8C),
      Color(0xFFFFFFFF),
      Color(0xFF4FA3E0),
      Color(0xFF0D3B8C),
    ], width: 0.11),
  ),
  // Çaycı Dayı accessories (placed on the mascot tile).
  ShopItem(
    id: 'mx_gozluk',
    category: ShopCategory.mascot,
    name: 'Güneş gözlüğü',
    price: 250,
    accessory: MascotAccessory('🕶️', 0.48, 0.53, 0.34),
  ),
  ShopItem(
    id: 'mx_atki',
    category: ShopCategory.mascot,
    name: 'Atkı',
    price: 300,
    accessory: MascotAccessory('🧣', 0.47, 0.82, 0.28),
  ),
  ShopItem(
    id: 'mx_madalya',
    category: ShopCategory.mascot,
    name: 'Madalya',
    price: 350,
    accessory: MascotAccessory('🏅', 0.32, 0.88, 0.18),
  ),
  ShopItem(
    id: 'mx_lale',
    category: ShopCategory.mascot,
    name: 'Şapkada lale',
    price: 300,
    accessory: MascotAccessory('🌷', 0.70, 0.30, 0.16),
  ),
  ShopItem(
    id: 'mx_tac',
    category: ShopCategory.mascot,
    name: 'Taç',
    price: 450,
    accessory: MascotAccessory('👑', 0.48, 0.13, 0.24),
  ),
  // App accent colours. Çay kırmızısı is the default look.
  ShopItem(
    id: 'th_cay',
    category: ShopCategory.theme,
    name: 'Çay kırmızısı',
    price: 0,
    accent: ThemeAccent(Color(0xFFA63F1B), Color(0xFFE99460)),
  ),
  ShopItem(
    id: 'th_iznik',
    category: ShopCategory.theme,
    name: 'İznik mavisi',
    price: 400,
    accent: ThemeAccent(Color(0xFF1F5FA8), Color(0xFF8DB8F2)),
  ),
  ShopItem(
    id: 'th_zeytin',
    category: ShopCategory.theme,
    name: 'Zeytin yeşili',
    price: 400,
    accent: ThemeAccent(Color(0xFF4F6B2A), Color(0xFFAFC982)),
  ),
  ShopItem(
    id: 'th_lavanta',
    category: ShopCategory.theme,
    name: 'Lavanta',
    price: 450,
    accent: ThemeAccent(Color(0xFF6B4FA0), Color(0xFFC0AEEA)),
  ),
  ShopItem(
    id: 'th_lokum',
    category: ShopCategory.theme,
    name: 'Gül lokumu',
    price: 450,
    accent: ThemeAccent(Color(0xFFB0365F), Color(0xFFF29BBB)),
  ),
  streakFreezeItem,
];

final _byId = {for (final i in shopItems) i.id: i};

ShopItem? shopItem(String? id) => id == null ? null : _byId[id];

List<ShopItem> itemsIn(ShopCategory c) => [
  for (final i in shopItems)
    if (i.category == c) i,
];

/// Free items count as owned.
bool ownsItem(Wallet w, ShopItem item) => item.free || w.owns(item.id);

/// The worn item of [slot], if it is still in the catalog and owned.
ShopItem? equippedIn(Wallet w, String slot) {
  final item = shopItem(w.equipped[slot]);
  return item != null && item.category.slot == slot && ownsItem(w, item) ? item : null;
}
