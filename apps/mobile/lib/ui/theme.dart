import 'package:flutter/material.dart';

/// WattByte visual identity: a bolt (energy) and a byte (data).
class WbColors {
  const WbColors._();

  /// Energy accent.
  static const bolt = Color(0xFFFFC53D);

  /// Data accent.
  static const byte = Color(0xFF38BDF8);
  static const mobile = Color(0xFFA78BFA);
  static const wifi = Color(0xFF34D399);
  static const cost = Color(0xFFFB7185);

  static const lightBg = Color(0xFFF4F5F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightText = Color(0xFF0F1115);

  /// Muted text. 6.1:1 on the white card and 5.6:1 on the page background (the
  /// earlier 0xFF6B7280 was 4.4:1 on the page background, below WCAG AA 4.5:1).
  static const lightMuted = Color(0xFF5B6270);

  static const darkBg = Color(0xFF0A0B0F);
  static const darkSurface = Color(0xFF15171E);
  static const darkText = Color(0xFFF3F4F6);
  static const darkMuted = Color(0xFF9CA3AF);

  /// Borders of controls (the segmented selectors): 4.7:1 on the page
  /// background in light mode, 5.7:1 in dark mode, so the control is found
  /// without relying on its label (WCAG 1.4.11). Material's own default was
  /// 2.2:1 in dark mode.
  static const lightOutline = Color(0xFF676E7C);
  static const darkOutline = Color(0xFF838A98);

  /// Error text: AA (4.5:1) on the card, the page background and the accent
  /// washes in both themes (the one red used before was 3.8:1 on white).
  static const lightError = Color(0xFFB91C1C);
  static const darkError = Color(0xFFF87171);

  /// Accent used as the COLOUR OF TEXT (links such as "Enter manually"): the
  /// brand sky blue is 2.1:1 on white, this deeper blue is 5.9:1; in dark mode
  /// the brand blue itself is 8.4:1.
  static const lightAccentText = Color(0xFF0369A1);

  static const boltGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFD86B), Color(0xFFFFB020)],
  );
  static const byteGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF67D2FF), Color(0xFF2A9DF4)],
  );
}

Color mutedOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? WbColors.darkMuted
        : WbColors.lightMuted;

/// Colour for accent-coloured TEXT (see [WbColors.lightAccentText]).
Color accentTextOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? WbColors.byte
        : WbColors.lightAccentText;

/// Colours that identify a data series (chart bars, legend dots).
///
/// The brand pastels are fine on the dark surface but only 1.6 to 2.7:1 on the
/// white card, where a bar or a legend dot should reach 3:1 (WCAG 1.4.11
/// non-text contrast). Light mode therefore uses the same hues one step
/// deeper; dark mode keeps the brand colours.
class WbSeries {
  const WbSeries._({
    required this.mobile,
    required this.wifi,
    required this.energy,
    required this.data,
    required this.cost,
  });

  final Color mobile;
  final Color wifi;
  final Color energy;
  final Color data;
  final Color cost;

  static const _light = WbSeries._(
    mobile: Color(0xFF8B5CF6),
    wifi: Color(0xFF059669),
    energy: Color(0xFFC2610C),
    data: Color(0xFF0284C7),
    cost: Color(0xFFE11D48),
  );
  static const _dark = WbSeries._(
    mobile: WbColors.mobile,
    wifi: WbColors.wifi,
    energy: WbColors.bolt,
    data: WbColors.byte,
    cost: WbColors.cost,
  );

  static WbSeries of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;
}

const kRadius = 24.0;

