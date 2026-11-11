import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/app_settings.dart';
import 'ui/transitions.dart';

export 'data/app_settings.dart' show AppMode, ThemePref;

// ---------------------------------------------------------------------------
// Design tokens. See docs/tasarim.md for how to use them.
// ---------------------------------------------------------------------------

/// Every colour the app uses, for one mode (adult / kid) and one brightness.
@immutable
class Palette {
  const Palette({
    required this.kid,
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.accentBg,
    required this.success,
    required this.successBg,
    required this.error,
    required this.errorBg,
    required this.streak,
    required this.xp,
    required this.info,
    required this.ink,
    required this.muted,
    required this.line,
    required this.surface,
    required this.card,
    required this.background,
    required this.edge,
    this.mascot = const Color(0xFFB85A00),
    this.onMascot = Colors.white,
    this.mascotBg = const Color(0xFFFFF3E6),
  });

  /// Çocuk modu palette.
  final bool kid;
  final Brightness brightness;

  /// Brand colour: buttons, selection, links.
  final Color primary;
  final Color onPrimary;

  /// Warm highlight (amber): daily goal, tips.
  final Color accent;

  /// Soft amber background for tips and "more natural" hints.
  final Color accentBg;
  final Color success;
  final Color successBg;
  final Color error;
  final Color errorBg;
  final Color streak;
  final Color xp;
  final Color info;

  /// Main text.
  final Color ink;

  /// Secondary text and icons.
  final Color muted;

  /// Borders and dividers.
  final Color line;

  /// Subtle filled areas: inputs, chips, progress tracks.
  final Color surface;

  /// Card / sheet background.
  final Color card;

  /// Page background.
  final Color background;

  /// Kid mode's darker 3D edge under neutral cards.
  final Color edge;

  /// Mascot orange: the brand accent for sign-in, mascot moments and the
  /// app icon. Dark palettes use a lighter tone with dark text on it.
  final Color mascot;
  final Color onMascot;

  /// Soft orange fill (inputs, chips) behind mascot-accented content.
  final Color mascotBg;

  /// Çaycı Dayı's orange tile and the launcher icon background.
  static const mascotOrange = Color(0xFFF17F04);

  bool get isDark => brightness == Brightness.dark;

  /// Softer version of a bright content colour (unit, level, track colours)
  /// for adult mode. Kid palettes return it unchanged.
  Color tone(Color c) {
    if (kid) return c;
    final h = HSLColor.fromColor(c);
    final s = (h.saturation * 0.55).clamp(0.0, 0.6);
    return h.withSaturation(s).withLightness(isDark ? 0.68 : 0.42).toColor();
  }

  /// Calm, premium look for students and professionals.
  static const adultLight = Palette(
    kid: false,
    brightness: Brightness.light,
    primary: Color(0xFFE06C00),
    onPrimary: Colors.white,
    accent: Color(0xFFD9900B),
    accentBg: Color(0xFFFCF3E1),
    success: Color(0xFF13885A),
    successBg: Color(0xFFE8F5EE),
    error: Color(0xFFD03A33),
    errorBg: Color(0xFFFCEDEC),
    streak: Color(0xFFE2672A),
    xp: Color(0xFFD9900B),
    info: Color(0xFF2F6FD6),
    ink: Color(0xFF14171F),
    muted: Color(0xFF636B7A),
    line: Color(0xFFE3E6EC),
    surface: Color(0xFFF2F4F7),
    card: Colors.white,
    background: Color(0xFFF8F9FB),
    edge: Color(0xFFD5D9E1),
  );

  static const adultDark = Palette(
    kid: false,
    brightness: Brightness.dark,
    primary: Color(0xFFF39A3D),
    onPrimary: Color(0xFF1A0E00),
    accent: Color(0xFFF0B13E),
    accentBg: Color(0xFF2A2214),
    success: Color(0xFF45C08A),
    successBg: Color(0xFF15281F),
    error: Color(0xFFF2766C),
    errorBg: Color(0xFF2E1816),
    streak: Color(0xFFF08A52),
    xp: Color(0xFFF0B13E),
    info: Color(0xFF6EA2F2),
    ink: Color(0xFFE8EAF0),
    muted: Color(0xFF9AA2B1),
    line: Color(0xFF2B303B),
    surface: Color(0xFF1F232C),
    card: Color(0xFF181B22),
    background: Color(0xFF101217),
    edge: Color(0xFF0A0B0F),
    mascot: Color(0xFFF39A3D),
    onMascot: Color(0xFF1A0E00),
    mascotBg: Color(0xFF2E2010),
  );

