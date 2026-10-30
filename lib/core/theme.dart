import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

import 'settings.dart';

/// Design tokens. Industrial: aluminium greys, hairlines, one signal colour.
@immutable
class Tokens extends ThemeExtension<Tokens> {
  const Tokens({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.radius,
    required this.dark,
    this.zen = false,
  });

  final Color bg;
  final Color surface;
  final Color raised;
  final Color ink;
  final Color muted;
  final Color line;
  final Color accent;
  final Color onAccent;
  final double radius;
  final bool dark;

  /// Zen mode: components drop hairlines, uppercase and monospace.
  final bool zen;

  BorderRadius get br => BorderRadius.circular(radius);

  /// The hairline around cards and buttons; zen has none.
  BoxBorder? get hair => zen ? null : Border.all(color: line);

  static Tokens of(BuildContext context) => Theme.of(context).extension<Tokens>()!;

  @override
  Tokens copyWith() => this;

  @override
  Tokens lerp(Tokens? other, double t) => t < .5 ? this : (other ?? this);
}

TextStyle mono(BuildContext context, {double size = 10.5, Color? color, FontWeight weight = FontWeight.w500, double spacing = 1.2}) {
  final t = Tokens.of(context);
  return monoFont(fontSize: size, color: color ?? t.muted, fontWeight: weight, letterSpacing: spacing);
}

/// The interface's small-print face: JetBrains Mono, or in zen mode the
/// regular UI font a touch larger and without the tracking.
TextStyle monoFont({double? fontSize, Color? color, FontWeight? fontWeight, double? letterSpacing, double? height}) {
  final s = Settings.i;
  if (!s.zen) return GoogleFonts.jetBrainsMono(fontSize: fontSize, color: color, fontWeight: fontWeight, letterSpacing: letterSpacing, height: height);
  return GoogleFonts.getFont(zenFont(s),
      fontSize: fontSize == null ? null : fontSize * 1.18, color: color, fontWeight: fontWeight, letterSpacing: (letterSpacing ?? 0) > .5 ? .1 : letterSpacing, height: height);
}

/// Zen keeps the chosen interface font unless it is the monospace one.
String zenFont(Settings s) => s.uiFont == 'JetBrains Mono' || s.uiFont == 'Space Grotesk' ? 'Inter' : s.uiFont;

ThemeData buildTheme(Brightness b, Settings s) {
  final dark = b == Brightness.dark;
  // Monochrome swaps the signal colour for the ink colour. So does an accent that
  // would disappear on this theme's background: white on light, black on dark.
  final accent = s.signalOn(dark ? const Color(0xFFEDEDED) : const Color(0xFF1A1A1A));
  final onAccent = accent.computeLuminance() > .5 ? const Color(0xFF111111) : Colors.white;
  final zen = s.zen;
  final t = zen
      ? Tokens(
          bg: dark ? const Color(0xFF0F0F10) : const Color(0xFFFAFAF9),
          surface: dark ? const Color(0xFF18181A) : const Color(0xFFFFFFFF),
          raised: dark ? const Color(0xFF232326) : const Color(0xFFF1F1EF),
          ink: dark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B),
          muted: dark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A),
          line: dark ? const Color(0xFF2A2A2D) : const Color(0xFFE9E9E6),
          accent: accent,
          onAccent: onAccent,
          radius: 16,
          dark: dark,
          zen: true,
        )
      : Tokens(
          bg: dark ? const Color(0xFF0D0D0D) : const Color(0xFFE8E6E1),
          surface: dark ? const Color(0xFF161616) : const Color(0xFFF3F2EE),
          raised: dark ? const Color(0xFF1F1F1F) : const Color(0xFFFFFFFF),
          ink: dark ? const Color(0xFFECEAE4) : const Color(0xFF141414),
          muted: dark ? const Color(0xFF8B8983) : const Color(0xFF75736D),
          line: dark ? const Color(0xFF2B2B2B) : const Color(0xFFCAC7BF),
          accent: accent,
          onAccent: onAccent,
          radius: s.radius,
          dark: dark,
        );

  final base = ThemeData(brightness: b, useMaterial3: true);
  final text = GoogleFonts.getTextTheme(zen ? zenFont(s) : s.uiFont, base.textTheme).apply(bodyColor: t.ink, displayColor: t.ink);
  final field = zen ? OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none) : null;

  return base.copyWith(
    extensions: [t],
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: b).copyWith(
      primary: accent,
      onPrimary: onAccent,
      surface: t.surface,
      onSurface: t.ink,
      outline: t.line,
    ),
    textTheme: text,
    splashFactory: zen ? InkSparkle.splashFactory : NoSplash.splashFactory,
    highlightColor: t.ink.withValues(alpha: .04),
    dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(zen ? 28 : t.radius + 6))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: zen ? BorderRadius.circular(24) : t.br, side: zen ? BorderSide.none : BorderSide(color: t.line)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.ink,
      contentTextStyle: monoFont(color: t.bg, fontSize: 12),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: t.br),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: t.raised,
      hintStyle: TextStyle(color: t.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: field ?? OutlineInputBorder(borderRadius: t.br, borderSide: BorderSide(color: t.line)),
      enabledBorder: field ?? OutlineInputBorder(borderRadius: t.br, borderSide: BorderSide(color: t.line)),
      focusedBorder: zen ? OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accent, width: 1.5)) : OutlineInputBorder(borderRadius: t.br, borderSide: BorderSide(color: t.ink)),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: zen ? 4 : 2,
      activeTrackColor: zen ? accent : t.ink,
      inactiveTrackColor: zen ? t.raised : t.line,
      thumbColor: accent,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: zen ? const RoundSliderThumbShape(enabledThumbRadius: 8, elevation: 1) : const _SquareThumb(),
      tickMarkShape: SliderTickMarkShape.noTickMark,
      showValueIndicator: ShowValueIndicator.never,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: zen ? BorderRadius.circular(14) : t.br, side: zen ? BorderSide.none : BorderSide(color: t.line)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: accent.withValues(alpha: .35),
      selectionHandleColor: accent,
      cursorColor: accent,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent, linearTrackColor: zen ? t.raised : t.line, borderRadius: zen ? BorderRadius.circular(3) : BorderRadius.zero),
  );
}

class _SquareThumb extends SliderComponentShape {
  const _SquareThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(14, 22);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final c = context.canvas;
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: 12, height: 22), const Radius.circular(2));
    c.drawRRect(r, Paint()..color = sliderTheme.thumbColor!);
    c.drawLine(center.translate(0, -6), center.translate(0, 6),
        Paint()
          ..color = Colors.black.withValues(alpha: .35)
          ..strokeWidth = 1.2);
  }
}
