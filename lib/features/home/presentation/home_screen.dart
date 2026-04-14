import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/layout/app_breakpoints.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/driver/driver_session_maintenance.dart';
import '../../../core/update/app_update_prompt.dart';
import '../../../core/data/sync_service.dart';
import '../../../core/data/user_repository.dart';
import '../../../core/prefs_keys.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/acuario_logo.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool? _isAdmin;
  /// Solo si [_isAdmin]: true = menú conductor; false = menú administración.
  bool _driverMode = false;

  @override
  void initState() {
    super.initState();
    _loadDriverModePref();
    _loadRole();
    // Intentar full sync al cargar la pantalla
    final uid = AuthService.instance.currentUser?.uid;
    if (uid != null) {
      UserRepository.instance.syncEmailFromAuthIfMissing();
      SyncService.instance.fullSync(uid);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await AppUpdatePrompt.maybeShow(context);
      if (!mounted) return;
      await DriverSessionMaintenance.runIfNeeded(context);
    });
  }

  Future<void> _loadDriverModePref() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _driverMode = prefs.getBool(PrefsKeys.homeDriverModeAdmin) ?? false;
    });
  }

  Future<void> _setDriverMode(bool value) async {
    setState(() => _driverMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.homeDriverModeAdmin, value);
  }

  Future<void> _loadRole() async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return;
    final admin = await UserRepository.instance.isAdmin(uid);
    if (mounted) setState(() => _isAdmin = admin);
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final hPad = screenW < AppBreakpoints.narrowScreenWidth ? 12.0 : 24.0;
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
        padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 24),
        children: [
          const SizedBox(height: 8),
          Center(
            child: AcuarioLogo(
              height: 160,
              maxWidth: 420,
            ),
          ),
          const SizedBox(height: 24),
          if (_isAdmin == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_isAdmin == false) ...[
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
          ] else ...[
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: SwitchListTile(
                secondary: Icon(
                  _driverMode
                      ? Icons.local_shipping_outlined
                      : Icons.admin_panel_settings_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(_driverMode ? 'Modo Driver' : 'Modo Admin'),
                subtitle: Text(
                  _driverMode
                      ? 'Escanear QR, entregas y cierre diario'
                      : 'Panel admin, reportes y entregas manuales',
                ),
                value: _driverMode,
                onChanged: (v) => _setDriverMode(v),
              ),
            ),
            if (_driverMode) ...[
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
            ] else ...[
              _MenuTile(
                icon: Icons.admin_panel_settings,
                title: 'Panel admin',
                onTap: () => context.push(AppRoutes.admin),
              ),
              _MenuTile(
                icon: Icons.bar_chart_outlined,
                title: 'Reportes de envíos',
                onTap: () => context.push(AppRoutes.adminReports),
              ),
              _MenuTile(
                icon: Icons.add_circle_outline,
                title: 'Crear entrega manual',
                onTap: () => context.push(AppRoutes.crearEntregaManual),
              ),
            ],
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

