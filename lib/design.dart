// The Bortle look, shared with the allskyhub app (its lib/design.dart, copied on purpose
// rather than shared, docs/CONCEPT.md): always dark, the night sky behind every page,
// glassy cards, pill buttons, Space Grotesk for titles.
//
// Bortle adds the red light mode: at the telescope a blue screen costs the eye its dark
// adaptation, so the whole app can turn deep red on black. Widgets therefore take their
// colours from the theme (`Theme.of(context)` and `context.tones`), never from the
// day palette's constants directly.

import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// The day palette (allskyhub's tokens.css).
abstract final class Sky {
  static const bg = Color(0xFF04060F);
  static const surface = Color(0x9E111830);
  static const surface2 = Color(0x8C1C2648);
  static const line = Color(0x2E7AA2F7);
  static const text = Color(0xFFEEF1FB);
  static const text2 = Color(0xFFA7B0CC);
  static const accent = Color(0xFF7AA2F7);
  static const accent2 = Color(0xFFB48CFF);
  static const aurora = Color(0xFF4FE3B0);
  static const ink = Color(0xFF050816);
  static const warn = Color(0xFFF2C06B);
  static const danger = Color(0xFFFF7A93);
  static const display = 'SpaceGrotesk';
  static const radius = 20.0;
}

/// The red light palette: one hue, told apart by lightness only.
abstract final class Red {
  static const bg = Color(0xFF000000);
  static const surface = Color(0xFF120000);
  static const surface2 = Color(0xFF1E0302);
  static const line = Color(0xFF3A0A08);
  static const text = Color(0xFFFF5A4E);
  static const text2 = Color(0xFFD2433A);
  static const strong = Color(0xFFFF7A70);
  static const ink = Color(0xFF000000);
}

/// The colours that carry meaning beyond the Material scheme.
class Tones extends ThemeExtension<Tones> {
  const Tones({
    required this.good,
    required this.warn,
    required this.danger,
    required this.muted,
    required this.surface,
    required this.line,
    required this.red,
  });

  final Color good;
  final Color warn;
  final Color danger;
  final Color muted;
  final Color surface;
  final Color line;

  /// Whether the red light mode is on.
  final bool red;

  static const day = Tones(
    good: Sky.aurora,
    warn: Sky.warn,
    danger: Sky.danger,
    muted: Sky.text2,
    surface: Sky.surface,
    line: Sky.line,
    red: false,
  );

  static const night = Tones(
    good: Red.strong,
    warn: Red.text,
    danger: Red.strong,
    muted: Red.text2,
    surface: Red.surface,
    line: Red.line,
    red: true,
  );

  @override
  Tones copyWith() => this;

  @override
  Tones lerp(Tones? other, double t) => t < .5 ? this : (other ?? this);
}

extension TonesOf on BuildContext {
  Tones get tones => Theme.of(this).extension<Tones>() ?? Tones.day;
}

