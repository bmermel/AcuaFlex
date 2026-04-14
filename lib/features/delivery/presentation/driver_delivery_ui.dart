import 'package:flutter/material.dart';

/// Tokens visuales para la pantalla de detalle de entrega (conductor).
/// Estilo: limpio, alto contraste, esquinas suaves, inspiración tipo Stripe/Linear.
abstract class DriverDeliveryUi {
  DriverDeliveryUi._();

  static const Color background = Color(0xFFF9FAFB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color borderSubtle = Color(0xFFE5E7EB);

  /// CTA principal: entregado.
  static const Color primarySuccess = Color(0xFF22C55E);
  static const Color onPrimarySuccess = Color(0xFFFFFFFF);

  /// Acción destructiva (contorno).
  static const Color danger = Color(0xFFEF4444);

  /// Secundarias: mapa / acciones fuertes.
  static const Color secondaryBlue = Color(0xFF3B82F6);
  static const Color secondaryDark = Color(0xFF1F2937);

  /// Utilidades neutras (Maps / llamar / copiar agrupadas).
  static const Color neutralButtonBg = Color(0xFFF3F4F6);
  static const Color neutralButtonFg = Color(0xFF111827);

  /// Estado pendiente.
  static const Color pendingBg = Color(0xFFFEF3C7);
  static const Color pendingFg = Color(0xFF92400E);

  /// Entregado / no entregado (chips compactos).
  static const Color successMutedBg = Color(0xFFDCFCE7);
  static const Color successMutedFg = Color(0xFF166534);
  static const Color dangerMutedBg = Color(0xFFFEE2E2);
  static const Color dangerMutedFg = Color(0xFF991B1B);

  static const double radiusLg = 16;
  static const double radiusMd = 12;
  static const double radiusSm = 10;

  /// Tema local: fondo claro, cards planas con borde, app bar blanca.
  static ThemeData overlayTheme(ThemeData base) {
    final cs = base.colorScheme;
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: cs.copyWith(
        primary: secondaryBlue,
        onPrimary: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        outline: borderSubtle,
        onSurfaceVariant: textSecondary,
        surfaceContainerHighest: neutralButtonBg,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: -0.2,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      cardTheme: CardTheme(
        color: surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: borderSubtle),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(color: borderSubtle),
    );
  }
}
