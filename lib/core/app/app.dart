import 'package:flutter/material.dart';

import '../router/app_router.dart';
import '../theme/app_theme.dart';

/// Widget raíz de la aplicación AcuaFlex.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AcuaFlex',
      theme: AppTheme.theme,
      routerConfig: createAppRouter(),
    );
  }
}
