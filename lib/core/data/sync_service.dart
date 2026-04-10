import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, ValueNotifier;

import '../../features/delivery/domain/delivery.dart';
import '../debug_delivery_log.dart';
import 'local_database.dart';

/// Estado de conectividad de la app.
enum SyncStatus {
  online,
  offline,
  syncing,
}

/// Servicio de sincronización: guarda localmente y sincroniza con Firestore.
///
/// Patrón local-first:
/// 1. Todas las escrituras van primero a SQLite local.
/// 2. Si hay conexión, se sincronizan inmediatamente con Firestore.
/// 3. Si no hay conexión, se encolan en pending_sync.
/// 4. Cuando vuelve la conexión, se procesan las operaciones pendientes.
class SyncService {
  SyncService._();
  static final SyncService _instance = SyncService._();
  static SyncService get instance => _instance;

  final LocalDatabase _localDb = LocalDatabase.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Connectivity _connectivity = Connectivity();

  final ValueNotifier<SyncStatus> statusNotifier =
      ValueNotifier(SyncStatus.online);
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier(0);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _syncTimer;
  bool _isSyncing = false;

  CollectionReference<Map<String, dynamic>> get _deliveriesCol =>
      _firestore.collection('deliveries');
  CollectionReference<Map<String, dynamic>> get _keysCol =>
      _firestore.collection('delivery_keys');

  /// Inicializar el servicio. Llamar una vez después de LocalDatabase.init().
  /// En web, solo se monitoea la conectividad (no hay offline sync).
  Future<void> init() async {
    try {
      // Verificar conectividad inicial
      final results = await _connectivity.checkConnectivity();
      _updateStatus(results);

      // Escuchar cambios de conectividad
      _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
        _updateStatus(results);
        if (_isOnline(results)) {
          _processPendingSyncs();
        }
      });

      // Timer periódico para reintentar syncs pendientes (solo si no es web)
      if (!kIsWeb) {
        _syncTimer = Timer.periodic(const Duration(minutes: 2), (_) {
          if (statusNotifier.value != SyncStatus.offline) {
            _processPendingSyncs();
          }
        });
      }

      // Actualizar contador de pendientes
      await _refreshPendingCount();

