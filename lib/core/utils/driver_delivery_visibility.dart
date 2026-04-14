import 'date_utils.dart' as app_date;
import '../../features/delivery/domain/delivery.dart';
import '../../features/delivery/domain/delivery_state.dart';

/// Reglas de visibilidad para el listado del conductor (no aplica al panel admin).
class DriverDeliveryVisibility {
  DriverDeliveryVisibility._();

  /// Entregas [entregado] solo se muestran el mismo día calendario que [fechaEntrega].
  /// Sin fecha de entrega, no se muestran (evita que queden colgadas de días anteriores).
  static bool isEntregadoVisibleInDailyList(Delivery d) {
    if (d.estado != DeliveryState.entregado) return true;
    final fe = d.fechaEntrega;
    if (fe == null) return false;
    final now = DateTime.now();
    return app_date.AppDateUtils.startOfDay(fe) ==
        app_date.AppDateUtils.startOfDay(now);
  }

  /// Lista para «Mis entregas»: oculta entregas completadas de días anteriores.
  static List<Delivery> filterForDailyDriverList(List<Delivery> raw) {
    return raw.where(isEntregadoVisibleInDailyList).toList();
  }

  /// Pendiente o no entregado cuyo escaneo es de antes de hoy (arrastre de días previos).
  static bool isCarryoverFromPriorDays(Delivery d) {
    if (d.estado != DeliveryState.pendiente &&
        d.estado != DeliveryState.noEntregado) {
      return false;
    }
    final todayStart = app_date.AppDateUtils.startOfDay(DateTime.now());
    return d.fechaEscaneo.isBefore(todayStart);
  }

  static int carryoverCount(List<Delivery> raw) {
    return raw.where(isCarryoverFromPriorDays).length;
  }
}