  /// Playful look (Çocuk modu): the original Dilbaz colours.
  static const kidLight = Palette(
    kid: true,
    brightness: Brightness.light,
    primary: Color(0xFFF17F04),
    onPrimary: Colors.white,
    accent: Color(0xFFFFB020),
    accentBg: Color(0xFFFFF4DC),
    success: Color(0xFF1FA971),
    successBg: Color(0xFFE3F7EE),
    error: Color(0xFFE5484D),
    errorBg: Color(0xFFFDECEC),
    streak: Color(0xFFFF7A1A),
    xp: Color(0xFFFFB020),
    info: Color(0xFF2F80ED),
    ink: Color(0xFF1E1B2E),
    muted: Color(0xFF8A8799),
    line: Color(0xFFE7E5EF),
    surface: Color(0xFFF7F6FB),
    card: Colors.white,
    background: Colors.white,
    edge: Color(0xFFDAD7E5),
  );

  static const kidDark = Palette(
    kid: true,
    brightness: Brightness.dark,
    primary: Color(0xFFFF9F43),
    onPrimary: Color(0xFF1A0E00),
    accent: Color(0xFFFFBE45),
    accentBg: Color(0xFF33290F),
    success: Color(0xFF34C77B),
    successBg: Color(0xFF16301F),
    error: Color(0xFFFF6B6F),
    errorBg: Color(0xFF3A1A1C),
    streak: Color(0xFFFF8B3D),
    xp: Color(0xFFFFBE45),
    info: Color(0xFF5B9DF5),
    ink: Color(0xFFF0EDF9),
    muted: Color(0xFFA6A2B8),
    line: Color(0xFF342E47),
    surface: Color(0xFF242034),
    card: Color(0xFF1E1A2B),
    background: Color(0xFF15121F),
    edge: Color(0xFF0D0B14),
    mascot: Color(0xFFF39A3D),
    onMascot: Color(0xFF1A0E00),
    mascotBg: Color(0xFF2E2010),
  );

  static Palette of(AppMode mode, Brightness b) => switch ((mode, b)) {
    (AppMode.adult, Brightness.light) => adultLight,
    (AppMode.adult, Brightness.dark) => adultDark,
    (AppMode.kid, Brightness.light) => kidLight,
    (AppMode.kid, Brightness.dark) => kidDark,
  };
}

/// 4-pt spacing scale.
abstract final class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii. Kid mode uses the larger values for cards and buttons.
abstract final class Radii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
}

/// Motion durations. Adult mode keeps animations short and subtle.
abstract final class AppDurations {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 220);
}

/// Mode + palette, available from the theme: `context.lingora`.
@immutable
class LingoraTheme extends ThemeExtension<LingoraTheme> {
  const LingoraTheme({required this.mode, required this.palette});
  final AppMode mode;
  final Palette palette;

  bool get isKid => mode == AppMode.kid;
  double get cardRadius => isKid ? Radii.lg : Radii.md;
  double get buttonRadius => isKid ? Radii.lg : Radii.md;

  /// Softer version of a bright content colour (unit colours, track colours)
  /// so adult screens don't look like a candy box. Kid mode keeps it as is.
  Color tone(Color c) => palette.tone(c);

