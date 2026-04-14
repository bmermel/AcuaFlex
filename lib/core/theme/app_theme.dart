import 'package:flutter/material.dart';

import '../../features/delivery/domain/delivery_state.dart';

/// Tema visual de la app AcuaFlex: estilo claro, moderno y prolijo.
///
/// Paleta de marca (referencia):
/// https://paletadecolores.com.ar/paleta/d2d2d2/58afb8/269199/ec225e/020305/
/// - `#d2d2d2` neutro / bordes · `#58afb8` teal claro · `#269199` teal principal
/// - `#ec225e` acento / alerta · `#020305` texto oscuro
class AppTheme {
  AppTheme._();

  /// Icono de marca (bootstrap): mismo asset que launcher/splash.
  static const String logoAssetPath = 'assets/images/app_brand_icon.png';

  /// Logo Acuario: login y pantalla principal (SVG exportado desde vectores).
  static const String acuarioLogoAssetPath = 'assets/images/logo_acuaflex.svg';

  // ——— Paleta AcuaFlex (hex de la referencia) ———
  static const Color paletteNeutral = Color(0xFFD2D2D2);
  static const Color paletteTealLight = Color(0xFF58AFB8);
  static const Color paletteTeal = Color(0xFF269199);
  static const Color paletteAccent = Color(0xFFEC225E);
  static const Color paletteInk = Color(0xFF020305);

  // ——— Colores principales (tema claro) ———
  /// Fondo general de la app.
  static const Color scaffoldBackground = Color(0xFFF0F1F2);

  /// Acciones principales y selección (teal de marca).
  static const Color primaryBlue = paletteTeal;

  /// Estado entregado (mismo eje cromático que la marca).
  static const Color entregadoColor = paletteTeal;
  static const Color entregadoBgLight = Color(0xFFE5F4F5);

  /// Estado pendiente (teal claro).
  static const Color pendienteColor = paletteTealLight;
  static const Color pendienteBgLight = Color(0xFFE8F6F7);

  /// Estado no entregado (acento rosa de la paleta).
  static const Color noEntregadoColor = paletteAccent;
  static const Color noEntregadoBgLight = Color(0xFFFCE8EF);

  /// Gris suave para bordes y divisores.
  static const Color borderLight = paletteNeutral;

  /// Fondo de cards (blanco o casi blanco).
  static const Color cardBackground = Color(0xFFFFFFFF);

  /// Fondo suave para filtro/tarjeta seleccionada (tinte teal).
  static const Color selectedTint = Color(0xFFE0F2F4);

  /// Ícono y color por estado (consistente en toda la app).
  static IconData iconFor(DeliveryState state) {
    switch (state) {
      case DeliveryState.entregado:
        return Icons.check_circle;
      case DeliveryState.noEntregado:
        return Icons.cancel;
      case DeliveryState.pendiente:
        return Icons.schedule;
    }
  }

  static Color colorFor(DeliveryState state) {
    switch (state) {
      case DeliveryState.entregado:
        return entregadoColor;
      case DeliveryState.noEntregado:
        return noEntregadoColor;
      case DeliveryState.pendiente:
        return pendienteColor;
    }
  }

  static Color backgroundColorFor(DeliveryState state) {
    switch (state) {
      case DeliveryState.entregado:
        return entregadoBgLight;
      case DeliveryState.noEntregado:
        return noEntregadoBgLight;
      case DeliveryState.pendiente:
        return pendienteBgLight;
    }
  }

  /// Íconos para tarjetas de filtro/resumen.
  static const IconData iconTotal = Icons.format_list_numbered;
  static const IconData iconPendientes = Icons.schedule;
  static const IconData iconEntregadas = Icons.check_circle;
  static const IconData iconNoEntregadas = Icons.cancel;

