import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  // Inter is the Home mockup system face (clean neo-grotesque).
  // Bundled offline — never fetched at runtime.
  static const _headingFont = 'Inter';
  static const _bodyFont = 'Inter';

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        // fromSeed alone desaturates the brand into slate blue / grey /
        // mauve; pin the logo's three stops so stock widgets stay on-brand.
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.brandViolet,
        onSecondary: Colors.white,
        tertiary: AppColors.accentCyan,
        onTertiary: Colors.white,
        surface: AppColors.light.surface,
        onSurface: AppColors.light.textPrimary,
        onSurfaceVariant: AppColors.light.textSecondary,
        outline: AppColors.light.border,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      hintColor: AppColors.light.textHint,
      dividerColor: AppColors.light.border,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
    );

    final textTheme = base.textTheme.apply(
      fontFamily: _bodyFont,
      bodyColor: AppColors.light.textPrimary,
      displayColor: AppColors.light.textPrimary,
    );

    return base.copyWith(
      textTheme: textTheme.copyWith(
        displayLarge: TextStyle(
          fontFamily: _headingFont,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: AppColors.light.textPrimary,
          height: 1.15,
          letterSpacing: -0.5,
        ),
        headlineLarge: TextStyle(
          fontFamily: _headingFont,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.light.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontFamily: _headingFont,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.light.textPrimary,
        ),
        titleLarge: TextStyle(
          fontFamily: _headingFont,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.light.textPrimary,
        ),
        titleMedium: TextStyle(
          fontFamily: _headingFont,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.light.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 16,
          color: AppColors.light.textSecondary,
          height: 1.6,
        ),
        bodyMedium: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 14,
          color: AppColors.light.textSecondary,
          height: 1.5,
        ),
        labelLarge: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.light.textPrimary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _headingFont,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.light.textPrimary,
        ),
        iconTheme: IconThemeData(color: AppColors.light.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.light.surface,
        elevation: 0,
        shadowColor: AppColors.glassShadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.light.border),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: TextStyle(
            fontFamily: _bodyFont,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.light.textPrimary,
          side: BorderSide(color: AppColors.light.border),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: TextStyle(
            fontFamily: _bodyFont,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.light.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.light.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.light.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.accent, width: 2),
        ),
        hintStyle: TextStyle(
          fontFamily: _bodyFont,
          color: AppColors.light.textHint,
          fontSize: 15,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.light.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: AppColors.accent.withValues(alpha: 0.16),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: AppColors.accent, size: 24);
          }
          return IconThemeData(color: AppColors.light.textHint, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontFamily: _bodyFont,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            );
          }
          return TextStyle(
            fontFamily: _bodyFont,
            fontSize: 11,
            color: AppColors.light.textHint,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.light.surface,
        selectedIconTheme: const IconThemeData(color: AppColors.accent),
        unselectedIconTheme: IconThemeData(color: AppColors.light.textHint),
        indicatorColor: AppColors.accent.withValues(alpha: 0.16),
        labelType: NavigationRailLabelType.selected,
        selectedLabelTextStyle: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.accent,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 12,
          color: AppColors.light.textHint,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.light.border,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData get dark {
    const dt = AppColors.darkTheme;

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        // Lighter tints of the same logo stops so they read on navy.
        primary: AppColors.primaryLight,
        onPrimary: AppColors.navy,
        secondary: const Color(0xFF9D7BFF),
        onSecondary: AppColors.navy,
        tertiary: const Color(0xFF38BDF8),
        onTertiary: AppColors.navy,
        surface: dt.surface,
        onSurface: dt.textPrimary,
        onSurfaceVariant: dt.textSecondary,
        outline: dt.border,
      ),
      scaffoldBackgroundColor: dt.bgTop,
      hintColor: dt.textHint,
      dividerColor: dt.border,
    );

    final textTheme = base.textTheme.apply(
      fontFamily: _bodyFont,
      bodyColor: dt.textPrimary,
      displayColor: dt.textPrimary,
    );

    return base.copyWith(
      textTheme: textTheme.copyWith(
        displayLarge: TextStyle(
          fontFamily: _headingFont,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: dt.textPrimary,
          height: 1.15,
          letterSpacing: -0.5,
        ),
        headlineLarge: TextStyle(
          fontFamily: _headingFont,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: dt.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontFamily: _headingFont,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: dt.textPrimary,
        ),
        titleLarge: TextStyle(
          fontFamily: _headingFont,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: dt.textPrimary,
        ),
        titleMedium: TextStyle(
          fontFamily: _headingFont,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: dt.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 16,
          color: dt.textSecondary,
          height: 1.6,
        ),
        bodyMedium: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 14,
          color: dt.textSecondary,
          height: 1.5,
        ),
        labelLarge: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: dt.textPrimary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _headingFont,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: dt.textPrimary,
        ),
        iconTheme: IconThemeData(color: dt.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: dt.surface,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: dt.border),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
            fontFamily: _bodyFont,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: dt.textPrimary,
          side: BorderSide(color: dt.border),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
            fontFamily: _bodyFont,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dt.iconWell.withValues(alpha: 0.88),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: dt.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: dt.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        hintStyle: TextStyle(fontFamily: _bodyFont, color: dt.textHint, fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dt.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: AppColors.accent.withValues(alpha: 0.22),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.accent, size: 24);
          }
          return IconThemeData(color: dt.textHint, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontFamily: _bodyFont,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            );
          }
          return TextStyle(fontFamily: _bodyFont, fontSize: 11, color: dt.textHint);
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: dt.surface,
        selectedIconTheme: const IconThemeData(color: AppColors.accent),
        unselectedIconTheme: IconThemeData(color: dt.textHint),
        indicatorColor: AppColors.accent.withValues(alpha: 0.22),
        labelType: NavigationRailLabelType.selected,
        selectedLabelTextStyle: const TextStyle(
          fontFamily: _bodyFont,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.accent,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 12,
          color: dt.textHint,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: dt.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
