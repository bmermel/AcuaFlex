import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/data/user_repository.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// Listado de todos los usuarios (Firestore [users]) y acceso a edición.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  Future<List<AppUser>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = UserRepository.instance.getAllUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuarios'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.admin),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar lista',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
          IconButton(
            tooltip: 'Vincular usuario (UID)',
            icon: const Icon(Icons.link),
            onPressed: () async {
              final ok = await context.push<bool>(AppRoutes.adminLinkUser);
              if (mounted && ok == true) _reload();
            },
          ),
          IconButton(
            tooltip: 'Nuevo usuario',
            icon: const Icon(Icons.person_add_outlined),
            onPressed: () => context.push(AppRoutes.registrarDriver),
          ),
        ],
      ),
      body: FutureBuilder<List<AppUser>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error al cargar usuarios: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          var list = snapshot.data ?? [];
          list = List<AppUser>.from(list)
            ..sort((a, b) => UserRepository.driverDisplayLabel(a)
                .toLowerCase()
                .compareTo(UserRepository.driverDisplayLabel(b).toLowerCase()));
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'No hay documentos en la colección users.',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Si ya hay cuentas en Authentication, vinculá el UID desde la consola.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.push(AppRoutes.registrarDriver),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Registrar usuario'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await context.push<bool>(AppRoutes.adminLinkUser);
                      if (mounted && ok == true) _reload();
                    },
                    icon: const Icon(Icons.link),
                    label: const Text('Vincular por UID'),
                  ),
                ],
              ),
            );
          }

          final myUid = AuthService.instance.currentUser?.uid;

          return RefreshIndicator(
            onRefresh: () async {
              final f = UserRepository.instance.getAllUsers();
              setState(() => _future = f);
              await f;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final u = list[i];
                final label = UserRepository.driverDisplayLabel(u);
                final isSelf = myUid != null && u.uid == myUid;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: u.isAdmin
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        u.isAdmin ? Icons.admin_panel_settings : Icons.local_shipping_outlined,
                        size: 22,
                        color: u.isAdmin
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    title: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (u.email.isNotEmpty)
                          Text(
                            u.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        if (u.usuario.isNotEmpty && u.usuario != label)
                          Text(
                            'Usuario: ${u.usuario}',
                            style: theme.textTheme.bodySmall,
                          ),
                        Text(
                          'UID: ${u.uid}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(
                          label: Text(u.isAdmin ? 'Admin' : 'Driver'),
                          backgroundColor: u.isAdmin
                              ? AppTheme.adminSelectedTint
                              : theme.colorScheme.surfaceContainerHighest,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                        if (isSelf)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              'Vos',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    onTap: () async {
                      await context.push(AppRoutes.adminEditUserPath(u.uid));
                      if (mounted) _reload();
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
