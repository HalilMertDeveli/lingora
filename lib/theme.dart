import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class Brand {
  static const primary = Color(0xFF6C4CF1);
  static const accent = Color(0xFFFFB020);
  static const success = Color(0xFF1FA971);
  static const successBg = Color(0xFFE3F7EE);
  static const error = Color(0xFFE5484D);
  static const errorBg = Color(0xFFFDECEC);
  static const heart = Color(0xFFE5484D);
  static const streak = Color(0xFFFF7A1A);
  static const xp = Color(0xFFFFB020);
  static const ink = Color(0xFF1E1B2E);
  static const muted = Color(0xFF8A8799);
  static const line = Color(0xFFE7E5EF);
  static const surface = Color(0xFFF7F6FB);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.primary,
    primary: Brand.primary,
    surface: Colors.white,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Brand.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.w800, color: Brand.ink),
      titleLarge: TextStyle(fontWeight: FontWeight.w800, color: Brand.ink),
      titleMedium: TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
      bodyLarge: TextStyle(color: Brand.ink),
      bodyMedium: TextStyle(color: Brand.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: Brand.line, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    ),
  );
}

/// Rounded card with a 3D bottom edge that highlights when selected and
/// sinks slightly while pressed.
class TapCard extends StatefulWidget {
  const TapCard({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
    this.color,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final Color? color;
  final EdgeInsets padding;

  @override
  State<TapCard> createState() => _TapCardState();
}

class _TapCardState extends State<TapCard> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? Brand.primary;
    final border = widget.selected ? c : Brand.line;
    final edge = widget.selected ? c.withValues(alpha: 0.55) : const Color(0xFFDAD7E5);
    final depth = widget.onTap == null ? 2.0 : (_down ? 0.0 : 4.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        margin: EdgeInsets.only(top: 4 - depth.clamp(0, 4)),
        decoration: BoxDecoration(
          color: widget.selected ? Color.alphaBlend(c.withValues(alpha: 0.10), Colors.white) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 2),
          boxShadow: [BoxShadow(color: edge, offset: Offset(0, depth))],
        ),
        padding: widget.padding,
        // Lets ListTiles inside paint their ink above the card colour.
        child: Material(type: MaterialType.transparency, child: widget.child),
      ),
    );
  }
}
