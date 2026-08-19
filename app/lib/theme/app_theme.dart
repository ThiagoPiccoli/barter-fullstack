import 'package:flutter/material.dart';

import '../branding/active_brand.dart';

/// Fachada de cores das telas.
///
/// Nada aqui tem valor próprio: cada membro apenas encaminha para a paleta da
/// marca ativa (`lib/branding/active_brand.dart`). É isso que faz um único
/// arquivo de marca reskinnar o app inteiro.
///
/// Se você precisar de uma cor que não está aqui, adicione o campo em
/// [BrandPalette] e exponha-o nesta fachada — não escreva `Color(0x...)` numa
/// tela, senão o próximo cliente herda a cor deste.
class AppColors {
  AppColors._();

  // --- Institucional -----------------------------------------------------
  static Color get primary => brand.palette.primary;
  static Color get primaryLight => brand.palette.primaryLight;
  static Color get primaryMedium => brand.palette.primaryMedium;
  static Color get primaryAccent => brand.palette.primaryAccent;
  static Color get primarySurface => brand.palette.primarySurface;
  static Color get accentOnLight => brand.palette.accentOnLight;

  // --- Superfícies e conteúdo -------------------------------------------
  static Color get background => brand.palette.background;
  static Color get surface => brand.palette.surface;
  static Color get textDark => brand.palette.textDark;
  static Color get textMedium => brand.palette.textMedium;
  static Color get textLight => brand.palette.textLight;

  // --- Conteúdo sobre a cor institucional --------------------------------
  // Cabeçalhos, app bar e tela de login. Usar estes tons em vez de branco
  // literal é o que mantém uma marca de fundo claro legível.
  static Color get onPrimary => brand.palette.onPrimary;
  static Color get onPrimaryMuted => brand.palette.onPrimaryMuted;
  static Color get onPrimarySubtle => brand.palette.onPrimarySubtle;
  static Color get onPrimaryFaint => brand.palette.onPrimaryFaint;
  static Color get onPrimaryOverlay => brand.palette.onPrimaryOverlay;

  // --- Estados da permuta -------------------------------------------------
  /// Esperando o parecer do gerente da unidade — a primeira parada.
  static Color get atManager => brand.palette.atManager;
  static Color get atManagerBg => brand.palette.atManagerBg;
  static Color get approved => brand.palette.approved;
  static Color get pending => brand.palette.pending;
  static Color get denied => brand.palette.denied;
  static Color get approvedBg => brand.palette.approvedBg;
  static Color get pendingBg => brand.palette.pendingBg;
  static Color get deniedBg => brand.palette.deniedBg;

  /// Faturada — o fim da linha.
  static Color get invoiced => brand.palette.invoiced;
  static Color get invoicedBg => brand.palette.invoicedBg;

  // --- Traços e estados neutros ------------------------------------------
  static Color get divider => brand.palette.divider;
  static Color get borderSubtle => brand.palette.borderSubtle;
  static Color get cardShadow => brand.palette.cardShadow;
  static Color get disabledBg => brand.palette.disabledBg;
  static Color get disabledFg => brand.palette.disabledFg;

  // --- Os dois lados do negócio -------------------------------------------
  // Insumo retirado define o custo; grão de pagamento cobre esse custo.
  static Color get grain => brand.palette.grain;
  static Color get grainBg => brand.palette.grainBg;
  static Color get input => brand.palette.input;
  static Color get inputBg => brand.palette.inputBg;
  static Color get balance => brand.palette.balance;

  /// Gradiente institucional dos cabeçalhos e blocos de resumo.
  static LinearGradient get primaryGradient => brand.palette.primaryGradient;

  /// Cor da série [index] nos gráficos, repetindo quando a lista acaba.
  static Color series(int index) => brand.palette.series(index);
}

/// Raios de canto da marca ativa. Mesma ideia da fachada de cores.
class AppShape {
  AppShape._();

  static BorderRadius get card => brand.shape.cardRadius;
  static BorderRadius get button => brand.shape.buttonRadius;
  static BorderRadius get field => brand.shape.fieldRadius;
  static BorderRadius get chip => brand.shape.chipRadius;
  static BorderRadius get logoTile => brand.shape.logoTileRadius;
}

class AppTheme {
  AppTheme._();

  static ThemeData get theme {
    final p = brand.palette;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: p.primary,
        primary: p.primary,
        onPrimary: p.onPrimary,
        secondary: p.primaryAccent,
        surface: p.surface,
        error: p.denied,
      ),
      scaffoldBackgroundColor: p.background,
      dividerColor: p.divider,
      appBarTheme: AppBarTheme(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: p.onPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: p.cardShadow,
        shape: RoundedRectangleBorder(borderRadius: brand.shape.cardRadius),
        color: p.surface,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          disabledBackgroundColor: p.disabledBg,
          disabledForegroundColor: p.disabledFg,
          shape: RoundedRectangleBorder(borderRadius: brand.shape.buttonRadius),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.primary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.primary,
          side: BorderSide(color: p.divider),
          shape: RoundedRectangleBorder(borderRadius: brand.shape.buttonRadius),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        border: OutlineInputBorder(
          borderRadius: brand.shape.fieldRadius,
          borderSide: BorderSide(color: p.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: brand.shape.fieldRadius,
          borderSide: BorderSide(color: p.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: brand.shape.fieldRadius,
          borderSide: BorderSide(color: p.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: brand.shape.fieldRadius,
          borderSide: BorderSide(color: p.denied),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.onPrimary,
        unselectedLabelColor: p.onPrimarySubtle,
        indicatorColor: p.onPrimary,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
        selectedItemColor: p.primary,
        unselectedItemColor: p.textLight,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: brand.shape.buttonRadius),
      ),
      fontFamily: brand.fontFamily,
    );
  }
}
