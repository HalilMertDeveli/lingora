import 'package:flutter/painting.dart';

import 'wallet.dart';

/// Mağaza categories, in tab order.
enum ShopCategory {
  avatar('Avatarlar', WalletSlot.avatar),
  frame('Çerçeveler', WalletSlot.frame),
  mascot('Çaycı Dayı', WalletSlot.mascot),
  pofuduk('Pofuduk', WalletSlot.pofuduk),
  theme('Temalar', WalletSlot.theme),
  freeze('Seri dondurma', null);

  const ShopCategory(this.label, this.slot);

  /// Tabs shown in the Mağaza. Çocuk modu has no Çaycı Dayı tab (kids only
  /// ever see Pofuduk) and adults no Pofuduk tab.
  static List<ShopCategory> tabs({required bool kid}) => [
    for (final c in values)
      if (kid ? c != mascot : c != pofuduk) c,
  ];
  final String label;

  /// Where the item is worn; null for consumables.
  final String? slot;

  /// "Nerede görünür?": where a worn item of this kind shows.
  String get where => switch (this) {
    avatar => 'Profilin, üst bar, ders sonu, lig satırın ve arkadaşlarının listesi',
    frame => 'Avatarının ya da fotoğrafının çevresinde: profil, üst bar, ders sonu, lig ve arkadaşlar',
    mascot => 'Çaycı Dayı\'nın göründüğü her yer (yetişkin modu)',
    pofuduk => 'Pofuduk\'un göründüğü her yer (Çocuk modu)',
    theme => 'Bütün uygulama: butonlar, seçimler ve vurgular',
    freeze => 'Bir gün çalışamazsan serini otomatik korur',
  };
}

/// How rare an item is: a coloured edge and a label in the Mağaza.
enum Rarity {
  common('Sıradan', Color(0xFF8A94A6)),
  rare('Nadir', Color(0xFF2F6FDB)),
  epic('Efsane', Color(0xFFB0459E));

  const Rarity(this.label, this.color);
  final String label;
  final Color color;
}

