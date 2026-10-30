import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_metrics.dart';

/// assembles the one ThemeData the whole app uses
///
/// the point of putting it here rather than styling each screen is that a screen
/// built later can't drift, it inherits the same scale and the same colours
class AppTheme {
  AppTheme._();

  /// five sizes doing all the work
  ///
  /// mapped onto the material names the screens already use, so a screen asking
  /// for titleMedium gets this scale without being rewritten
  ///
  /// everything is a step larger than material's defaults because this is read
  /// standing up at arm's length on a counter, not held in the hand
  static const TextTheme _textTheme = TextTheme(
    // the wordmark on the lock screen, nothing else, so it can be large
    headlineLarge: TextStyle(
      fontSize: 56,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
      letterSpacing: -0.5,
    ),
    // a screen's one important instruction
    headlineMedium: TextStyle(
      fontSize: 27,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
    ),
    // the single most important number on a screen, a total or a stepper value
    headlineSmall: TextStyle(
      fontSize: 23,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
    // section headings
    titleLarge: TextStyle(
      fontSize: 19,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
    ),
    // a row's subject, a menu item name, an ingredient
    titleMedium: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: AppColors.inkBody,
    ),
    // default reading text
    bodyLarge: TextStyle(fontSize: 16, color: AppColors.inkBody),
    bodyMedium: TextStyle(fontSize: 15, color: AppColors.inkBody),
    // meta lines, the quiet detail under a title
    bodySmall: TextStyle(fontSize: 13, color: AppColors.inkMuted),
    // button text, kept large because buttons are pressed without looking closely
    labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  );

  /// written out rather than generated from a seed colour
  ///
  /// a seeded scheme invents tones nobody chose, which is how an app ends up
  /// looking like every other app built from the same default
  static const ColorScheme _colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.ink,
    onPrimary: Colors.white,
    primaryContainer: AppColors.surfaceSunken,
    onPrimaryContainer: AppColors.ink,
    secondary: AppColors.info,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.infoSurface,
    onSecondaryContainer: AppColors.onInfoSurface,
    // tertiary is where the informational panels pull their tint from
    tertiary: AppColors.info,
    onTertiary: Colors.white,
    tertiaryContainer: AppColors.infoSurface,
    onTertiaryContainer: AppColors.onInfoSurface,
    error: AppColors.danger,
    onError: Colors.white,
    errorContainer: Color(0xFFF7DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: AppColors.surface,
    onSurface: AppColors.inkBody,
    surfaceContainerHighest: AppColors.surfaceSunken,
    surfaceContainerHigh: AppColors.surfaceSunken,
    surfaceContainer: AppColors.surfaceRaised,
    onSurfaceVariant: AppColors.inkMuted,
    outline: AppColors.outline,
    outlineVariant: AppColors.hairline,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: AppColors.ink,
    onInverseSurface: AppColors.surface,
    inversePrimary: AppColors.surfaceSunken,
  );

  static ThemeData build() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: _colorScheme,
      textTheme: _textTheme,
      scaffoldBackgroundColor: AppColors.surface,
      disabledColor: AppColors.inkDisabled,
      // the system font, it's what every other android app on the tablet uses
      // so it reads as native and costs nothing to ship
      fontFamily: null,

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        // flat, a shadow under the bar just eats contrast on a small screen
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),

      // flat with a hairline border instead of material's elevation shadows,
      // shadows on a pale surface read as untouched defaults
      cardTheme: CardThemeData(
        color: AppColors.surfaceRaised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
          side: const BorderSide(color: AppColors.hairline),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
        space: 1,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppSizes.actionHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radius),
          ),
          textStyle: _textTheme.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSizes.actionHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          side: const BorderSide(color: AppColors.outline),
          foregroundColor: AppColors.ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radius),
          ),
          textStyle: _textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppSizes.minTarget),
          foregroundColor: AppColors.ink,
          textStyle: _textTheme.labelLarge,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppSizes.minTarget, AppSizes.minTarget),
          foregroundColor: AppColors.ink,
        ),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.inkMuted,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.inkBody,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 13,
          color: AppColors.inkMuted,
        ),
        minVerticalPadding: AppSpacing.md,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radius),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radius),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radius),
          borderSide: const BorderSide(color: AppColors.ink, width: 2),
        ),
        labelStyle: const TextStyle(fontSize: 15, color: AppColors.inkMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceRaised,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        ),
        titleTextStyle: _textTheme.titleLarge,
        contentTextStyle: _textTheme.bodyLarge,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(fontSize: 15, color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radius),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceSunken,
        side: const BorderSide(color: AppColors.hairline),
        labelStyle: const TextStyle(fontSize: 13, color: AppColors.inkBody),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radius),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radius),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.ink,
      ),
    );
  }
}
