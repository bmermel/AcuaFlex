/// Claves de SharedPreferences usadas en la app.
abstract class PrefsKeys {
  PrefsKeys._();

  /// Si true, al reabrir la app se mantiene la sesión de Firebase.
  /// Si false, al abrir la app se hace signOut y se muestra login.
  static const String keepLoggedIn = 'keep_logged_in';
}
