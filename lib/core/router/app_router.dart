import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_screen.dart';
import '../../features/admin/presentation/registrar_driver_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/cierre_diario/presentation/cierre_diario_screen.dart';
import '../../features/delivery/presentation/confirmar_entrega_screen.dart';
import '../../features/delivery/presentation/crear_entrega_manual_screen.dart';
import '../../features/delivery/presentation/delivery_detail_screen.dart';
import '../../features/delivery/presentation/editar_entrega_manual_screen.dart';
import '../../features/delivery/presentation/delivery_list_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/scan_qr/presentation/scan_qr_screen.dart';
import '../auth/auth_service.dart';
import '../data/user_repository.dart';

/// Rutas nombradas de la app.
abstract class AppRoutes {
  static const String login = '/login';
  static const String home = '/home';
  static const String scan = '/scan';
  static const String deliveryList = '/deliveries';
  static String deliveryDetailPath(String id) => '/deliveries/$id';
  static String confirmarEntregaPath(String id) => '/deliveries/$id/confirmar';
  static const String cierreDiario = '/cierre-diario';
  static const String admin = '/admin';
  static const String crearEntregaManual = '/admin/crear-manual';
  static const String registrarDriver = '/admin/registrar-driver';
  static String editarEntregaPath(String id) => '/deliveries/$id/editar';
}

GoRouter createAppRouter() {
  final authState = ValueNotifier<Object?>(AuthService.instance.currentUser);
  AuthService.instance.authStateChanges.listen((_) {
    authState.value = AuthService.instance.currentUser;
  });

  return GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: authState,
    redirect: (context, state) async {
      final user = AuthService.instance.currentUser;
      final onLogin = state.matchedLocation == AppRoutes.login;
      if (user == null && !onLogin) return AppRoutes.login;
      if (user != null && onLogin) return AppRoutes.home;

      // Guard admin: solo usuarios con rol admin pueden acceder a /admin y rutas admin
      final isAdminRoute = state.matchedLocation == AppRoutes.admin ||
          state.matchedLocation == AppRoutes.crearEntregaManual ||
          state.matchedLocation == AppRoutes.registrarDriver ||
          state.matchedLocation.startsWith('/deliveries/') && state.matchedLocation.endsWith('/editar');
      if (isAdminRoute) {
        if (user == null) return AppRoutes.login;
        final isAdmin = await UserRepository.instance.isAdmin(user.uid);
        if (!isAdmin) return AppRoutes.home;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.scan,
        builder: (_, __) => const ScanQrScreen(),
      ),
      GoRoute(
        path: AppRoutes.deliveryList,
        builder: (_, __) => const DeliveryListScreen(),
      ),
      GoRoute(
        path: '/deliveries/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return DeliveryDetailScreen(deliveryId: id);
        },
      ),
      GoRoute(
        path: '/deliveries/:id/confirmar',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ConfirmarEntregaScreen(deliveryId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.cierreDiario,
        builder: (_, __) => const CierreDiarioScreen(),
      ),
      GoRoute(
        path: AppRoutes.admin,
        builder: (_, __) => const AdminScreen(),
      ),
      GoRoute(
        path: AppRoutes.crearEntregaManual,
        builder: (_, __) => const CrearEntregaManualScreen(),
      ),
      GoRoute(
        path: AppRoutes.registrarDriver,
        builder: (_, __) => const RegistrarDriverScreen(),
      ),
      GoRoute(
        path: '/deliveries/:id/editar',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return EditarEntregaManualScreen(deliveryId: id);
        },
      ),
    ],
  );
}