/// How a frame moves (off when the phone asks for less motion).
enum FrameMotion { none, spin, pulse }

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
  const FrameStyle(this.colors, {this.width = 0.09, this.motion = FrameMotion.none});
  final List<Color> colors;
  final FrameMotion motion;

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
    Rarity? rarity,
    // Named parameters cannot be private.
    // ignore: prefer_initializing_formals
  }) : _rarity = rarity;

  final Rarity? _rarity;

  /// Set by hand for special items, else by price.
  Rarity get rarity =>
      _rarity ??
      (price >= 400
          ? Rarity.epic
          : price >= 250
          ? Rarity.rare
          : Rarity.common);

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
  ShopItem(id: 'av_kirpi', category: ShopCategory.avatar, name: 'Kirpi', price: 160, emoji: '🦔'),
  ShopItem(id: 'av_flamingo', category: ShopCategory.avatar, name: 'Flamingo', price: 220, emoji: '🦩'),
  ShopItem(id: 'av_karpuz', category: ShopCategory.avatar, name: 'Karpuz', price: 180, emoji: '🍉'),
  ShopItem(id: 'av_balina', category: ShopCategory.avatar, name: 'Balina', price: 280, emoji: '🐳'),
  ShopItem(id: 'av_ejderha', category: ShopCategory.avatar, name: 'Ejderha', price: 450, emoji: '🐉'),
  ShopItem(id: 'av_unicorn', category: ShopCategory.avatar, name: 'Tek boynuzlu at', price: 450, emoji: '🦄'),
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
  // Animated frames: the ring turns or glows (still with reduced motion).
  ShopItem(
    id: 'fr_gokkusagi',
    category: ShopCategory.frame,
    name: 'Dönen gökkuşağı',
    price: 500,
    frame: FrameStyle([
      Color(0xFFE53935),
      Color(0xFFFFB300),
      Color(0xFF43A047),
      Color(0xFF1E88E5),
      Color(0xFF8E24AA),
      Color(0xFFE53935),
    ], motion: FrameMotion.spin),
  ),
  ShopItem(
    id: 'fr_ates',
    category: ShopCategory.frame,
    name: 'Ateş halkası',
    price: 450,
    frame: FrameStyle(
      [Color(0xFFFF6F00), Color(0xFFFFD54F), Color(0xFFD84315), Color(0xFFFF6F00)],
      width: 0.11,
      motion: FrameMotion.pulse,
    ),
  ),
  ShopItem(
    id: 'fr_deniz',
    category: ShopCategory.frame,
    name: 'Dalgalı deniz',
    price: 400,
    frame: FrameStyle([
      Color(0xFF006064),
      Color(0xFF4DD0E1),
      Color(0xFFE0F7FA),
      Color(0xFF006064),
    ], motion: FrameMotion.spin),
  ),
  // Pofuduk outfits (Çocuk modu only, drawn on the Pofuduk artwork).
  ShopItem(
    id: 'px_sapka',
    category: ShopCategory.pofuduk,
    name: 'Silindir şapka',
    price: 200,
    accessory: MascotAccessory('🎩', 0.5, 0.06, 0.3),
  ),
  ShopItem(
    id: 'px_kurdele',
    category: ShopCategory.pofuduk,
    name: 'Kurdele',
    price: 180,
    accessory: MascotAccessory('🎀', 0.8, 0.1, 0.22),
  ),
  ShopItem(
    id: 'px_kep',
    category: ShopCategory.pofuduk,
    name: 'Kep',
    price: 250,
    accessory: MascotAccessory('🧢', 0.5, 0.07, 0.3),
  ),
  ShopItem(
    id: 'px_cicek',
    category: ShopCategory.pofuduk,
    name: 'Papatya',
    price: 160,
    accessory: MascotAccessory('🌼', 0.2, 0.12, 0.2),
  ),
  ShopItem(
    id: 'px_tac',
    category: ShopCategory.pofuduk,
    name: 'Prens tacı',
    price: 400,
    accessory: MascotAccessory('👑', 0.5, 0.04, 0.26),
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

/// Off the price of the week's featured items ("Haftanın ürünleri").
const featuredDiscount = 0.2;

/// Three items featured this week, the same for everyone and all week
/// (Monday to Monday): one avatar, one frame and one other. Free items and
/// the streak freeze are never featured. [kid] swaps Çaycı Dayı for Pofuduk.
List<ShopItem> featuredItems(DateTime now, {bool kid = false}) {
  final d = DateTime(now.year, now.month, now.day);
  final monday = d.subtract(Duration(days: d.weekday - DateTime.monday));
  final week = monday.difference(DateTime(2026)).inDays ~/ 7;
  List<ShopItem> pool(bool Function(ShopItem) test) => [
    for (final i in shopItems)
      if (!i.free && !i.consumable && test(i)) i,
  ];
  final avatars = pool((i) => i.category == ShopCategory.avatar);
  final frames = pool((i) => i.category == ShopCategory.frame);
  final others = pool(
    (i) =>
        i.category == ShopCategory.theme || i.category == (kid ? ShopCategory.pofuduk : ShopCategory.mascot),
  );
  ShopItem pick(List<ShopItem> list, int salt) =>
      list[((week * 7 + salt) % list.length + list.length) % list.length];
  return [pick(avatars, 1), pick(frames, 3), pick(others, 5)];
}

/// Whether [item] is featured this week (in either mode).
bool isFeatured(ShopItem item, DateTime now) =>
    featuredItems(now).any((f) => f.id == item.id) ||
    featuredItems(now, kid: true).any((f) => f.id == item.id);

/// Price today: featured items cost [featuredDiscount] less.
int priceOf(ShopItem item, DateTime now) =>
    isFeatured(item, now) ? (item.price * (1 - featuredDiscount)).round() : item.price;

/// Whether the learner shows their Mağaza avatar instead of their photo.
bool prefersAvatar(Wallet w) =>
    w.equipped[WalletSlot.face] == WalletSlot.faceAvatar && equippedIn(w, WalletSlot.avatar) != null;