ThemeData bortleTheme({bool red = false}) {
  final scheme = red
      ? const ColorScheme.dark(
          primary: Red.text,
          onPrimary: Red.ink,
          primaryContainer: Red.surface2,
          onPrimaryContainer: Red.text,
          secondary: Red.text,
          onSecondary: Red.ink,
          tertiary: Red.strong,
          onTertiary: Red.ink,
          error: Red.strong,
          onError: Red.ink,
          surface: Red.bg,
          onSurface: Red.text,
          onSurfaceVariant: Red.text2,
          surfaceContainerLowest: Red.bg,
          surfaceContainerLow: Red.surface,
          surfaceContainer: Red.surface,
          surfaceContainerHigh: Red.surface2,
          surfaceContainerHighest: Red.surface2,
          outline: Red.line,
          outlineVariant: Red.line,
        )
      : const ColorScheme.dark(
          primary: Sky.accent,
          onPrimary: Sky.ink,
          primaryContainer: Color(0xFF243766),
          onPrimaryContainer: Sky.text,
          secondary: Sky.accent2,
          onSecondary: Sky.ink,
          secondaryContainer: Color(0xFF33295A),
          onSecondaryContainer: Sky.text,
          tertiary: Sky.aurora,
          onTertiary: Sky.ink,
          error: Sky.danger,
          onError: Sky.ink,
          surface: Color(0xFF0B1124),
          onSurface: Sky.text,
          onSurfaceVariant: Sky.text2,
          surfaceContainerLowest: Color(0xFF070B18),
          surfaceContainerLow: Color(0xFF0D1428),
          surfaceContainer: Color(0xFF111A33),
          surfaceContainerHigh: Color(0xFF16203D),
          surfaceContainerHighest: Color(0xFF1C2648),
          outline: Color(0x667AA2F7),
          outlineVariant: Sky.line,
        );
  final tones = red ? Tones.night : Tones.day;
  final textColor = scheme.onSurface;
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = base.textTheme.apply(bodyColor: textColor, displayColor: textColor);
  TextStyle? display(TextStyle? s, FontWeight w) =>
      s?.copyWith(fontFamily: Sky.display, fontWeight: w, letterSpacing: -.2);
  const pill = StadiumBorder();
  const buttonSize = Size(48, 48);
  const buttonText = TextStyle(fontWeight: FontWeight.w700, fontSize: 15);
  final field = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: tones.line),
  );
  final dialogBg = red ? Red.surface : const Color(0xFF0D1428);
  return base.copyWith(
    extensions: [tones],
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: scheme.surface,
    textTheme: text.copyWith(
      displayLarge: display(text.displayLarge, FontWeight.w700),
      displayMedium: display(text.displayMedium, FontWeight.w700),
      displaySmall: display(text.displaySmall, FontWeight.w700),
      headlineLarge: display(text.headlineLarge, FontWeight.w700),
      headlineMedium: display(text.headlineMedium, FontWeight.w700),
      headlineSmall: display(text.headlineSmall, FontWeight.w600),
      titleLarge: display(text.titleLarge, FontWeight.w600),
      titleMedium: display(text.titleMedium, FontWeight.w600),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: SkyPageTransitions(FadeForwardsPageTransitionsBuilder()),
        TargetPlatform.iOS: SkyPageTransitions(CupertinoPageTransitionsBuilder()),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: red ? Red.bg : const Color(0x8C04060F),
      surfaceTintColor: Colors.transparent,
      foregroundColor: textColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: tones.line)),
      titleTextStyle: TextStyle(
        fontFamily: Sky.display,
        fontWeight: FontWeight.w700,
        fontSize: 21,
        letterSpacing: -.4,
        color: textColor,
      ),
    ),
    cardTheme: CardThemeData(
      color: tones.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sky.radius),
        side: BorderSide(color: tones.line),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: tones.muted,
      subtitleTextStyle: TextStyle(color: tones.muted, fontSize: 14),
    ),
    dividerTheme: DividerThemeData(color: tones.line, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: buttonSize,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textColor,
        backgroundColor: red ? Red.surface : const Color(0x337AA2F7),
        side: BorderSide(color: red ? Red.line : const Color(0x737AA2F7)),
        minimumSize: buttonSize,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: pill,
        textStyle: buttonText.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        minimumSize: const Size(44, 44),
        shape: pill,
        textStyle: buttonText.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: red ? Red.surface : const Color(0x99060A18),
      border: field,
      enabledBorder: field,
      focusedBorder: field.copyWith(borderSide: BorderSide(color: scheme.primary, width: 2)),
      errorBorder: field.copyWith(borderSide: BorderSide(color: tones.danger)),
      labelStyle: TextStyle(color: tones.muted),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: red ? Red.bg : const Color(0xF0070A16),
      indicatorColor: red ? Red.surface2 : const Color(0xFF1C2440),
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dialogBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sky.radius),
        side: BorderSide(color: tones.line),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: dialogBg, surfaceTintColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: red ? Red.surface2 : const Color(0xFF1C2648),
      contentTextStyle: TextStyle(color: textColor),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
  );
}

/// Every page gets its own sky, so the pages (with transparent scaffolds) stay opaque
/// during a transition.
class SkyPageTransitions extends PageTransitionsBuilder {
  const SkyPageTransitions(this.inner);

  final PageTransitionsBuilder inner;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => inner.buildTransitions(route, context, animation, secondaryAnimation, SkyBackground(child: child));
}

/// The night sky behind a page; plain black in the red light mode, where every lit
/// pixel costs dark adaptation.
class SkyBackground extends StatelessWidget {
  const SkyBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final page = SafeArea(top: false, left: false, right: false, child: child);
    if (context.tones.red) return ColoredBox(color: Red.bg, child: page);
    return CustomPaint(painter: const _SkyPainter(), isComplex: true, child: page);
  }
}

class _SkyPainter extends CustomPainter {
  const _SkyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF060A1C), Sky.bg, Color(0xFF02030A)],
          stops: [0, .55, 1],
        ).createShader(rect),
    );
    void glow(Offset centre, double rx, double ry, Color color) {
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.scale(1, ry / rx);
      final r = Rect.fromCircle(center: Offset.zero, radius: rx);
      canvas.drawRect(
        Rect.fromLTRB(-rx, -rx, rx, rx),
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)], stops: const [0, .6]).createShader(r),
      );
      canvas.restore();
    }

    final w = size.width, h = size.height;
    glow(Offset(w * .15, -h * .05), w * .8, h * .45, const Color(0x384FE3B0));
    glow(Offset(w * .85, 0), w * .7, h * .5, const Color(0x3DB48CFF));
    glow(Offset(w * .5, h * 1.1), w * 1.2, h * .6, const Color(0x592846AA));

    final random = math.Random(7);
    final star = Paint();
    final count = (w * h / 2500).round().clamp(80, 900);
    for (var i = 0; i < count; i++) {
      final p = Offset(random.nextDouble() * w, random.nextDouble() * h);
      final bright = random.nextDouble();
      star.color = Colors.white.withValues(alpha: .25 + .6 * bright * bright);
      canvas.drawCircle(p, .4 + 1.0 * bright * bright, star);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) => false;
}
