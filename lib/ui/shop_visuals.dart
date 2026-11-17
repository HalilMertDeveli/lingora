import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/shop_catalog.dart';
import '../theme.dart';
import 'avatar.dart';
import 'gold_coin.dart';
import 'mascot.dart';

/// An emoji face on a round tile (a Mağaza avatar).
class AvatarFace extends StatelessWidget {
  const AvatarFace({super.key, required this.emoji, required this.size});
  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: Brand.surface, shape: BoxShape.circle),
    child: Text(emoji, style: TextStyle(fontSize: size * 0.56, height: 1.1)),
  );
}

/// [child] inside a ring of [style] (null: no ring). The ring sits inside
/// [size], so framed and plain avatars line up.
class FramedAvatar extends StatelessWidget {
  const FramedAvatar({super.key, required this.style, required this.size, required this.child});
  final FrameStyle? style;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = style;
    if (s == null) {
      return SizedBox.square(
        dimension: size,
        child: Center(child: child),
      );
    }
    final ring = max(2.0, size * s.width);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(s.colors, ring),
        child: Padding(
          padding: EdgeInsets.all(ring + 1),
          child: FittedBox(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.colors, this.width);
  final List<Color> colors;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = SweepGradient(colors: colors, transform: const GradientRotation(-pi / 2)).createShader(rect);
    canvas.drawCircle(rect.center, (size.shortestSide - width) / 2, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.colors != colors || old.width != width;
}

/// A learner's face as friends see it: their photo, else their Mağaza
/// avatar, else [fallback]; inside their frame.
class StyledAvatar extends StatelessWidget {
  const StyledAvatar({
    super.key,
    required this.size,
    required this.fallback,
    this.photo,
    this.avatarId,
    this.frameId,
  });
  final double size;
  final Uint8List? photo;
  final String? avatarId;
  final String? frameId;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final frame = shopItem(frameId)?.frame;
    final emoji = shopItem(avatarId)?.emoji;
    final inner = frame == null ? size : size - 2 * (max(2.0, size * frame.width) + 1);
    return FramedAvatar(
      style: frame,
      size: size,
      child: PhotoAvatar(
        photo: photo,
        size: inner,
        fallback: emoji != null ? AvatarFace(emoji: emoji, size: inner) : fallback,
      ),
    );
  }
}

/// The Çaycı Dayı accessory to draw on every mascot below (the worn Mağaza
/// item). Set at the app root.
class MascotOutfitScope extends InheritedWidget {
  const MascotOutfitScope({super.key, required this.accessory, required super.child});
  final MascotAccessory? accessory;

  static MascotAccessory? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MascotOutfitScope>()?.accessory;

  @override
  bool updateShouldNotify(MascotOutfitScope old) => old.accessory != accessory;
}

/// [accessory] placed on a mascot tile of side [size].
class MascotAccessoryLayer extends StatelessWidget {
  const MascotAccessoryLayer({super.key, required this.accessory, required this.size});
  final MascotAccessory accessory;
  final double size;

  @override
  Widget build(BuildContext context) {
    final a = accessory;
    final side = size * a.size;
    return Positioned(
      left: size * a.x - side / 2,
      top: size * a.y - side / 2,
      width: side,
      height: side,
      child: IgnorePointer(
        child: FittedBox(child: Text(a.emoji, style: const TextStyle(height: 1))),
      ),
    );
  }
}

/// The picture of a Mağaza item in its card.
class ShopItemPreview extends StatelessWidget {
  const ShopItemPreview({super.key, required this.item, this.size = 64});
  final ShopItem item;
  final double size;

  @override
  Widget build(BuildContext context) => switch (item.category) {
    ShopCategory.avatar => AvatarFace(emoji: item.emoji ?? '⭐', size: size),
    ShopCategory.frame => FramedAvatar(
      style: item.frame,
      size: size,
      child: Icon(Icons.person_rounded, color: Brand.muted),
    ),
    ShopCategory.mascot => SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.18),
            child: Image.asset(mascotAsset, width: size, height: size),
          ),
          if (item.accessory != null) MascotAccessoryLayer(accessory: item.accessory!, size: size),
        ],
      ),
    ),
    ShopCategory.theme => _Swatch(accent: item.accent!, size: size),
    ShopCategory.freeze => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF4FA3E0).withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Text(item.emoji ?? '🧊', style: TextStyle(fontSize: size * 0.5)),
    ),
  };
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.accent, required this.size});
  final ThemeAccent accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.palette.isDark ? accent.dark : accent.light;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Brand.card,
        borderRadius: BorderRadius.circular(size * 0.2),
        border: Border.all(color: Brand.line),
      ),
      padding: EdgeInsets.all(size * 0.14),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(size * 0.1)),
              alignment: Alignment.center,
              child: Icon(Icons.check_rounded, color: onColor(c), size: size * 0.3),
            ),
          ),
          SizedBox(height: size * 0.06),
          Container(
            height: size * 0.12,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(size),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small coin + price, or a lock when [locked].
class PriceTag extends StatelessWidget {
  const PriceTag({super.key, required this.price, this.locked = false});
  final int price;
  final bool locked;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (locked) ...[Icon(Icons.lock_rounded, size: 14, color: Brand.muted), const SizedBox(width: 2)],
      GoldAmount(price, size: 14, color: locked ? Brand.muted : null),
    ],
  );
}
