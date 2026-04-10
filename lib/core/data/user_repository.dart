import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const String _usersCollection = 'users';

/// Emails que siempre se consideran admin aunque no tengan documento en Firestore (fallback).
const List<String> _seedAdminEmails = [
  'insumosacuarioml@gmail.com',
];

/// Modelo mínimo de usuario para roles y labels.
class AppUser {
  const AppUser({required this.uid, this.email = '', this.role = 'driver'});
  final String uid;
  final String email;
  final String role; // 'admin' | 'driver'

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

  /// Crea o actualiza el documento del usuario en Firestore (colección users).
  /// Debe llamarse tras crear el usuario en Firebase Auth para que aparezca en filtros y asignaciones.
  Future<void> setUserProfile(String uid, {required String email, required String role}) async {
    await _col.doc(uid).set({
      'email': email.trim(),
      'role': role.trim().toLowerCase() == 'admin' ? 'admin' : 'driver',
    }, SetOptions(merge: true));
  }

  AppUser _docToUser(String uid, Map<String, dynamic> data) {
    final email = (data['email'] ?? data['emailAddress'] ?? '').toString().trim();
    final roleRaw = (data['role'] ?? 'driver').toString().trim().toLowerCase();
    final role = roleRaw == 'admin' ? 'admin' : 'driver';
    return AppUser(
      uid: uid,
      email: email,
      role: role,
    );
  }
}
