import 'package:flutter/material.dart';

import '../layout/app_breakpoints.dart';

/// Coloca [children] en **fila** con [Expanded] o en **columna** a ancho completo,
/// según el ancho disponible (evita botones aplastados en móviles angostos).
class AdaptiveButtonRow extends StatelessWidget {
  const AdaptiveButtonRow({
    super.key,
    required this.children,
    this.breakpoint = AppBreakpoints.compactButtonRow,
    this.spacing = 8,
  });

  final List<Widget> children;
  final double breakpoint;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < breakpoint;

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}
