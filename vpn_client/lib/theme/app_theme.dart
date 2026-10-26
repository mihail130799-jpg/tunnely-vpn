import 'package:flutter/material.dart';

/// Brand + semantic colors from DESIGN_SYSTEM.md.
abstract final class Brand {
  static const navy = Color(0xFF010333);
  static const blue = Color(0xFF3B5DFD);
  static const cyan = Color(0xFF1AB4FE);
  static const violet = Color(0xFF6E32E9);
  static const success = Color(0xFF2BD48A);
  static const warning = Color(0xFFF2B33D);
  static const danger = Color(0xFFFF5A6A);
}

/// Theme-dependent tokens not covered by Material's ColorScheme.
@immutable
class TunnelyColors extends ThemeExtension<TunnelyColors> {
  const TunnelyColors({
    required this.bgGradient,
    required this.surface,
    required this.surfaceVariant,
    required this.onSurface,
    required this.muted,
    required this.divider,
    required this.accent,
    required this.archOffOuter,
    required this.archOffInner,
    required this.archOffEdge,
    required this.portalOff,
    required this.roadOff,
  });

  final List<Color> bgGradient;
  final Color surface;
  final Color surfaceVariant;
  final Color onSurface;
  final Color muted;
  final Color divider;
  final Color accent;
  final Color archOffOuter;
  final Color archOffInner;
  final Color archOffEdge;
  final Color portalOff;
  final Color roadOff;

  static const dark = TunnelyColors(
    bgGradient: [Color(0xFF2A2FB8), Color(0xFF0A0F6A), Brand.navy],
    surface: Color(0xFF0B0F4A),
    surfaceVariant: Color(0xFF121860),
    onSurface: Colors.white,
    muted: Color(0xFF8C93C9),
    divider: Color(0x12FFFFFF),
    accent: Brand.cyan,
    archOffOuter: Color(0xFF2A3070),
    archOffInner: Color(0xFF0B0F3A),
    archOffEdge: Color(0xFF3A4290),
    portalOff: Color(0xFF4A5196),
    roadOff: Color(0x0FFFFFFF),
  );

  static const light = TunnelyColors(
    bgGradient: [Color(0xFFDCE6FF), Color(0xFFEEF2FD), Color(0xFFF7F8FD)],
    surface: Colors.white,
    surfaceVariant: Color(0xFFEEF1FB),
    onSurface: Color(0xFF0B1033),
    muted: Color(0xFF7A80A6),
    divider: Color(0x120B1033),
    accent: Brand.blue,
    archOffOuter: Color(0xFFC9D0EA),
    archOffInner: Color(0xFFEEF1FA),
    archOffEdge: Color(0xFFB6BEDF),
    portalOff: Color(0xFFAEB6D8),
    roadOff: Color(0x0F0B1033),
  );

  @override
  TunnelyColors copyWith() => this;

  @override
  TunnelyColors lerp(TunnelyColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return TunnelyColors(
      bgGradient: [for (var i = 0; i < 3; i++) c(bgGradient[i], other.bgGradient[i])],
      surface: c(surface, other.surface),
      surfaceVariant: c(surfaceVariant, other.surfaceVariant),
      onSurface: c(onSurface, other.onSurface),
      muted: c(muted, other.muted),
      divider: c(divider, other.divider),
      accent: c(accent, other.accent),
      archOffOuter: c(archOffOuter, other.archOffOuter),
      archOffInner: c(archOffInner, other.archOffInner),
      archOffEdge: c(archOffEdge, other.archOffEdge),
      portalOff: c(portalOff, other.portalOff),
      roadOff: c(roadOff, other.roadOff),
    );
  }
}

extension TunnelyThemeX on BuildContext {
  TunnelyColors get tc => Theme.of(this).extension<TunnelyColors>()!;
}

/// Inter is a variable font: weight must be passed as a `wght` variation too.
TextStyle inter(double size, FontWeight weight, {Color? color, double? letterSpacing, bool tabular = false}) =>
    TextStyle(
      fontFamily: 'Inter',
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation.weight(weight.value.toDouble())],
      color: color,
      letterSpacing: letterSpacing,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final tc = dark ? TunnelyColors.dark : TunnelyColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.blue,
    brightness: b,
    primary: dark ? Brand.cyan : Brand.blue,
    surface: tc.surface,
    onSurface: tc.onSurface,
    error: Brand.danger,
  );
  TextStyle s(double size, FontWeight w) => inter(size, w, color: tc.onSurface);
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: tc.bgGradient.last,
    extensions: [tc],
    textTheme: TextTheme(
      headlineMedium: s(28, FontWeight.w800),
      titleLarge: s(20, FontWeight.w700),
      titleMedium: s(17, FontWeight.w700),
      titleSmall: s(15, FontWeight.w600),
      bodyLarge: s(15, FontWeight.w500),
      bodyMedium: s(14, FontWeight.w500),
      bodySmall: inter(12, FontWeight.w500, color: tc.muted),
      labelLarge: s(14, FontWeight.w600),
      labelMedium: s(12, FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: tc.onSurface,
      titleTextStyle: s(17, FontWeight.w700),
    ),
    dividerTheme: DividerThemeData(color: tc.divider, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: dark ? const Color(0xFF1B2170) : const Color(0xFF0B1033),
      contentTextStyle: inter(14, FontWeight.w500, color: Colors.white),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primary : null),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tc.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      showDragHandle: true,
      dragHandleColor: tc.muted.withValues(alpha: .4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tc.surfaceVariant,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      hintStyle: inter(14, FontWeight.w500, color: tc.muted),
    ),
  );
}
