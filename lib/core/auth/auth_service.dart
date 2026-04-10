import 'package:firebase_auth/firebase_auth.dart';

/// Sufijo para emails sintéticos (Firebase exige formato email válido).
const String syntheticEmailSuffix = '@acuaflex.local';

/// Servicio de autenticación (Firebase Auth) singleton.
class AuthService {
  AuthService._();
  static final AuthService _instance = AuthService._();
  static AuthService get instance => _instance;

  FirebaseAuth get _auth => FirebaseAuth.instance;
  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> signOut() => _auth.signOut();

  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return cred.user;
  }

  /// Crea un usuario en Firebase Auth con email y contraseña.
  /// Tras crearlo, la sesión actual pasa a ser la del nuevo usuario (Firebase así lo hace).
  /// Usar solo desde admin para registrar drivers; después hacer signOut() y redirigir a login.
  Future<User?> createUserWithEmailAndPassword(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    return cred.user;
  }

  /// Convierte el texto del campo "Usuario" al email que se usa en Firebase Auth.
  /// - Si contiene @: se trata como email real y se usa tal cual (solo trim).
  /// - Si no contiene @: se normaliza (trim, minúsculas, espacios → _) y se agrega @acuaflex.local.
  static String usernameToSyntheticEmail(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.contains('@')) return trimmed;
    final n = trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    return '$n$syntheticEmailSuffix';
  }

  /// Si [email] es un email sintético (termina en @acuaflex.local), devuelve
  /// la parte "usuario" para mostrar en UI. Si no, devuelve el email tal cual.
  static String syntheticEmailToDisplayUsername(String? email) {
    if (email == null || email.trim().isEmpty) return '';
    final e = email.trim();
    if (e.endsWith(syntheticEmailSuffix)) {
      final user = e.substring(0, e.length - syntheticEmailSuffix.length);
      return user.isEmpty ? e : user;
    }
    return e;
  }

  /// Nombre corto para mostrar en filtros y labels: parte antes de @, o el texto completo si no hay @.
  /// Ej: karina@acuaflex.local → karina, bmermel@gmail.com → bmermel.
  static String shortDisplayName(String? email) {
    if (email == null || email.trim().isEmpty) return '';
    final e = email.trim();
    final i = e.indexOf('@');
    if (i > 0) return e.substring(0, i);
    return e;
  }

  /// Mensaje legible para el usuario a partir de errores de Firebase Auth.
  static String userFriendlyAuthMessage(Object? error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'wrong-password':
          return 'Contraseña incorrecta.';
        case 'user-not-found':
          return 'Usuario no encontrado.';
        case 'invalid-email':
          return 'El usuario no es válido.';
        case 'invalid-credential':
          return 'Credenciales incorrectas. Revisá usuario y contraseña.';
        case 'user-disabled':
          return 'Esta cuenta fue deshabilitada.';
        case 'too-many-requests':
          return 'Demasiados intentos. Esperá un momento e intentá de nuevo.';
        case 'network-request-failed':
          return 'Sin conexión. Revisá tu red e intentá de nuevo.';
        case 'operation-not-allowed':
          return 'El inicio de sesión no está habilitado.';
        case 'email-already-in-use':
          return 'Ese usuario o email ya está registrado.';
        case 'weak-password':
          return 'La contraseña es muy corta. Usá al menos 6 caracteres.';
        default:
          return 'Error al iniciar sesión. Intentá de nuevo.';
      }
    }
    return 'Error inesperado. Intentá de nuevo.';
  }
}
