import 'package:flutter/material.dart';

import '../router/app_router.dart';
import '../theme/app_theme.dart';
import '../utils/system_ui_mobile.dart';

/// Widget raíz de la aplicación AcuaFlex.
class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    applyHideBottomSystemNavigationBar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      applyHideBottomSystemNavigationBar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AcuaFlex',
      theme: AppTheme.theme,
      routerConfig: createAppRouter(),
    );
  }
}
