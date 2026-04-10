import 'package:flutter/material.dart';

import '../../features/delivery/domain/delivery_state.dart';

/// Tema visual de la app AcuaFlex: estilo claro, moderno y prolijo.
class AppTheme {
  AppTheme._();

  static const String logoAssetPath = 'assets/images/logo_acuaflex.png';

  // ——— Colores principales (tema claro) ———
  /// Fondo general de la app.
  static const Color scaffoldBackground = Color(0xFFF5F5F5);

  /// Azul suave: acciones principales y selección.
  static const Color primaryBlue = Color(0xFF5C9EAD);

  /// Verde suave: estado entregado.
  static const Color entregadoColor = Color(0xFF6B9B6B);
  static const Color entregadoBgLight = Color(0xFFE8F5E9);

  /// Naranja suave: estado pendiente.
  static const Color pendienteColor = Color(0xFFE59866);
  static const Color pendienteBgLight = Color(0xFFFFF3E0);

  /// Rojo suave: estado no entregado.
  static const Color noEntregadoColor = Color(0xFFD46A6A);
  static const Color noEntregadoBgLight = Color(0xFFFFEBEE);

  /// Gris suave para bordes y divisores.
  static const Color borderLight = Color(0xFFE0E0E0);

  /// Fondo de cards (blanco o casi blanco).
  static const Color cardBackground = Color(0xFFFFFFFF);

  /// Azul muy claro para filtro/tarjeta seleccionada.
  static const Color selectedTint = Color(0xFFE3F2FD);

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

  /// Tema global de la app (claro, Material moderno).
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: primaryBlue,
        onPrimary: const Color(0xFFFFFFFF),
        surface: cardBackground,
        onSurface: const Color(0xFF1C1C1C),
        surfaceContainerHighest: const Color(0xFFFAFAFA),
        onSurfaceVariant: const Color(0xFF5C5C5C),
        outline: borderLight,
        error: const Color(0xFFB00020),
        onError: const Color(0xFFFFFFFF),
      ),
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: cardBackground,
        foregroundColor: const Color(0xFF1C1C1C),
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
        fillColor: const Color(0xFFFAFAFA),
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFFAFAFA),
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
