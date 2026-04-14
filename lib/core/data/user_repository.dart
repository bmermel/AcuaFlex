import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth/auth_service.dart';

const String _usersCollection = 'users';

/// Emails que siempre se consideran admin aunque no tengan documento en Firestore (fallback).
const List<String> _seedAdminEmails = [
  'insumosacuarioml@gmail.com',
];

/// Modelo mínimo de usuario para roles y labels.
class AppUser {
  const AppUser({
    required this.uid,
    this.email = '',
    this.role = 'driver',
    this.usuario = '',
    this.displayName = '',
  });

  final String uid;
  final String email;
  final String role; // 'admin' | 'driver'
  /// Login corto guardado al registrar (ej. mismo texto que el usuario de login).
  final String usuario;
  /// Nombre para mostrar opcional en Firestore (displayName, name, nombre).
  final String displayName;

  bool get isAdmin => role.trim().toLowerCase() == 'admin';
  bool get isDriver => role.trim().toLowerCase() == 'driver';
}

class UserRepository {
  UserRepository._();
  static final UserRepository _instance = UserRepository._();
  static UserRepository get instance => _instance;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(_usersCollection);

  Future<AppUser?> getProfile(String uid) async {
    final snap = await _col.doc(uid).get();
    final data = snap.data();
    if (data == null) return null;
    return _docToUser(uid, data);
  }

  Future<bool> isAdmin(String uid) async {
    final user = await getProfile(uid);
    if (user != null && user.isAdmin) return true;
    // Fallback: si no hay perfil o no es admin, comprobar lista de admins por email (p. ej. primer admin)
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser?.uid == uid && authUser?.email != null) {
      final email = authUser!.email!.trim().toLowerCase();
      if (_seedAdminEmails.any((e) => e.toLowerCase() == email)) return true;
    }
    return false;
  }

  Future<List<AppUser>> getAllUsers() async {
    final snap = await _col.get();
    return snap.docs.map((d) => _docToUser(d.id, d.data())).toList();
  }

  /// Si el documento [users] no tiene `email` o `usuario`, los rellena desde Firebase Auth
  /// (útil para cuentas creadas antes de guardar bien el perfil).
  Future<void> syncEmailFromAuthIfMissing() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;
    final email = authUser.email?.trim() ?? '';
    if (email.isEmpty) return;
    final snap = await _col.doc(authUser.uid).get();
    final data = snap.data();
    final existingEmail = (data?['email'] ?? '').toString().trim();
    final existingUsuario = (data?['usuario'] ?? '').toString().trim();
    final map = <String, dynamic>{};
    if (existingEmail.isEmpty) {
      map['email'] = email;
    }
    final lower = email.toLowerCase();
    if (existingUsuario.isEmpty && lower.endsWith(syntheticEmailSuffix)) {
      final local = email.substring(0, email.length - syntheticEmailSuffix.length).trim();
      if (local.isNotEmpty) {
        map['usuario'] = local;
      }
    }
    if (map.isEmpty) return;
    await _col.doc(authUser.uid).set(map, SetOptions(merge: true));
  }

  /// Crea o actualiza el documento del usuario en Firestore (colección users).
  /// Debe llamarse tras crear el usuario en Firebase Auth para que aparezca en filtros y asignaciones.
  /// [loginUsername] se guarda como [usuario] para mostrar el nombre aunque falle la lectura de email.
  Future<void> setUserProfile(
    String uid, {
    required String email,
    required String role,
    String? loginUsername,
  }) async {
    final map = <String, dynamic>{
      'email': email.trim(),
      'role': role.trim().toLowerCase() == 'admin' ? 'admin' : 'driver',
    };
    final u = loginUsername?.trim();
    if (u != null && u.isNotEmpty) {
      map['usuario'] = u;
    }
    await _col.doc(uid).set(map, SetOptions(merge: true));
  }

  /// Actualiza el documento Firestore [users] (perfil editable en la app).
  /// La contraseña de login (Auth) se gestiona en Firebase Console → Authentication.
  Future<void> updateUserDocument(
    String uid, {
    String? email,
    String? role,
    String? usuario,
    String? displayName,
  }) async {
    final map = <String, dynamic>{};
    if (email != null) map['email'] = email.trim();
    if (role != null) {
      map['role'] =
          role.trim().toLowerCase() == 'admin' ? 'admin' : 'driver';
    }
    if (usuario != null) map['usuario'] = usuario.trim();
    if (displayName != null) map['displayName'] = displayName.trim();
    if (map.isEmpty) return;
    await _col.doc(uid).set(map, SetOptions(merge: true));
  }

  /// Texto único para listas, filtros y detalle de entrega.
  static String driverDisplayLabel(AppUser u) {
    final dn = u.displayName.trim();
    if (dn.isNotEmpty) return dn;
    final fromEmail = AuthService.shortDisplayName(u.email);
    if (fromEmail.isNotEmpty) return fromEmail;
    final fromSynthetic = AuthService.syntheticEmailToDisplayUsername(u.email);
    if (fromSynthetic.isNotEmpty) return fromSynthetic;
    final us = u.usuario.trim();
    if (us.isNotEmpty) return us;
    return uidFallbackLabel(u.uid);
  }

  /// Cuando solo tenemos el UID (sin documento users o email vacío).
  static String uidFallbackLabel(String uid) {
    final t = uid.trim();
    if (t.isEmpty) return '—';
    if (t.length <= 8) return 'Conductor ($t)';
    return 'Conductor (…${t.substring(t.length - 6)})';
  }

  AppUser _docToUser(String uid, Map<String, dynamic> data) {
    final email = (data['email'] ?? data['emailAddress'] ?? '').toString().trim();
    final roleRaw = (data['role'] ?? 'driver').toString().trim().toLowerCase();
    final role = roleRaw == 'admin' ? 'admin' : 'driver';
    final usuario = (data['usuario'] ?? data['username'] ?? '').toString().trim();
    final displayName =
        (data['displayName'] ?? data['name'] ?? data['nombre'] ?? '').toString().trim();
    return AppUser(
      uid: uid,
      email: email,
      role: role,
      usuario: usuario,
      displayName: displayName,
    );
  }
}
