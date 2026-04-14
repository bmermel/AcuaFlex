import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme/app_theme.dart';

/// Logo Acuario vectorial (SVG) para login y home.
class AcuarioLogo extends StatelessWidget {
  const AcuarioLogo({
    super.key,
    required this.height,
    this.maxWidth,
  });

  final double height;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final child = SvgPicture.asset(
      AppTheme.acuarioLogoAssetPath,
      height: height,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      allowDrawingOutsideViewBox: true,
      placeholderBuilder: (context) => SizedBox(
        height: height,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
    if (maxWidth != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: child,
      );
    }
    return child;
  }
}