  // ——— Panel admin: colores previos (azul suave, verde/naranja/rojo por estado) ———
  static const Color adminPrimaryBlue = Color(0xFF5C9EAD);
  static const Color adminEntregadoColor = Color(0xFF6B9B6B);
  static const Color adminEntregadoBgLight = Color(0xFFE8F5E9);
  static const Color adminPendienteColor = Color(0xFFE59866);
  static const Color adminPendienteBgLight = Color(0xFFFFF3E0);
  static const Color adminNoEntregadoColor = Color(0xFFD46A6A);
  static const Color adminNoEntregadoBgLight = Color(0xFFFFEBEE);
  static const Color adminScaffoldBackground = Color(0xFFF5F5F5);
  static const Color adminBorderLight = Color(0xFFE0E0E0);
  static const Color adminSelectedTint = Color(0xFFE3F2FD);
  static const Color adminOnSurface = Color(0xFF1C1C1C);

  static Color adminColorFor(DeliveryState state) {
    switch (state) {
      case DeliveryState.entregado:
        return adminEntregadoColor;
      case DeliveryState.noEntregado:
        return adminNoEntregadoColor;
      case DeliveryState.pendiente:
        return adminPendienteColor;
    }
  }

  static Color adminBackgroundColorFor(DeliveryState state) {
    switch (state) {
      case DeliveryState.entregado:
        return adminEntregadoBgLight;
      case DeliveryState.noEntregado:
        return adminNoEntregadoBgLight;
      case DeliveryState.pendiente:
        return adminPendienteBgLight;
    }
  }

  /// Tema solo para rutas `/admin/*`: restaura el aspecto previo al de la paleta de marca.
  static ThemeData get adminTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: adminPrimaryBlue,
      brightness: Brightness.light,
    ).copyWith(
      primary: adminPrimaryBlue,
      onPrimary: Colors.white,
      surface: cardBackground,
      onSurface: adminOnSurface,
      surfaceContainerHighest: const Color(0xFFFAFAFA),
      onSurfaceVariant: const Color(0xFF5C5C5C),
      outline: adminBorderLight,
      outlineVariant: adminBorderLight.withValues(alpha: 0.75),
      error: const Color(0xFFB00020),
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: adminScaffoldBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: cardBackground,
        foregroundColor: adminOnSurface,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardTheme(
        color: cardBackground,
        elevation: 1,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: adminBorderLight, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: adminBorderLight),
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: adminPrimaryBlue, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: adminPrimaryBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          minimumSize: const Size(48, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          minimumSize: const Size(48, 48),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(48, 48),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        side: const BorderSide(color: adminBorderLight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      textTheme: _buildTextTheme(),
    );
  }

  /// Tema global de la app (claro, Material moderno).
  static ThemeData get theme {
    final scheme = ColorScheme.fromSeed(
      seedColor: paletteTeal,
      brightness: Brightness.light,
    ).copyWith(
      primary: paletteTeal,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFB8E0E4),
      onPrimaryContainer: const Color(0xFF002D33),
      secondary: paletteTealLight,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFCCECF0),
      onSecondaryContainer: const Color(0xFF002D33),
      tertiary: paletteAccent,
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFFFD9E2),
      onTertiaryContainer: const Color(0xFF400018),
      surface: cardBackground,
      onSurface: paletteInk,
      surfaceContainerHighest: const Color(0xFFF5F5F6),
      onSurfaceVariant: const Color(0xFF5C6266),
      outline: paletteNeutral,
      outlineVariant: paletteNeutral.withValues(alpha: 0.6),
      error: paletteAccent,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: cardBackground,
        foregroundColor: paletteInk,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardTheme(
        color: cardBackground,
        elevation: 1,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: borderLight, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: borderLight),
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: primaryBlue, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          minimumSize: const Size(48, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          minimumSize: const Size(48, 48),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(48, 48),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        side: const BorderSide(color: borderLight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      textTheme: _buildTextTheme(),
    );
  }

  static TextTheme _buildTextTheme() {
    final base = ThemeData.light().textTheme;
    return base.copyWith(
      titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w500),
      bodyLarge: base.bodyLarge?.copyWith(height: 1.4),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.4),
    );
  }
}
