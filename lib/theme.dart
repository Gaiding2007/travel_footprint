import 'package:flutter/material.dart';

/// 主题与配色（参考站是干净的白色系，点亮色用天蓝）
class AppColors {
  static const Color background = Color(0xFFF2F5F9);
  static const Color surface = Colors.white;
  static const Color primary = Color(0xFF2E6BE6);
  static const Color lit = Color(0xFF90CEFF);
  static const Color textPrimary = Color(0xFF1F2933);
  static const Color textSecondary = Color(0xFF6B7A8C);
  static const Color divider = Color(0xFFE4E9F0);
}

class AppTheme {
  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ).copyWith(surface: AppColors.surface),
      scaffoldBackgroundColor: AppColors.background,
    );
    return base.copyWith(
      splashFactory: InkSparkle.splashFactory,
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: Color(0xFFB6C2D1), width: 1.4),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return Colors.white;
        }),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
    );
  }
}