ThemeData wbTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: WbColors.bolt,
    onPrimary: Colors.black,
    secondary: WbColors.byte,
    onSecondary: Colors.black,
    outline: dark ? WbColors.darkOutline : WbColors.lightOutline,
    error: dark ? WbColors.darkError : WbColors.lightError,
    onError: dark ? Colors.black : Colors.white,
    surface: dark ? WbColors.darkSurface : WbColors.lightSurface,
    onSurface: dark ? WbColors.darkText : WbColors.lightText,
  );
  final base = ThemeData(
      useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final text = base.textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  return base.copyWith(
    scaffoldBackgroundColor: dark ? WbColors.darkBg : WbColors.lightBg,
    textTheme: text.copyWith(
      displayLarge: text.displayLarge?.copyWith(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.5,
        height: 1.05,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      displayMedium: text.displayMedium?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
        height: 1.1,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineSmall: text.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      titleLarge: text.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelMedium: text.labelMedium?.copyWith(
        color: dark ? WbColors.darkMuted : WbColors.lightMuted,
        letterSpacing: 0.2,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? WbColors.darkSurface : WbColors.lightSurface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: WbColors.bolt.withValues(alpha: dark ? 0.25 : 0.35),
      height: 68,
      // Labels keep Flutter's own cap (NavigationBar clamps its label text at
      // 1.3x so the bar keeps its height); the full-size text is in the tooltip
      // (long press) and in the semantics label. See ShellScreen.
      labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: states.contains(WidgetState.selected)
                    ? scheme.onSurface
                    : (dark ? WbColors.darkMuted : WbColors.lightMuted),
              )),
      iconTheme: WidgetStatePropertyAll(IconThemeData(color: scheme.onSurface)),
    ),
    // Bolder labels: easier to read at 14 px, and the same weight as the
    // other controls (the default medium weight looked faint on the dark card).
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(
            text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      ),
    ),
    dividerTheme: DividerThemeData(
        color: scheme.onSurface.withValues(alpha: 0.06), space: 1),
    chipTheme: base.chipTheme.copyWith(
      shape: const StadiumBorder(),
      // A chip is found by its outline (>= 3:1, WCAG 1.4.11) and the selected one is told apart from the others by more
      // than a faint tint (1.4.1): a 2 px outline instead of 1 px. No check mark: at the largest text sizes its width
      // pushes the labels of the Settings chips ("Dziesiętne") past the width of the screen.
      side: WidgetStateBorderSide.resolveWith((states) => BorderSide(
            color: dark ? WbColors.darkOutline : WbColors.lightOutline,
            width: states.contains(WidgetState.selected) ? 2 : 1,
          )),
      backgroundColor: scheme.onSurface.withValues(alpha: 0.06),
      selectedColor: WbColors.bolt.withValues(alpha: dark ? 0.3 : 0.4),
      labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      showCheckmark: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: WbColors.bolt,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    // The default outlined foreground is the yellow primary: unreadable on white cards.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        // 50 % keeps the outline >= 3:1 on every card/screen/accent surface in both brightnesses (WCAG 1.4.11).
        side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.5)),
        // 24 = half the minimum height: a pill for one line of text, a rounded
        // rectangle once the label wraps (a stadium cuts into two lines).
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        minimumSize: const Size(48, 48),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
    ),
    // On: a track that stands out from the card (3:1, 1.4.11) and a thumb that stands out from the track, with a check mark
    // so the state is not told by colour alone (1.4.1). Off: an outlined, almost clear track and a thumb in the outline
    // colour. Before, the thumb was white on both states and the tracks were 1.4-1.6:1 against the card.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) {
        final on = s.contains(WidgetState.selected);
        if (on) return dark ? WbColors.darkBg : Colors.white;
        return dark ? WbColors.darkOutline : WbColors.lightOutline;
      }),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? (dark ? WbColors.bolt : WbColors.lightAccentText)
              : scheme.onSurface.withValues(alpha: 0.05)),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? Colors.transparent
              : (dark ? WbColors.darkOutline : WbColors.lightOutline)),
      thumbIcon: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? Icon(Icons.check_rounded,
                  size: 16,
                  color: dark ? WbColors.bolt : WbColors.lightAccentText)
              : null),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.onSurface.withValues(alpha: 0.05),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
    ),
  );
}
