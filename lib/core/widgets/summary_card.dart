import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tarjeta de resumen reutilizable (Total / Pendientes / Entregadas).
/// Layout en **una sola línea** (icono + valor + título) para evitar overflow en grid y fila.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.color,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  /// Tipografía algo más chica (lista conductor / admin compacto).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    final pad = compact
        ? const EdgeInsets.symmetric(vertical: 8, horizontal: 8)
        : const EdgeInsets.symmetric(vertical: 10, horizontal: 10);
    final iconSize = compact ? 20.0 : 22.0;
    final valueStyle = compact
        ? theme.textTheme.titleLarge?.copyWith(
            color: accent,
            fontWeight: FontWeight.bold,
          )
        : theme.textTheme.headlineSmall?.copyWith(
            color: accent,
            fontWeight: FontWeight.bold,
          );
    final titleStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.1,
    );

    return Card(
      elevation: selected ? 2 : 1,
      margin: compact ? EdgeInsets.zero : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        side: BorderSide(
          color: selected ? accent : AppTheme.borderLight,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        child: Container(
          padding: pad,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 10 : 12),
            color: selected ? AppTheme.selectedTint : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: iconSize, color: accent),
              SizedBox(width: compact ? 6 : 8),
              Text(value, style: valueStyle),
              SizedBox(width: compact ? 4 : 6),
              Expanded(
                child: Text(
                  title,
                  style: titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cuadrícula 2×2 en pantallas angostas o una fila de 4 columnas si [constraints] ≥ [breakpoint].
///
/// En [compact], tipografía algo menor en [SummaryCard] y celdas un poco más bajas.
class SummaryCardsGrid extends StatelessWidget {
  const SummaryCardsGrid({
    super.key,
    required this.children,
    this.breakpoint = 720,
    this.compact = false,
  });

  final List<Widget> children;
  final double breakpoint;

  /// Si es true, [SummaryCard] con estilo más chico (p. ej. vista del conductor).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (w >= breakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(width: compact ? 8 : 10),
                Expanded(child: children[i]),
              ],
            ],
          );
        }
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: compact ? 6 : 10,
          crossAxisSpacing: compact ? 6 : 10,
          // Una sola línea por celda ⇒ altura baja; ratio alto = celda más baja.
          childAspectRatio: compact ? 3.6 : 3.0,
          children: children,
        );
      },
    );
  }
}
