import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app/app.dart';
import 'core/auth/auth_service.dart';
import 'core/data/local_database.dart';
import 'core/data/sync_service.dart';
import 'core/prefs_keys.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Inicializar base de datos local y servicio de sincronización
  await LocalDatabase.instance.init();
  await SyncService.instance.init();

  // Si el usuario no eligió "Mantener sesión iniciada", limpiar sesión al abrir la app.
  final prefs = await SharedPreferences.getInstance();
  final keepLoggedIn = prefs.getBool(PrefsKeys.keepLoggedIn) ?? true;
  if (!keepLoggedIn) {
    await AuthService.instance.signOut();
  }

  runApp(const App());
}