  /// Background for a hero banner with white text on it (unit headers,
  /// course/exam headers). Kid: bright colour with a soft gradient. Adult:
  /// a deep, muted solid tone that keeps white text readable in both themes.
  BoxDecoration hero(Color c, {Color? from}) {
    if (isKid) {
      return BoxDecoration(
        gradient: from == null ? null : LinearGradient(colors: [from, c]),
        color: from == null ? c : null,
        borderRadius: BorderRadius.circular(Radii.xl),
      );
    }
    final h = HSLColor.fromColor(c);
    final s = (h.saturation * 0.5).clamp(0.0, 0.5);
    final l = palette.isDark ? 0.27 : 0.34;
    return BoxDecoration(
      color: h.withSaturation(s).withLightness(l).toColor(),
      borderRadius: BorderRadius.circular(Radii.lg),
    );
  }

  @override
  LingoraTheme copyWith({AppMode? mode, Palette? palette}) =>
      LingoraTheme(mode: mode ?? this.mode, palette: palette ?? this.palette);

  @override
  LingoraTheme lerp(LingoraTheme? other, double t) => other == null || t < 0.5 ? this : other;
}

extension LingoraContext on BuildContext {
  LingoraTheme get lingora =>
      Theme.of(this).extension<LingoraTheme>() ?? LingoraTheme(mode: AppMode.adult, palette: Brand.palette);
  Palette get palette => lingora.palette;
  bool get isKid => lingora.isKid;
}

/// Legacy colour names, kept so existing screens adapt automatically: every
/// getter reads the active palette (mode + light/dark). New code should
/// prefer `context.palette`.
abstract final class Brand {
  static Palette _active = Palette.adultLight;
  static Palette get palette => _active;

  /// Called by the app root before building with a new palette.
  static void apply(Palette p) => _active = p;

  static Color get primary => _active.primary;
  static Color get onPrimary => _active.onPrimary;
  static Color get accent => _active.accent;
  static Color get accentBg => _active.accentBg;
  static Color get success => _active.success;
  static Color get successBg => _active.successBg;
  static Color get error => _active.error;
  static Color get errorBg => _active.errorBg;
  static Color get heart => _active.error;
  static Color get streak => _active.streak;
  static Color get xp => _active.xp;
  static Color get info => _active.info;
  static Color get mascot => _active.mascot;
  static Color get onMascot => _active.onMascot;
  static Color get mascotBg => _active.mascotBg;
  static Color get ink => _active.ink;
  static Color get muted => _active.muted;
  static Color get line => _active.line;
  static Color get surface => _active.surface;
  static Color get card => _active.card;
  static Color get background => _active.background;
  static bool get isKid => _active.kid;
  static Color tone(Color c) => _active.tone(c);
}

/// Adult mode maps heavy weights (800/900, used for the playful look) to
/// Bold, so inline `FontWeight.w900` reads as a calm heading.
const _adultFont = 'LingoraSans';
const _kidFont = 'Inter';

