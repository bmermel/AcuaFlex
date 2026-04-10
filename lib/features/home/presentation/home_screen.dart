import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/data/sync_service.dart';
import '../../../core/data/user_repository.dart';
import '../../../core/prefs_keys.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool? _isAdmin;

  @override
  void initState() {
    super.initState();
    _loadRole();
    // Intentar full sync al cargar la pantalla
    final uid = AuthService.instance.currentUser?.uid;
    if (uid != null) {
      SyncService.instance.fullSync(uid);
    }
  }

  Future<void> _loadRole() async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return;
    final admin = await UserRepository.instance.isAdmin(uid);
    if (mounted) setState(() => _isAdmin = admin);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AcuaFlex'),
        actions: [
          // Indicador de sync status
          ValueListenableBuilder<SyncStatus>(
            valueListenable: SyncService.instance.statusNotifier,
            builder: (_, status, __) {
              return ValueListenableBuilder<int>(
                valueListenable: SyncService.instance.pendingCountNotifier,
                builder: (_, pendingCount, __) {
                  IconData icon;
                  Color color;
                  String tooltip;

                  switch (status) {
                    case SyncStatus.online:
                      if (pendingCount > 0) {
                        icon = Icons.sync_problem;
                        color = AppTheme.pendienteColor;
                        tooltip = '$pendingCount pendientes de sync';
                      } else {
                        icon = Icons.cloud_done;
                        color = AppTheme.entregadoColor;
                        tooltip = 'Sincronizado';
                      }
                      break;
                    case SyncStatus.offline:
                      icon = Icons.cloud_off;
                      color = AppTheme.noEntregadoColor;
                      tooltip = 'Sin conexión${pendingCount > 0 ? ' ($pendingCount pendientes)' : ''}';
                      break;
                    case SyncStatus.syncing:
                      icon = Icons.sync;
                      color = AppTheme.primaryBlue;
                      tooltip = 'Sincronizando...';
                      break;
                  }

                  return IconButton(
                    icon: Icon(icon, color: color),
                    tooltip: tooltip,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(tooltip),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                      // Si hay pendientes y hay conexión, forzar sync
                      if (pendingCount > 0 && status != SyncStatus.offline) {
                        final uid = AuthService.instance.currentUser?.uid;
                        if (uid != null) SyncService.instance.fullSync(uid);
                      }
                    },
                  );
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthService.instance.signOut();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool(PrefsKeys.keepLoggedIn, false);
              if (context.mounted) context.go(AppRoutes.login);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Image.asset(
              AppTheme.logoAssetPath,
              height: 160,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Text(
                'AcuaFlex',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _MenuTile(
            icon: Icons.qr_code_scanner,
            title: 'Escanear QR',
            onTap: () => context.push(AppRoutes.scan),
          ),
          _MenuTile(
            icon: Icons.list_alt,
            title: 'Mis entregas',
            onTap: () => context.push(AppRoutes.deliveryList),
          ),
          _MenuTile(
            icon: Icons.today,
            title: 'Cierre diario',
            onTap: () => context.push(AppRoutes.cierreDiario),
          ),
          if (_isAdmin == true) ...[
            _MenuTile(
              icon: Icons.admin_panel_settings,
              title: 'Panel admin',
              onTap: () => context.push(AppRoutes.admin),
            ),
            _MenuTile(
              icon: Icons.add_circle_outline,
              title: 'Crear entrega manual',
              onTap: () => context.push(AppRoutes.crearEntregaManual),
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        onTap: onTap,
      ),
    );
  }
}

