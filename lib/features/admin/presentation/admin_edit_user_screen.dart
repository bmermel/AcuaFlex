import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/data/user_repository.dart';
import '../../../core/theme/app_theme.dart';

/// Edición del perfil en Firestore [users] (mismos datos que al registrar, más nombre visible).
class AdminEditUserScreen extends StatefulWidget {
  const AdminEditUserScreen({super.key, required this.userId});

  final String userId;

  @override
  State<AdminEditUserScreen> createState() => _AdminEditUserScreenState();
}

class _AdminEditUserScreenState extends State<AdminEditUserScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  late final TextEditingController _usuarioController;
  late final TextEditingController _emailController;
  String _role = 'driver';
  bool _loading = true;
  bool _saving = false;
  String? _error;
  AppUser? _user;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _usuarioController = TextEditingController();
    _emailController = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final u = await UserRepository.instance.getProfile(widget.userId);
      if (!mounted) return;
      if (u == null) {
        setState(() {
          _loading = false;
          _error = 'No existe documento en users para este UID.';
        });
        return;
      }
      _user = u;
      _displayNameController.text = u.displayName;
      _usuarioController.text = u.usuario;
      _emailController.text = u.email;
      _role = u.isAdmin ? 'admin' : 'driver';
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usuarioController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final myUid = AuthService.instance.currentUser?.uid;
    final wasAdmin = _user?.isAdmin ?? false;
    final newRole = _role;
    if (myUid == widget.userId && wasAdmin && newRole == 'driver') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Quitar rol admin'),
          content: const Text(
            'Vas a dejar de ser administrador en la app. '
            'Asegurate de que haya otro admin activo. ¿Continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí, guardar'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      await UserRepository.instance.updateUserDocument(
        widget.userId,
        displayName: _displayNameController.text,
        usuario: _usuarioController.text,
        email: _emailController.text,
        role: _role,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil actualizado.'),
          backgroundColor: AppTheme.adminEntregadoColor,
        ),
      );
      context.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelf = AuthService.instance.currentUser?.uid == widget.userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar usuario'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _saving ? null : () => context.pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _user == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        children: [
                          if (isSelf)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                'Estás editando tu propio perfil.',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          Text(
                            'Nombre, usuario, email en perfil y rol se guardan en Firestore. '
                            'La contraseña de acceso se gestiona en Firebase Console → Authentication '
                            '(no desde esta pantalla).',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _displayNameController,
                            decoration: const InputDecoration(
                              labelText: 'Nombre para mostrar',
                              hintText: 'Ej. María González',
                            ),
                            textCapitalization: TextCapitalization.words,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _usuarioController,
                            decoration: const InputDecoration(
                              labelText: 'Usuario (login corto)',
                              hintText: 'Mismo concepto que al registrar',
                            ),
                            textCapitalization: TextCapitalization.none,
                            autocorrect: false,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email en perfil',
                              hintText: 'Copia informativa en la app',
                            ),
                            textCapitalization: TextCapitalization.none,
                            autocorrect: false,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _role,
                            decoration: const InputDecoration(
                              labelText: 'Rol',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'driver',
                                child: Text('Driver'),
                              ),
                              DropdownMenuItem(
                                value: 'admin',
                                child: Text('Admin'),
                              ),
                            ],
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _role = v ?? 'driver'),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'UID: ${widget.userId}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                          const SizedBox(height: 28),
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(_saving ? 'Guardando...' : 'Guardar'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
