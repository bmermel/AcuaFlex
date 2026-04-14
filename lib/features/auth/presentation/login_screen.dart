import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/layout/app_breakpoints.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/prefs_keys.dart';
import '../../../core/router/app_router.dart';
import '../../../widgets/acuario_logo.dart';

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
        _error = 'Ingresá un usuario o email.';
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
    final screenW = MediaQuery.sizeOf(context).width;
    final hPad = screenW < AppBreakpoints.narrowScreenWidth ? 16.0 : 24.0;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AcuarioLogo(height: 180),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _userController,
                    decoration: const InputDecoration(
                      labelText: 'Usuario o email',
                      helperText:
                          'Si incluís @, es un email real. Si no, usuario corto como antes.',
                    ),
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    keyboardType: TextInputType.emailAddress,
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
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _signIn,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Iniciar sesión'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
