import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/shop_catalog.dart';
import '../theme.dart';
import 'avatar.dart';
import 'gold_coin.dart';
import 'mascot.dart';
import 'motion.dart';

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
/// [size], so framed and plain avatars line up. Animated frames turn or
/// glow, unless the phone asks for less motion.
class FramedAvatar extends StatefulWidget {
  const FramedAvatar({super.key, required this.style, required this.size, required this.child});
  final FrameStyle? style;
  final double size;
  final Widget child;

  @override
  State<FramedAvatar> createState() => _FramedAvatarState();
}

class _FramedAvatarState extends State<FramedAvatar> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(FramedAvatar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final moving = (widget.style?.motion ?? FrameMotion.none) != FrameMotion.none && loopsEnabled(context);
    if (moving) {
      _c ??= AnimationController(vsync: this, duration: const Duration(seconds: 4));
      if (!_c!.isAnimating) _c!.repeat();
    } else {
      _c?.stop();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.style;
    final size = widget.size;
    if (s == null) {
      return SizedBox.square(
        dimension: size,
        child: Center(child: widget.child),
      );
    }
    final ring = max(2.0, size * s.width);
    final inner = Padding(
      padding: EdgeInsets.all(ring + 1),
      child: FittedBox(child: widget.child),
    );
    final c = _c;
    return SizedBox.square(
      dimension: size,
      child: c == null || !c.isAnimating
          ? CustomPaint(painter: _RingPainter(s.colors, ring, s.motion, 0), child: inner)
          : AnimatedBuilder(
              animation: c,
              child: inner,
              builder: (_, child) =>
                  CustomPaint(painter: _RingPainter(s.colors, ring, s.motion, c.value), child: child),
            ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.colors, this.width, this.motion, this.t);
  final List<Color> colors;
  final double width;
  final FrameMotion motion;

  /// Animation phase 0..1.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final turn = motion == FrameMotion.spin ? t * 2 * pi : 0.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = SweepGradient(
        colors: colors,
        transform: GradientRotation(-pi / 2 + turn),
      ).createShader(rect);
    final radius = (size.shortestSide - width) / 2;
    if (motion == FrameMotion.pulse) {
      // A soft glow that breathes.
      final glow = 0.5 + 0.5 * sin(t * 2 * pi * 2);
      canvas.drawCircle(
        rect.center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * (1.2 + glow)
          ..color = colors.first.withValues(alpha: 0.25 + 0.25 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.8),
      );
    }
    canvas.drawCircle(rect.center, radius, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.colors != colors || old.width != width || old.t != t || old.motion != motion;
}

/// A learner's face: their photo, else their Mağaza avatar, else
/// [fallback]; inside their frame. With [preferAvatar] the Mağaza avatar
/// is shown even when there is a photo (Profil > Fotoğraf / Avatar).
class StyledAvatar extends StatelessWidget {
  const StyledAvatar({
    super.key,
    required this.size,
    required this.fallback,
    this.photo,
    this.avatarId,
    this.frameId,
    this.preferAvatar = false,
  });
  final double size;
  final Uint8List? photo;
  final String? avatarId;
  final String? frameId;
  final bool preferAvatar;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final frame = shopItem(frameId)?.frame;
    final emoji = shopItem(avatarId)?.emoji;
    final inner = frame == null ? size : size - 2 * (max(2.0, size * frame.width) + 1);
    final face = emoji != null ? AvatarFace(emoji: emoji, size: inner) : null;
    return FramedAvatar(
      style: frame,
      size: size,
      child: preferAvatar && face != null
          ? face
          : PhotoAvatar(photo: photo, size: inner, fallback: face ?? fallback),
    );
  }
}

/// The worn mascot accessories, drawn on every mascot below: Çaycı Dayı's
/// ([dayi], adult mode) and Pofuduk's ([pofuduk], Çocuk modu). Set at the
/// app root.
class MascotOutfitScope extends InheritedWidget {
  const MascotOutfitScope({super.key, required this.accessory, this.pofuduk, required super.child});

  /// Çaycı Dayı's accessory.
  final MascotAccessory? accessory;
  final MascotAccessory? pofuduk;

  static MascotAccessory? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MascotOutfitScope>()?.accessory;

  static MascotAccessory? pofudukOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MascotOutfitScope>()?.pofuduk;

  @override
  bool updateShouldNotify(MascotOutfitScope old) => old.accessory != accessory || old.pofuduk != pofuduk;
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

/// [image] of side [size] with [accessory] on top.
Widget dressedMascot(Widget image, double size, MascotAccessory? accessory) => accessory == null
    ? image
    : SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            image,
            MascotAccessoryLayer(accessory: accessory, size: size),
          ],
        ),
      );

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
    ShopCategory.mascot => dressedMascot(
      ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.18),
        // Çocuk modu shows only Pofuduk, never Çaycı Dayı.
        child: Image.asset(context.isKid ? pofudukAvatar : mascotAsset, width: size, height: size),
      ),
      size,
      item.accessory,
    ),
    ShopCategory.pofuduk => dressedMascot(
      Image.asset(pofudukPose(Mood.idle), width: size, height: size, fit: BoxFit.contain),
      size,
      item.accessory,
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
