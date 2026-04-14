import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_service.dart';
import '../prefs_keys.dart';
import '../utils/driver_delivery_visibility.dart';
import '../../features/delivery/data/delivery_repository.dart';
import '../../features/delivery/domain/delivery.dart';

/// Purga de pendientes viejos, “rollover” de arrastre a la fecha de hoy, y aviso (una vez por sesión/día).
class DriverSessionMaintenance {
  DriverSessionMaintenance._();

  /// Evita repetir el diálogo en la misma sesión (Home + listado).
  static String? _dialogShownForUid;

  /// Llamar desde Home o desde el listado de entregas tras el primer frame.
  static Future<void> runIfNeeded(BuildContext context) async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null || !context.mounted) return;

    try {
      await DeliveryRepository.instance.purgeStalePendingDeliveries(uid);
    } catch (_) {
      // Sin red u otro error: no bloquear la app
    }

    List<Delivery> list;
    try {
      list = await DeliveryRepository.instance.getDeliveriesByDriver(uid);
    } catch (_) {
      return;
    }

    final carryovers =
        list.where(DriverDeliveryVisibility.isCarryoverFromPriorDays).toList();
    if (carryovers.isEmpty) return;

    final n = carryovers.length;
    final now = DateTime.now();
    for (final d in carryovers) {
      try {
        await DeliveryRepository.instance.updateDelivery(
          d.copyWith(fechaEscaneo: now),
        );
      } catch (_) {
        // Sin red: puede reintentarse en el próximo runIfNeeded
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final todayKey = _todayKey();
    if (prefs.getString(PrefsKeys.driverCarryoverReminderDate) == todayKey) {
      return;
    }
    if (_dialogShownForUid == uid) return;

    _dialogShownForUid = uid;
    await prefs.setString(PrefsKeys.driverCarryoverReminderDate, todayKey);

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Entregas pendientes'),
        content: Text(
          'Tenías $n entrega(s) pendiente(s) o no realizada(s) de días anteriores. '
          'Ya las dejamos cargadas con la fecha de hoy para que sigas con ellas '
          '(salvo que un admin las borre). Revisálas en «Mis entregas».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }
}
