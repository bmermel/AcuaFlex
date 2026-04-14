import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:acuaflex_v1/core/app/app.dart';
import 'package:acuaflex_v1/core/auth/auth_service.dart';
import 'package:acuaflex_v1/core/data/local_database.dart';
import 'package:acuaflex_v1/core/data/sync_service.dart';
import 'package:acuaflex_v1/core/prefs_keys.dart';
import 'package:acuaflex_v1/core/theme/app_theme.dart';
import 'package:acuaflex_v1/core/bootstrap/web_splash.dart';
import 'package:acuaflex_v1/firebase_options.dart';
import 'package:acuaflex_v1/widgets/fish_loader.dart';

/// Arranque en dos fases:
/// 1. [runApp] de inmediato con una UI mínima → el splash nativo de Android puede ocultarse
///    en cuanto Flutter pinta el primer frame (antes todo el init bloqueaba antes de [runApp]).
/// 2. Inicialización async con timeouts y mensajes de error visibles en el dispositivo.
class AcuaFlexBootstrap extends StatefulWidget {
  const AcuaFlexBootstrap({super.key});

  @override
  State<AcuaFlexBootstrap> createState() => _AcuaFlexBootstrapState();
}

class _AcuaFlexBootstrapState extends State<AcuaFlexBootstrap> {
  bool _ready = false;
  Object? _error;

  static const Duration _firebaseTimeout = Duration(seconds: 45);
  static const Duration _dbTimeout = Duration(seconds: 25);
  static const Duration _syncTimeout = Duration(seconds: 25);
  static const Duration _signOutTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    // Oculta el splash HTML de web/index.html en el primer frame de Flutter.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kIsWeb) removeHtmlSplashOverlay();
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _ensureFirebaseInitialized();

      await LocalDatabase.instance.init().timeout(_dbTimeout);
      await SyncService.instance.init().timeout(_syncTimeout);

      final prefs = await SharedPreferences.getInstance();
      final keepLoggedIn = prefs.getBool(PrefsKeys.keepLoggedIn) ?? true;
      if (!keepLoggedIn) {
        try {
          await AuthService.instance.signOut().timeout(_signOutTimeout);
        } catch (_) {
          // Sin red u otro fallo: no bloquear el arranque.
        }
      }
    } on TimeoutException catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[BOOT] Timeout: $e\n$st');
      }
      if (mounted) setState(() => _error = e);
      return;
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[BOOT] Error: $e\n$st');
      }
      if (mounted) setState(() => _error = e);
      return;
    }
    if (mounted) setState(() => _ready = true);
  }

  /// En Android el plugin `google-services` puede inicializar Firebase en nativo
  /// antes que Dart; si además llamamos [Firebase.initializeApp], aparece
  /// `[core/duplicate-app]`. Eso no es fallo: seguimos con la app ya creada.
  Future<void> _ensureFirebaseInitialized() async {
    if (Firebase.apps.isNotEmpty) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(_firebaseTimeout);
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app') {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[BOOT] Firebase [DEFAULT] ya existía (nativo o carrera); OK');
        }
        return;
      }
      rethrow;
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _ready = false;
    });
    _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return const App();
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTheme.paletteTeal,
          brightness: Brightness.light,
        ),
      ),
      home: Scaffold(
        backgroundColor:
            _error != null ? AppTheme.scaffoldBackground : AppTheme.paletteInk,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _error != null
                  ? _BootstrapError(error: _error!, onRetry: _retry)
                  : const _BootstrapLoading(),
            ),
          ),
        ),
      ),
    );
  }
}

class _BootstrapLoading extends StatelessWidget {
  const _BootstrapLoading();

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const SizedBox(
        width: 300,
        height: 400,
        child: HtmlElementView(viewType: 'acua-css-loader'),
      );
    }
    return const FishLoader();
  }
}

class _BootstrapError extends StatelessWidget {
  const _BootstrapError({
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.wifi_off, size: 56, color: AppTheme.noEntregadoColor),
        const SizedBox(height: 16),
        Text(
          'No se pudo iniciar',
          style: textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Revisá datos/Wi‑Fi, actualizá Google Play Services y probá de nuevo.',
          style: textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              error.toString(),
              style: textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      ],
    );
  }
}
