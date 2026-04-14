import 'package:flutter/material.dart';

import 'core/bootstrap/acua_bootstrap.dart';
import 'core/bootstrap/loader_registrar.dart';
import 'core/utils/system_ui_mobile.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerLoaderViewIfWeb();
  applyHideBottomSystemNavigationBar();
  runApp(const AcuaFlexBootstrap());
}
