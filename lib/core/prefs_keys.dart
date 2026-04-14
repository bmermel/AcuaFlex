/// Claves de SharedPreferences usadas en la app.
abstract class PrefsKeys {
  PrefsKeys._();

  /// Si true, al reabrir la app se mantiene la sesión de Firebase.
  /// Si false, al abrir la app se hace signOut y se muestra login.
  static const String keepLoggedIn = 'keep_logged_in';

  /// `latestVersionCode` de Firestore que el usuario pospuso con "Más tarde".
  static const String dismissedAppUpdateVersionCode =
      'dismissed_app_update_version_code';

  /// Día local (YYYY-M-D) en que ya se mostró el aviso de arrastre pendiente.
  static const String driverCarryoverReminderDate =
      'driver_carryover_reminder_date';

  /// Vista compacta del listado «Mis entregas» para conductores.
  static const String driverListCompact = 'driver_list_compact';

  /// Home admin: true = solo opciones de conductor; false = solo opciones de administración.
  static const String homeDriverModeAdmin = 'home_driver_mode_admin';
}
