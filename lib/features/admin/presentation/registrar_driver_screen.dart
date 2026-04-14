import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/data/user_repository.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// Pantalla admin para registrar un nuevo usuario (driver o admin).
/// Crea la cuenta en Firebase Auth y el documento en Firestore users en un solo paso.
/// Tras registrar, la sesión pasa al nuevo usuario; se hace signOut y se redirige a login.
class RegistrarDriverScreen extends StatefulWidget {
  const RegistrarDriverScreen({super.key});

  @override
  State<RegistrarDriverScreen> createState() => _RegistrarDriverScreenState();
}

class _RegistrarDriverScreenState extends State<RegistrarDriverScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usuarioController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String _role = 'driver';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usuarioController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
    });
    if (!_formKey.currentState!.validate()) return;

    final usuario = _usuarioController.text.trim();
    final password = _passwordController.text;
    final email = AuthService.usernameToSyntheticEmail(usuario);
    if (email.isEmpty) {
      setState(() => _error = 'Ingresá un usuario o email válido.');
      return;
    }

    setState(() => _loading = true);
    try {
      await AuthService.instance.createUserWithEmailAndPassword(email, password);
      final uid = AuthService.instance.currentUser?.uid;
      if (uid == null) {
        setState(() {
          _loading = false;
          _error = 'No se pudo obtener el usuario creado.';
        });
        return;
      }
      await UserRepository.instance.setUserProfile(
        uid,
        email: email,
        role: _role,
        loginUsername: usuario,
      );
      await AuthService.instance.signOut();
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Usuario registrado. Aparecerá en filtros y asignaciones. Iniciá sesión de nuevo.',
          ),
          backgroundColor: AppTheme.adminEntregadoColor,
          duration: Duration(seconds: 4),
        ),
      );
      context.go(AppRoutes.login);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AuthService.userFriendlyAuthMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo driver'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _loading ? null : () => context.pop(),
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
              'Registrar nuevo usuario',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Se crea la cuenta de login y el perfil en la app. El usuario aparecerá en filtros y asignación de conductor.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _usuarioController,
              decoration: const InputDecoration(
                labelText: 'Usuario o email',
                hintText: 'Ej. karina o bmermel@gmail.com',
              ),
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Ingresá el usuario o email';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                hintText: 'Mínimo 6 caracteres',
              ),
              obscureText: true,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Ingresá la contraseña';
                if (v.length < 6) return 'Mínimo 6 caracteres';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmController,
              decoration: const InputDecoration(
                labelText: 'Confirmar contraseña',
              ),
              obscureText: true,
              validator: (v) {
                if (v != _passwordController.text) {
                  return 'No coincide con la contraseña';
                }
                return null;
              },
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
              onChanged: (v) => setState(() => _role = v ?? 'driver'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add),
              label: Text(_loading ? 'Registrando...' : 'Registrar usuario'),
            ),
            const SizedBox(height: 16),
            Text(
              'Tras registrar tendrás que iniciar sesión de nuevo con tu usuario de admin.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
