import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/prefs_keys.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _keepLoggedIn = true;

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final syntheticEmail = AuthService.usernameToSyntheticEmail(_userController.text);
    if (syntheticEmail.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Ingresá un usuario.';
      });
      return;
    }
    try {
      await AuthService.instance.signInWithEmailAndPassword(
        syntheticEmail,
        _passwordController.text,
      );
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.keepLoggedIn, _keepLoggedIn);
      if (!mounted) return;
      context.go(AppRoutes.home);
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
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LogoPlaceholder(),
                const SizedBox(height: 32),
                TextField(
                  controller: _userController,
                  decoration: const InputDecoration(
                    labelText: 'Usuario',
                  ),
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                  ),
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _signIn(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: _keepLoggedIn,
                      onChanged: (v) =>
                          setState(() => _keepLoggedIn = v ?? true),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _keepLoggedIn = !_keepLoggedIn),
                        child: Text(
                          'Mantener sesión iniciada',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _signIn,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Iniciar sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo sin contenedor con color para respetar la transparencia del PNG.
class _LogoPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppTheme.logoAssetPath,
      height: 220,
      fit: BoxFit.contain,
      // Sin color ni colorBlendMode para no alterar el PNG; sin Container/Card con fondo
      errorBuilder: (_, __, ___) => Text(
        'AcuaFlex',
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
      ),
    );
  }
}