ThemeData buildTheme({AppMode mode = AppMode.adult, Brightness brightness = Brightness.light}) {
  final p = Palette.of(mode, brightness);
  final kid = mode == AppMode.kid;
  final r = kid ? Radii.lg : Radii.md;
  final scheme = ColorScheme.fromSeed(
    seedColor: p.primary,
    brightness: brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    secondary: p.accent,
    error: p.error,
    surface: p.card,
    onSurface: p.ink,
    onSurfaceVariant: p.muted,
    outline: p.line,
    outlineVariant: p.line,
  );
  // In adult mode w800 renders with the Bold file (see pubspec "LingoraSans").
  const heavy = FontWeight.w800;
  final semi = kid ? FontWeight.w700 : FontWeight.w600;
  TextStyle s(double size, FontWeight w, {double? h, double ls = 0}) =>
      TextStyle(fontSize: size, fontWeight: w, height: h, letterSpacing: ls, color: p.ink);
  final textTheme = TextTheme(
    displaySmall: s(34, heavy, h: 1.15, ls: -0.6),
    headlineMedium: s(28, heavy, h: 1.2, ls: -0.5),
    headlineSmall: s(24, heavy, h: 1.25, ls: -0.3),
    titleLarge: s(20, semi, h: 1.3, ls: -0.2),
    titleMedium: s(16, semi, h: 1.35),
    titleSmall: s(14, semi, h: 1.35),
    bodyLarge: s(16, FontWeight.w400, h: 1.5),
    bodyMedium: s(14, FontWeight.w400, h: 1.45),
    bodySmall: s(12, FontWeight.w400, h: 1.4).copyWith(color: p.muted),
    labelLarge: s(14, semi, ls: 0.1),
    labelMedium: s(12, FontWeight.w500, ls: 0.2),
    labelSmall: s(11, FontWeight.w600, ls: 0.4),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kid ? _kidFont : _adultFont,
    textTheme: textTheme,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    dividerColor: p.line,
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    extensions: [LingoraTheme(mode: mode, palette: p)],
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge,
      systemOverlayStyle: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: p.card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r),
        side: BorderSide(color: p.line),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.primary.withValues(alpha: p.isDark ? 0.22 : 0.12),
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (st) => TextStyle(
          fontSize: 12,
          fontWeight: st.contains(WidgetState.selected) ? semi : FontWeight.w500,
          color: st.contains(WidgetState.selected) ? p.ink : p.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (st) => IconThemeData(color: st.contains(WidgetState.selected) ? p.primary : p.muted),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: p.card,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.isDark ? p.surface : p.ink,
      contentTextStyle: TextStyle(color: p.isDark ? p.ink : p.card, fontFamily: kid ? _kidFont : _adultFont),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.card,
      selectedColor: p.primary.withValues(alpha: p.isDark ? 0.25 : 0.12),
      side: BorderSide(color: p.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
      labelStyle: TextStyle(color: p.ink, fontWeight: FontWeight.w500),
      checkmarkColor: p.primary,
    ),
    listTileTheme: ListTileThemeData(iconColor: p.muted, textColor: p.ink),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: DilbazPageTransitionsBuilder(),
        TargetPlatform.iOS: DilbazPageTransitionsBuilder(fallback: CupertinoPageTransitionsBuilder()),
        TargetPlatform.windows: DilbazPageTransitionsBuilder(),
        TargetPlatform.macOS: DilbazPageTransitionsBuilder(fallback: CupertinoPageTransitionsBuilder()),
        TargetPlatform.linux: DilbazPageTransitionsBuilder(),
      },
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary, linearTrackColor: p.line),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size.fromHeight(kid ? 54 : 52),
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
        textStyle: TextStyle(fontSize: 16, fontWeight: kid ? FontWeight.w800 : FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size.fromHeight(kid ? 54 : 52),
        foregroundColor: p.ink,
        side: BorderSide(color: p.line, width: kid ? 2 : 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
        textStyle: TextStyle(fontSize: 16, fontWeight: kid ? FontWeight.w700 : FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.primary,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        side: BorderSide(color: p.line),
        selectedBackgroundColor: p.primary.withValues(alpha: p.isDark ? 0.25 : 0.12),
        selectedForegroundColor: p.ink,
        foregroundColor: p.muted,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(r), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide(color: p.primary, width: 1.5),
      ),
      hintStyle: TextStyle(color: p.muted),
    ),
  );
}

/// Card used everywhere. Adult mode: flat card with a hairline border and a
/// soft shadow. Kid mode: chunky card with a 3D bottom edge that sinks while
/// pressed. Selected cards get a primary (or [color]) border and tint.
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
    final lt = context.lingora;
    final p = lt.palette;
    final c = widget.color ?? p.primary;
    final tint = Color.alphaBlend(c.withValues(alpha: p.isDark ? 0.16 : 0.08), p.card);
    final BoxDecoration deco;
    double margin = 0;
    if (!lt.isKid && widget.onTap != null) {
      // Adult choice cards: a thinner 3D lip that sinks while pressed.
      final edge = widget.selected ? edgeOf3d(c) : (p.isDark ? p.edge : p.line);
      final depth = _down ? 0.0 : 3.0;
      margin = 3 - depth;
      deco = BoxDecoration(
        color: widget.selected ? tint : p.card,
        borderRadius: BorderRadius.circular(Radii.md + 2),
        border: Border.all(color: widget.selected ? c : p.line, width: 2),
        boxShadow: [BoxShadow(color: edge, offset: Offset(0, depth))],
      );
    } else if (lt.isKid) {
      final edge = widget.selected ? c.withValues(alpha: 0.55) : p.edge;
      final depth = widget.onTap == null ? 2.0 : (_down ? 0.0 : 4.0);
      margin = 4 - depth.clamp(0, 4);
      deco = BoxDecoration(
        color: widget.selected ? tint : p.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: widget.selected ? c : p.line, width: 2),
        boxShadow: [BoxShadow(color: edge, offset: Offset(0, depth))],
      );
    } else {
      final pressed = _down ? Color.alphaBlend(p.ink.withValues(alpha: 0.04), p.card) : p.card;
      deco = BoxDecoration(
        color: widget.selected ? tint : pressed,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: widget.selected ? c : p.line, width: widget.selected ? 1.5 : 1),
        boxShadow: p.isDark || widget.selected
            ? null
            : const [BoxShadow(color: Color(0x0A101828), blurRadius: 3, offset: Offset(0, 1))],
      );
    }
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
        duration: Duration(milliseconds: lt.isKid ? 90 : 120),
        margin: EdgeInsets.only(top: margin),
        decoration: deco,
        padding: widget.padding,
        // Lets ListTiles inside paint their ink above the card colour.
        child: Material(type: MaterialType.transparency, child: widget.child),
      ),
    );
  }
}

