import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Spacing, radii and sizes from the Milestone 1 design (section 7.2):
/// 20 px screen margins, 8 px spacing grid, 12–16 px rounded cards and inputs,
/// pill-shaped chips, touch targets of at least 44 × 44 px and 52 px main buttons.
abstract final class Insets {
  static const double screen = 20;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double buttonHeight = 52;
  static const double fieldHeight = 48;
  static const double minTouch = 44;
  static const double maxContentWidth = 560; // keeps tablet / landscape layouts readable
}

abstract final class Radii {
  static const card = BorderRadius.all(Radius.circular(16));
  static const field = BorderRadius.all(Radius.circular(12));
  static const button = BorderRadius.all(Radius.circular(14));
  static const pill = BorderRadius.all(Radius.circular(999));
}

/// Text styles used across the app (Plus Jakarta Sans).
abstract final class AppText {
  /// Set to false in widget tests, which cannot download fonts.
  static bool useGoogleFonts = true;

  static TextStyle get _base =>
      useGoogleFonts ? GoogleFonts.plusJakartaSans(color: AppColors.darkCocoa) : const TextStyle(color: AppColors.darkCocoa);

  static TextStyle get display => _base.copyWith(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5);
  static TextStyle get screenTitle => _base.copyWith(fontSize: 19, fontWeight: FontWeight.w700);
  static TextStyle get headline => _base.copyWith(fontSize: 22, fontWeight: FontWeight.w800, height: 1.25);
  static TextStyle get section => _base.copyWith(fontSize: 16, fontWeight: FontWeight.w700);
  static TextStyle get body => _base.copyWith(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5);
  static TextStyle get bodyStrong => _base.copyWith(fontSize: 14, fontWeight: FontWeight.w700);
  static TextStyle get label => _base.copyWith(fontSize: 13, fontWeight: FontWeight.w600);
  static TextStyle get caption => _base.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.grayBrown);
  static TextStyle get small => _base.copyWith(fontSize: 11, fontWeight: FontWeight.w600);
  static TextStyle get price => _base.copyWith(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.deepOlive);
  static TextStyle get priceLarge => _base.copyWith(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.deepOlive);
  static TextStyle get button => _base.copyWith(fontSize: 16, fontWeight: FontWeight.w700);
}

ThemeData buildAppTheme() {
  final textTheme = (AppText.useGoogleFonts ? GoogleFonts.plusJakartaSansTextTheme() : ThemeData.light().textTheme).apply(
    bodyColor: AppColors.darkCocoa,
    displayColor: AppColors.darkCocoa,
  );
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.moss,
    onPrimary: AppColors.white,
    secondary: AppColors.clay,
    onSecondary: AppColors.white,
    tertiary: AppColors.softHoney,
    onTertiary: AppColors.darkCocoa,
    error: AppColors.brick,
    onError: AppColors.white,
    surface: AppColors.white,
    onSurface: AppColors.darkCocoa,
    surfaceContainerHighest: AppColors.lightSand,
    outline: AppColors.linen,
    outlineVariant: AppColors.linen,
  );

  OutlineInputBorder border(Color c, [double w = 1.5]) =>
      OutlineInputBorder(borderRadius: Radii.field, borderSide: BorderSide(color: c, width: w));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.warmCream,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.warmCream,
      foregroundColor: AppColors.darkCocoa,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: AppText.screenTitle,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.linen, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: AppText.body.copyWith(color: AppColors.grayBrown),
      prefixIconColor: AppColors.grayBrown,
      suffixIconColor: AppColors.grayBrown,
      border: border(AppColors.linen),
      enabledBorder: border(AppColors.linen),
      focusedBorder: border(AppColors.moss, 2),
      errorBorder: border(AppColors.brick),
      focusedErrorBorder: border(AppColors.brick, 2),
      errorStyle: AppText.caption.copyWith(color: AppColors.brick),
      helperStyle: AppText.caption,
      helperMaxLines: 2,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.moss,
        foregroundColor: AppColors.white,
        minimumSize: const Size.fromHeight(Insets.buttonHeight),
        shape: const RoundedRectangleBorder(borderRadius: Radii.button),
        textStyle: AppText.button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.moss,
        minimumSize: const Size.fromHeight(Insets.buttonHeight),
        side: const BorderSide(color: AppColors.moss, width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: Radii.button),
        textStyle: AppText.button,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.moss, textStyle: AppText.label.copyWith(fontWeight: FontWeight.w700)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.moss : AppColors.white),
      side: const BorderSide(color: AppColors.linen, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(AppColors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.moss : AppColors.linen),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.moss,
      inactiveTrackColor: AppColors.linen,
      thumbColor: AppColors.moss,
      overlayColor: Color(0x225F6F3E),
      valueIndicatorColor: AppColors.deepOlive,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.darkCocoa,
      contentTextStyle: AppText.body.copyWith(color: AppColors.white),
      shape: const RoundedRectangleBorder(borderRadius: Radii.field),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.warmCream,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    datePickerTheme: const DatePickerThemeData(backgroundColor: AppColors.warmCream),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 600)),
  );
}
