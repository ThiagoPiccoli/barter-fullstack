import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF1B5E20);
  static const Color primaryLight = Color(0xFF2E7D32);
  static const Color primaryMedium = Color(0xFF388E3C);
  static const Color primaryAccent = Color(0xFF4CAF50);
  static const Color primarySurface = Color(0xFFE8F5E9);
  static const Color background = Color(0xFFF5F5F5);
  static const Color white = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF212121);
  static const Color textMedium = Color(0xFF616161);
  static const Color textLight = Color(0xFF9E9E9E);
  static const Color approved = Color(0xFF2E7D32);
  static const Color pending = Color(0xFFF57F17);
  static const Color denied = Color(0xFFC62828);
  static const Color approvedBg = Color(0xFFE8F5E9);
  static const Color pendingBg = Color(0xFFFFF8E1);
  static const Color deniedBg = Color(0xFFFFEBEE);
  static const Color divider = Color(0xFFBDBDBD);
  static const Color cardShadow = Color(0x1A000000);

  // Permuta: insumo retirado (define o custo) x grão de pagamento (cobre o custo)
  static const Color grain = Color(0xFFE65100); // âmbar/laranja terra
  static const Color grainBg = Color(0xFFFFF3E0);
  static const Color input = Color(0xFF00695C); // verde-azulado
  static const Color inputBg = Color(0xFFE0F2F1);
  static const Color balance = Color(0xFF1B5E20);

  /// Gradiente verde padrão usado em cabeçalhos e destaques (saudação, resumo).
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryMedium],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.primaryAccent,
          surface: AppColors.white,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: AppColors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: AppColors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: AppColors.white,
          unselectedLabelColor: Color(0xAAFFFFFF),
          indicatorColor: AppColors.white,
        ),
        fontFamily: 'Roboto',
      );
}
