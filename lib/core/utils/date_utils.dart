/// Utilidades de fecha compartidas para filtros (cierre diario, panel admin).
class AppDateUtils {
  AppDateUtils._();

  /// Inicio del día (00:00:00) para la fecha dada.
  static DateTime startOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  /// Fin del día (exclusivo: 00:00:00 del día siguiente).
  static DateTime endOfDay(DateTime d) =>
      startOfDay(d).add(const Duration(days: 1));

  /// Primer instante del mes calendario de [d].
  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  /// Primer instante del mes siguiente a [d].
  static DateTime startOfNextMonth(DateTime d) =>
      DateTime(d.year, d.month + 1, 1);

  /// Primer instante del mes anterior a [d].
  static DateTime startOfPreviousMonth(DateTime d) =>
      DateTime(d.year, d.month - 1, 1);

  /// True si [value] está en el rango [start, end) (start inclusivo, end exclusivo).
  static bool isInRange(DateTime value, DateTime start, DateTime end) =>
      !value.isBefore(start) && value.isBefore(end);

  static DateTime get _now => DateTime.now();

  /// Rango [inicio, fin) del día calendario de [d] (hora local).
  static (DateTime start, DateTime end) dayRange(DateTime d) =>
      (startOfDay(d), endOfDay(d));

  /// Inicio y fin (exclusivo) del día de hoy.
  static (DateTime start, DateTime end) get todayRange {
    final start = startOfDay(_now);
    return (start, endOfDay(_now));
  }

  /// Inicio y fin (exclusivo) del día de ayer.
  static (DateTime start, DateTime end) get yesterdayRange {
    final yesterday = _now.subtract(const Duration(days: 1));
    return (startOfDay(yesterday), endOfDay(yesterday));
  }

  /// Inicio del rango "últimos 7 días" (00:00 de hace 7 días); el fin es "ahora".
  static DateTime get last7DaysStart =>
      startOfDay(_now).subtract(const Duration(days: 7));
}