      if (kDebugMode) {
        // ignore: avoid_print
        print('[SYNC] SyncService initialized, status: ${statusNotifier.value}');
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SYNC] Init failed: $e (may be running on web)');
      }
      // Asumir que estamos online en web (sin offline sync)
      statusNotifier.value = SyncStatus.online;
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
    _syncTimer?.cancel();
  }

  bool get isOnline => statusNotifier.value != SyncStatus.offline;

  void _updateStatus(List<ConnectivityResult> results) {
    final wasOffline = statusNotifier.value == SyncStatus.offline;
    if (_isOnline(results)) {
      if (statusNotifier.value != SyncStatus.syncing) {
        statusNotifier.value = SyncStatus.online;
      }
    } else {
      statusNotifier.value = SyncStatus.offline;
    }
    if (wasOffline && isOnline && kDebugMode) {
      // ignore: avoid_print
      print('[SYNC] Connection restored, will process pending syncs');
    }
  }

  bool _isOnline(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
  }

  Future<void> _refreshPendingCount() async {
    try {
      pendingCountNotifier.value = await _localDb.pendingSyncCount();
    } catch (e) {
      // En web o si la DB no está disponible, asumir 0
      pendingCountNotifier.value = 0;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SYNC] Could not refresh pending count: $e');
      }
    }
  }

  // ─────────────────── Operaciones Local-First ───────────────────

  /// Crea una entrega: guarda local + intenta sync.
  Future<void> createDelivery(Delivery delivery) async {
    // Web: no hay SQLite; escribir solo en Firestore.
    if (kIsWeb) {
      if (!isOnline) {
        throw StateError(
          'Sin conexión: en el navegador no hay cola offline; '
          'comprobá la red e intentá de nuevo.',
        );
      }
      try {
        await _syncCreateToFirestore(delivery);
        deliveryDebugLog(
          'sync_service.createDelivery',
          'synced immediately (web)',
          data: {'deliveryId': delivery.id},
        );
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[SYNC] Failed to sync create on web: $e');
        }
        rethrow;
      }
      return;
    }

    // 1. Guardar localmente
    await _localDb.upsertDelivery(delivery);

    // 2. Intentar sync
    if (isOnline) {
      try {
        await _syncCreateToFirestore(delivery);
        deliveryDebugLog(
          'sync_service.createDelivery',
          'synced immediately',
          data: {'deliveryId': delivery.id},
        );
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[SYNC] Failed to sync create, queuing: $e');
        }
        await _enqueueSync(delivery.id, 'create', delivery.toMap());
      }
    } else {
      await _enqueueSync(delivery.id, 'create', delivery.toMap());
    }
  }

  /// Actualiza una entrega: guarda local + intenta sync.
  Future<void> updateDelivery(Delivery delivery) async {
    if (kIsWeb) {
      if (!isOnline) {
        throw StateError(
          'Sin conexión: en el navegador no se puede actualizar sin red.',
        );
      }
      await _deliveriesCol.doc(delivery.id).update(delivery.toMap());
      deliveryDebugLog(
        'sync_service.updateDelivery',
        'synced immediately (web)',
        data: {'deliveryId': delivery.id},
      );
      return;
    }

    await _localDb.upsertDelivery(delivery);

    if (isOnline) {
      try {
        await _deliveriesCol.doc(delivery.id).update(delivery.toMap());
        deliveryDebugLog(
          'sync_service.updateDelivery',
          'synced immediately',
          data: {'deliveryId': delivery.id},
        );
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[SYNC] Failed to sync update, queuing: $e');
        }
        await _enqueueSync(delivery.id, 'update', delivery.toMap());
      }
    } else {
      await _enqueueSync(delivery.id, 'update', delivery.toMap());
    }
  }

  /// Elimina una entrega: elimina local + intenta sync.
  Future<void> deleteDelivery(String deliveryId) async {
    if (kIsWeb) {
      if (isOnline) {
        try {
          await _deliveriesCol.doc(deliveryId).delete();
        } catch (e) {
          rethrow;
        }
      } else {
        throw StateError(
          'Sin conexión: en el navegador no se puede eliminar sin red.',
        );
      }
      return;
    }

    await _localDb.deleteDelivery(deliveryId);

    if (isOnline) {
      try {
        await _deliveriesCol.doc(deliveryId).delete();
      } catch (e) {
        await _enqueueSync(deliveryId, 'delete', null);
      }
    } else {
      await _enqueueSync(deliveryId, 'delete', null);
    }
  }

  /// Obtiene entregas por conductor: primero local, luego intenta sync desde Firestore.
  /// En web, devuelve desde Firestore directamente.
  Future<List<Delivery>> getDeliveriesByDriver(String conductorId) async {
    try {
      // Siempre devolver datos locales primero (respuesta inmediata)
      final local = await _localDb.getDeliveriesByDriver(conductorId);

      // Si hay conexión, intentar actualizar en background
      if (isOnline) {
        _syncDeliveriesFromFirestore(conductorId);
      }

      return local;
    } catch (e) {
      // Fallback a Firestore si local no funciona (web)
      final snap = await _deliveriesCol
          .where('conductorId', isEqualTo: conductorId)
          .orderBy('fechaEscaneo', descending: true)
          .get();
      return snap.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        _timestampToIso(data, 'fechaEscaneo');
        _timestampToIso(data, 'fechaEntrega');
        _timestampToIso(data, 'fechaFirma');
        _timestampToIso(data, 'fechaNoEntrega');
        return Delivery.fromMap(data);
      }).toList();
    }
  }

  /// Obtiene entregas por orderId desde local.
  /// En web, devuelve desde Firestore directamente.
  Future<List<Delivery>> getDeliveriesByOrderId(String orderId) async {
    try {
      return await _localDb.getDeliveriesByOrderId(orderId);
    } catch (e) {
      // Fallback a Firestore si local no funciona
      final snap = await _deliveriesCol
          .where('orderId', isEqualTo: orderId)
          .get();
      return snap.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        _timestampToIso(data, 'fechaEscaneo');
        _timestampToIso(data, 'fechaEntrega');
        _timestampToIso(data, 'fechaFirma');
        _timestampToIso(data, 'fechaNoEntrega');
        return Delivery.fromMap(data);
      }).toList();
    }
  }

  /// Obtiene una entrega por id desde local.
  /// En web, devuelve desde Firestore directamente.
  Future<Delivery?> getDeliveryById(String id) async {
    try {
      return await _localDb.getDeliveryById(id);
    } catch (e) {
      // Fallback a Firestore si local no funciona
      final doc = await _deliveriesCol.doc(id).get();
      if (!doc.exists) return null;
      final data = Map<String, dynamic>.from(doc.data() ?? {});
      _timestampToIso(data, 'fechaEscaneo');
      _timestampToIso(data, 'fechaEntrega');
      _timestampToIso(data, 'fechaFirma');
      _timestampToIso(data, 'fechaNoEntrega');
      return Delivery.fromMap(data);
    }
  }

  /// Fuerza una sincronización completa desde Firestore para un conductor.
  Future<void> fullSync(String conductorId) async {
    if (!isOnline) return;

    statusNotifier.value = SyncStatus.syncing;
    try {
      // Descargar entregas del conductor desde Firestore
      final snap = await _deliveriesCol
          .where('conductorId', isEqualTo: conductorId)
          .orderBy('fechaEscaneo', descending: true)
          .get();

      final deliveries = snap.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        _timestampToIso(data, 'fechaEscaneo');
        _timestampToIso(data, 'fechaEntrega');
        _timestampToIso(data, 'fechaFirma');
        _timestampToIso(data, 'fechaNoEntrega');
        return Delivery.fromMap(data);
      }).toList();

      if (!kIsWeb) {
        await _localDb.upsertDeliveries(deliveries);
        // Procesar pendientes
        await _processPendingSyncs();
      }

      if (kDebugMode) {
        // ignore: avoid_print
        print('[SYNC] Full sync completed: ${deliveries.length} deliveries');
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SYNC] Full sync failed: $e');
      }
    } finally {
      statusNotifier.value = isOnline ? SyncStatus.online : SyncStatus.offline;
    }
  }

  // ─────────────────── Sync Internals ───────────────────

  Future<void> _enqueueSync(
      String deliveryId, String operation, Map<String, dynamic>? data) async {
    await _localDb.addPendingSync(
      deliveryId: deliveryId,
      operation: operation,
      data: data,
    );
    await _refreshPendingCount();
  }

  Future<void> _syncCreateToFirestore(Delivery delivery) async {
    await _deliveriesCol.doc(delivery.id).set(delivery.toMap());

    // También crear la key si tiene orderId
    if (delivery.hasOrderId) {
      final keyId =
          delivery.orderId!.replaceAll(RegExp(r'[^a-zA-Z0-9\-_]'), '_');
      final keySnap = await _keysCol.doc(keyId).get();
      if (!keySnap.exists) {
        await _keysCol.doc(keyId).set({
          'orderId': delivery.orderId,
          'conductorId': delivery.conductorId,
          'deliveryId': delivery.id,
        });
      }
    }
  }

  Future<void> _processPendingSyncs() async {
    if (kIsWeb) return;
    if (_isSyncing) return;
    _isSyncing = true;
    statusNotifier.value = SyncStatus.syncing;

    try {
      final pending = await _localDb.getPendingSyncs();
      if (pending.isEmpty) {
        _isSyncing = false;
        statusNotifier.value = SyncStatus.online;
        return;
      }

      if (kDebugMode) {
        // ignore: avoid_print
        print('[SYNC] Processing ${pending.length} pending syncs');
      }

      for (final item in pending) {
        final id = item['id'] as int;
        final deliveryId = item['deliveryId'] as String;
        final operation = item['operation'] as String;
        final dataStr = item['data'] as String?;

        try {
          switch (operation) {
            case 'create':
              if (dataStr != null) {
                final data = jsonDecode(dataStr) as Map<String, dynamic>;
                // Convertir fechas ISO string de vuelta a DateTime para toMap
                _isoToTimestamp(data, 'fechaEscaneo');
                _isoToTimestamp(data, 'fechaEntrega');
                _isoToTimestamp(data, 'fechaFirma');
                _isoToTimestamp(data, 'fechaNoEntrega');
                await _deliveriesCol.doc(deliveryId).set(data);
                // Crear key si tiene orderId
                final orderId = data['orderId']?.toString().trim() ?? '';
                if (orderId.isNotEmpty) {
                  final keyId =
                      orderId.replaceAll(RegExp(r'[^a-zA-Z0-9\-_]'), '_');
                  await _keysCol.doc(keyId).set({
                    'orderId': orderId,
                    'conductorId': data['conductorId'] ?? '',
                    'deliveryId': deliveryId,
                  }, SetOptions(merge: true));
                }
              }
              break;
            case 'update':
              if (dataStr != null) {
                final data = jsonDecode(dataStr) as Map<String, dynamic>;
                _isoToTimestamp(data, 'fechaEscaneo');
                _isoToTimestamp(data, 'fechaEntrega');
                _isoToTimestamp(data, 'fechaFirma');
                _isoToTimestamp(data, 'fechaNoEntrega');
                await _deliveriesCol.doc(deliveryId).update(data);
              }
              break;
            case 'delete':
              await _deliveriesCol.doc(deliveryId).delete();
              break;
          }

          await _localDb.removePendingSync(id);
          if (kDebugMode) {
            // ignore: avoid_print
            print('[SYNC] Synced: $operation $deliveryId');
          }
        } catch (e) {
          if (kDebugMode) {
            // ignore: avoid_print
            print('[SYNC] Failed to sync $operation $deliveryId: $e');
          }
          await _localDb.incrementRetryCount(id);
        }
      }

      // Limpiar syncs con muchos reintentos fallidos
      await _localDb.cleanupFailedSyncs();
    } finally {
      _isSyncing = false;
      statusNotifier.value = isOnline ? SyncStatus.online : SyncStatus.offline;
      await _refreshPendingCount();
    }
  }

  /// Sincroniza entregas desde Firestore al local en background.
  Future<void> _syncDeliveriesFromFirestore(String conductorId) async {
    try {
      final snap = await _deliveriesCol
          .where('conductorId', isEqualTo: conductorId)
          .orderBy('fechaEscaneo', descending: true)
          .get();

      final deliveries = snap.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        _timestampToIso(data, 'fechaEscaneo');
        _timestampToIso(data, 'fechaEntrega');
        _timestampToIso(data, 'fechaFirma');
        _timestampToIso(data, 'fechaNoEntrega');
        return Delivery.fromMap(data);
      }).toList();

      if (!kIsWeb) {
        await _localDb.upsertDeliveries(deliveries);
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SYNC] Background sync from Firestore failed: $e');
      }
    }
  }

  /// Convierte Timestamp de Firestore a DateTime en un Map.
  void _timestampToIso(Map<String, dynamic> data, String key) {
    final v = data[key];
    if (v is Timestamp) {
      data[key] = v.toDate();
    }
  }

  /// Convierte ISO string de vuelta a Timestamp para Firestore.
  void _isoToTimestamp(Map<String, dynamic> data, String key) {
    final v = data[key];
    if (v is String && v.isNotEmpty) {
      final dt = DateTime.tryParse(v);
      if (dt != null) {
        data[key] = Timestamp.fromDate(dt);
      }
    }
    // Si ya es DateTime, convertir a Timestamp
    if (v is DateTime) {
      data[key] = Timestamp.fromDate(v);
    }
  }
}
