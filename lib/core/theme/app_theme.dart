import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Port Shape.kt.
class AppShapes {
  AppShapes._();

  static final BorderRadius card = BorderRadius.circular(18);
  static final BorderRadius panel = BorderRadius.circular(28);
  static final BorderRadius pill = BorderRadius.circular(100);
}

TextStyle _ts(FontWeight w, double size, double lineHeight, double spacing, Color c) {
  return TextStyle(
    fontWeight: w,
    fontSize: size,
    height: lineHeight / size,
    letterSpacing: spacing,
    color: c,
  );
}

/// Port Theme.kt + Type.kt. Zenime (Flutter) hanya punya tema gelap.
ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accentViolet,
    onPrimary: AppColors.textWhite,
    primaryContainer: AppColors.accentVioletDark,
    onPrimaryContainer: AppColors.textWhite,
    secondary: AppColors.accentVioletLight,
    onSecondary: AppColors.textWhite,
    secondaryContainer: AppColors.surfaceElevated,
    onSecondaryContainer: AppColors.textSecondary,
    tertiary: AppColors.accentVioletLight,
    onTertiary: AppColors.textWhite,
    surface: AppColors.surfaceDark,
    onSurface: AppColors.textWhite,
    surfaceContainerHighest: AppColors.surfaceVariantDark,
    onSurfaceVariant: AppColors.textSecondary,
    outline: AppColors.surfaceElevated,
    outlineVariant: AppColors.surfaceVariantDark,
    error: AppColors.errorRed,
    onError: AppColors.textWhite,
  );

  final textTheme = TextTheme(
    headlineLarge: _ts(FontWeight.w700, 28, 34, -0.5, AppColors.textWhite),
    headlineMedium: _ts(FontWeight.w700, 22, 28, -0.2, AppColors.textWhite),
    headlineSmall: _ts(FontWeight.w600, 18, 24, 0, AppColors.textWhite),
    titleLarge: _ts(FontWeight.w700, 17, 23, 0, AppColors.textWhite),
    titleMedium: _ts(FontWeight.w600, 15, 21, 0.1, AppColors.textWhite),
    titleSmall: _ts(FontWeight.w500, 13, 18, 0.1, AppColors.textSecondary),
    bodyLarge: _ts(FontWeight.w400, 14, 20, 0.2, AppColors.textWhite),
    bodyMedium: _ts(FontWeight.w400, 13, 18, 0.2, AppColors.textSecondary),
    bodySmall: _ts(FontWeight.w400, 11, 16, 0.2, AppColors.textMuted),
    labelLarge: _ts(FontWeight.w600, 13, 17, 0.3, AppColors.textWhite),
    labelMedium: _ts(FontWeight.w500, 11, 15, 0.4, AppColors.textSecondary),
    labelSmall: _ts(FontWeight.w500, 10, 14, 0.5, AppColors.textMuted),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.backgroundDark,
    canvasColor: AppColors.backgroundDark,
    textTheme: textTheme,
  );
}
