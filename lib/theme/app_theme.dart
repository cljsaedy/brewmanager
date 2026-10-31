import 'package:flutter/material.dart';

// all the colors of the app in one place so every screen looks the same
class AppColors {
  // main brand color, espresso brown
  static const Color espresso = Color(0xFF5B3A29);
  // accent color for highlights, caramel
  static const Color caramel = Color(0xFFC8873A);
  // page background behind the cards, cream
  static const Color cream = Color(0xFFF6F1EB);
  // cards, sidebar and top bar are white
  static const Color card = Color(0xFFFFFFFF);
  // light brown lines between table rows and around cards
  static const Color divider = Color(0xFFE8DFD6);

  // dark text and lighter text for hints/labels
  static const Color textMain = Color(0xFF2B211C);
  static const Color textMuted = Color(0xFF7A6A60);

  // status chip colors, text color + soft background color
  // green = ok, amber = restock recommended, red = error/failed
  static const Color okText = Color(0xFF2E7D4F);
  static const Color okBg = Color(0xFFE3F1E8);
  static const Color warnText = Color(0xFFB26A00);
  static const Color warnBg = Color(0xFFFDF0DC);
  static const Color errorText = Color(0xFFB3261E);
  static const Color errorBg = Color(0xFFFBE4E2);
}

class AppTheme {
  // font name, must match the family name in pubspec.yaml
  // if the font files are missing flutter just uses the default font
  static const String fontFamily = 'PublicSans';

  // corner roundness for cards and buttons
  static const double cardRadius = 16;
  static const double buttonRadius = 10;

  static ThemeData light() {
    // make the material color set from our brown, then swap in our exact colors
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.espresso,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.espresso,
      onPrimary: Colors.white,
      secondary: AppColors.caramel,
      onSecondary: Colors.white,
      surface: AppColors.card,
      onSurface: AppColors.textMain,
      error: AppColors.errorText,
      outlineVariant: AppColors.divider,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.cream,
      dividerColor: AppColors.divider,

      // text sizes, kept a bit small since the tablet screen is only 8.7 inch
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textMain,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textMain,
        ),
        bodyMedium: TextStyle(fontSize: 14, color: AppColors.textMain),
        bodySmall: TextStyle(fontSize: 12, color: AppColors.textMuted),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),

      // white cards with round corners and a thin line instead of a shadow
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: AppColors.divider),
        ),
      ),

      // main filled button, brown with white text
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.espresso,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),

      // outlined button for less important actions like day note
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.espresso,
          side: const BorderSide(color: AppColors.divider),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),

      // text boxes, white with light border, brown border when typing
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: AppColors.espresso, width: 1.5),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