/// Shows an emoji in kid mode and a Material icon otherwise. Use it for
/// decorative pictograms in headers and list leading slots.
class Glyph extends StatelessWidget {
  const Glyph({super.key, required this.emoji, required this.icon, this.size = 28, this.color});
  final String emoji;
  final IconData icon;
  final double size;

  /// Icon colour (adult mode). Defaults to primary.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (context.isKid) return Text(emoji, style: TextStyle(fontSize: size));
    return Icon(icon, size: size * 0.9, color: color ?? context.palette.primary);
  }
}

/// Icon in a soft tinted rounded square: the adult replacement for big emoji.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.color, this.size = 40, this.emoji});
  final IconData icon;
  final Color? color;
  final double size;

  /// When set, kid mode shows this emoji instead of the icon.
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.primary;
    if (context.isKid && emoji != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(emoji!, style: TextStyle(fontSize: size * 0.7)),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: p.isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(size * (context.isKid ? 0.5 : 0.28)),
      ),
      child: Icon(icon, color: c, size: size * 0.55),
    );
  }
}

/// Small caps section label ("KURSLAR", "ÜNİTE 1").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: color ?? context.palette.muted,
      fontWeight: context.isKid ? FontWeight.w900 : FontWeight.w600,
      fontSize: 12,
      letterSpacing: context.isKid ? 1 : 0.8,
    ),
  );
}

/// Keeps the global [Brand] palette in sync with the app's mode and
/// brightness. When the palette changes, every widget below is rebuilt so
/// widgets that read `Brand.*` (instead of the theme) pick up the change
/// without losing state.
class PaletteScope extends StatefulWidget {
  const PaletteScope({super.key, required this.palette, required this.child});
  final Palette palette;
  final Widget child;

  @override
  State<PaletteScope> createState() => _PaletteScopeState();
}

class _PaletteScopeState extends State<PaletteScope> {
  Palette? _built;

  @override
  Widget build(BuildContext context) {
    Brand.apply(widget.palette);
    if (_built != null && !identical(_built, widget.palette)) {
      void mark(Element e) {
        e.markNeedsBuild();
        e.visitChildren(mark);
      }

      (context as Element).visitChildren(mark);
    }
    _built = widget.palette;
    return widget.child;
  }
}

/// Readable text/icon colour on top of [c] (white on deep colours, near-black
/// on light ones such as dark-mode tones).
Color onColor(Color c) => c.computeLuminance() > 0.4 ? const Color(0xFF111318) : Colors.white;

/// Emoji prefix shown only in Çocuk modu: `'${kidEmoji('💡')}Daha doğal'`.
String kidEmoji(String emoji) => Brand.isKid ? '$emoji ' : '';

/// Darker shade of [c] for a selected 3D card's lip (same rule as `edgeOf`).
Color edgeOf3d(Color c) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness - 0.14).clamp(0.0, 1.0)).toColor();
}
