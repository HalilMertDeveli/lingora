import 'package:flutter/material.dart';

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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

/// Rounded card with a 2px border that highlights when selected.
class TapCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final c = color ?? Brand.primary;
    return Material(
      color: selected ? c.withValues(alpha: 0.10) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? c : Brand.line, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
