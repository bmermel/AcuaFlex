import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/user_repository.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// Crea o actualiza el documento [users/{uid}] para una cuenta que ya existe en
/// Firebase Authentication pero aún no tiene (o hay que completar) perfil en Firestore.
/// El UID se obtiene desde Firebase Console → Authentication → Usuario → UID.
class AdminLinkUserScreen extends StatefulWidget {
  const AdminLinkUserScreen({super.key});

  @override
  State<AdminLinkUserScreen> createState() => _AdminLinkUserScreenState();
}

class _AdminLinkUserScreenState extends State<AdminLinkUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uidController = TextEditingController();
  final _emailController = TextEditingController();
  final _usuarioController = TextEditingController();
  final _displayNameController = TextEditingController();
  String _role = 'driver';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _uidController.dispose();
    _emailController.dispose();
    _usuarioController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final uid = _uidController.text.trim();
    if (uid.isEmpty) {
      setState(() => _error = 'El UID es obligatorio.');
      return;
    }

    final existing = await UserRepository.instance.getProfile(uid);
    if (!mounted) return;

    if (existing != null) {
      final merge = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Perfil existente'),
          content: Text(
            'Ya hay un documento en users para este UID '
            '(${UserRepository.driverDisplayLabel(existing)}). '
            '¿Actualizar con los datos del formulario?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Actualizar'),
            ),
          ],
        ),
      );
      if (merge != true || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      await UserRepository.instance.updateUserDocument(
        uid,
        email: _emailController.text,
        role: _role,
        usuario: _usuarioController.text,
        displayName: _displayNameController.text,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Perfil vinculado. Ya aparece en la lista de usuarios.'
                : 'Perfil actualizado.',
          ),
          backgroundColor: AppTheme.adminEntregadoColor,
        ),
      );
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go(AppRoutes.adminUsers);
      }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vincular usuario'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _saving ? null : () => context.pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              children: [
                Text(
                  'Usuario solo en Authentication',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Si la cuenta ya fue creada en Firebase Auth pero no tiene '
                  'documento en la colección users (o querés completarlo), '
                  'copiá el UID desde la consola de Firebase: '
                  'Authentication → Usuario → UID. '
                  'Comprobá en la misma consola que el email coincida con el de la cuenta.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _uidController,
                  decoration: const InputDecoration(
                    labelText: 'UID de Firebase',
                    hintText: 'Pegá el UID completo',
                  ),
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Requerido';
                    }
                    if (v.trim().length < 8) {
                      return 'UID demasiado corto; revisá el pegado.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email (perfil en la app)',
                    hintText: 'Mismo que figura en Authentication',
                  ),
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usuarioController,
                  decoration: const InputDecoration(
                    labelText: 'Usuario (login corto)',
                    hintText: 'Opcional, para mostrar en la app',
                  ),
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre para mostrar',
                    hintText: 'Opcional',
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _role,
                  decoration: const InputDecoration(
                    labelText: 'Rol',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'driver', child: Text('Driver')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _role = v ?? 'driver'),
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
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: Text(_saving ? 'Guardando...' : 'Guardar perfil'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
