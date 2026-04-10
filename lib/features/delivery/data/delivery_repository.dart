import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import '../../../core/data/local_database.dart';
import '../../../core/data/sync_service.dart';
import '../../../core/debug_delivery_log.dart';
import '../domain/delivery.dart';

const String _collection = 'deliveries';
const String _keysCollection = 'delivery_keys';

/// Clave segura para Firestore doc id a partir de orderId (solo alfanum y guión).
String _orderIdDocId(String orderId) {
  return orderId.replaceAll(RegExp(r'[^a-zA-Z0-9\-_]'), '_');
}

/// Clave legacy por (dni, direccion) normalizados para QRs sin orderId.
String legacyDuplicateKey(String normalizedDni, String normalizedDireccion) {
  final combined = '$normalizedDni|$normalizedDireccion';
  final code = combined.hashCode.abs();
  return 'legacy_${code}_${normalizedDni.length}_${normalizedDireccion.length}';
}

class DeliveryRepository {
  DeliveryRepository._();
  static final DeliveryRepository _instance = DeliveryRepository._();
  static DeliveryRepository get instance => _instance;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(_collection);
  CollectionReference<Map<String, dynamic>> get _keysCol =>
      _firestore.collection(_keysCollection);

  CollectionReference<Map<String, dynamic>> _evidencesCol(String deliveryId) =>
      _col.doc(deliveryId).collection('evidences');

  /// Comprime a JPEG; si no se puede decodificar, devuelve bytes crudos (pueden ser grandes).
  static Uint8List _compressToJpeg(Uint8List inputBytes,
      {int maxWidth = 1024, int quality = 70}) {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) return inputBytes;
    img.Image resized = decoded;
    if (decoded.width > maxWidth) {
      resized = img.copyResize(decoded, width: maxWidth);
    }
    var jpg = img.encodeJpg(resized, quality: quality);
    // Firestore doc límite ~1 MiB; base64 ~4/3 del tamaño en bytes
    const int maxJpegBytes = 600000;
    if (jpg.length > maxJpegBytes && quality > 30) {
      jpg = img.encodeJpg(resized, quality: 40);
    }
    return Uint8List.fromList(jpg);
  }

  /// Reemplaza evidencias de "No entregado" (máx 2) en subcolección:
  /// deliveries/{deliveryId}/evidences/{e0|e1}
  /// Guarda base64 JPEG comprimido, type, createdAt, uploadedBy.
  Future<void> replaceNoEntregadoEvidences({
    required String deliveryId,
    required List<({XFile file, String type})> fotos,
    required DateTime createdAt,
    required String uploadedBy,
  }) async {
    final col = _evidencesCol(deliveryId);
    final batch = _firestore.batch();

    // borrar evidencias anteriores (simple y consistente)
    final existing = await col.get();
    for (final d in existing.docs) {
      batch.delete(d.reference);
    }

    for (var i = 0; i < fotos.length && i < 2; i++) {
      final bytes = await fotos[i].file.readAsBytes();
      final compressed = _compressToJpeg(Uint8List.fromList(bytes));
      final b64 = base64Encode(compressed);
      final docRef = col.doc('e$i');
      batch.set(docRef, {
        'type': fotos[i].type,
        'mime': 'image/jpeg',
        'imageBase64': b64,
        'createdAt': Timestamp.fromDate(createdAt),
        'uploadedBy': uploadedBy,
      });
    }

    await batch.commit();
    deliveryDebugLog(
      'delivery_repository.replaceNoEntregadoEvidences',
      'saved noEntregado evidences in subcollection',
      data: {
        'deliveryId': deliveryId,
        'count': fotos.length > 2 ? 2 : fotos.length,
        'uploadedBy': uploadedBy,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getNoEntregadoEvidences(
    String deliveryId,
  ) async {
    final snap = await _evidencesCol(deliveryId).orderBy('createdAt').get();
    return snap.docs.map((d) => d.data()).toList();
  }

  Future<void> createDelivery(Delivery delivery) async {
    deliveryDebugLog(
      'delivery_repository.createDelivery',
      'creating new delivery (local-first)',
      data: {'deliveryId': delivery.id, 'orderId': delivery.orderId, 'conductorId': delivery.conductorId},
    );
    assert(() {
      // ignore: avoid_print
      print('[SCAN_QR] EJECUTA createDelivery -> nueva entrega id=${delivery.id} orderId=${delivery.orderId}');
      return true;
    }());

    // ── Local-first: guardar en SQLite + encolar sync ──
    await SyncService.instance.createDelivery(delivery);

    // ── Keys: intentar crear en Firestore si hay conexión ──
    if (SyncService.instance.isOnline) {
      try {
        if (delivery.hasOrderId) {
          final keyId = _orderIdDocId(delivery.orderId!);
          final keySnap = await _keysCol.doc(keyId).get();
          if (!keySnap.exists) {
            await _keysCol.doc(keyId).set({
              'orderId': delivery.orderId,
              'conductorId': delivery.conductorId,
              'deliveryId': delivery.id,
            });
          }
        } else {
          final nDni = delivery.dni.trim().toLowerCase();
          final nDir = delivery.direccion.trim().toLowerCase();
          final key = legacyDuplicateKey(nDni, nDir);
          final keySnap = await _keysCol.doc(key).get();
          if (!keySnap.exists) {
            await _keysCol.doc(key).set({
              'conductorId': delivery.conductorId,
              'dni': delivery.dni,
              'direccion': delivery.direccion,
            });
          }
        }
      } catch (e) {
        // Keys se sincronizarán cuando vuelva la conexión
        deliveryDebugLog(
          'delivery_repository.createDelivery',
          'failed to create key (offline?)',
          data: {'error': e.toString()},
        );
      }
    }
  }

  /// ConductorId que registró este orderId, o null si no hay clave.
  /// Si la clave existe pero conductorId es null/vacío, devuelve '' (entrega sin asignar).
  Future<String?> getConductorIdByOrderId(String orderId) async {
    final key = await getKeyByOrderId(orderId);
    if (key == null) return null;
    final c = key['conductorId'];
    if (c == null || (c is String && c.isEmpty)) return '';
    return c is String ? c : c.toString();
  }

  /// Índice fuerte: obtiene la clave por orderId (orderId, conductorId, deliveryId).
  /// Devuelve null si no existe. Usar deliveryId para leer el documento exacto en deliveries.
  Future<Map<String, dynamic>?> getKeyByOrderId(String orderId) async {
    final keyId = _orderIdDocId(orderId);
    final snap = await _keysCol.doc(keyId).get();
    if (!snap.exists) return null;
    return snap.data();
  }

  /// ConductorId que registró esta (dni, direccion) legacy, o null.
  Future<String?> getConductorIdByLegacyKey(String normalizedDni, String normalizedDireccion) async {
    final key = legacyDuplicateKey(normalizedDni, normalizedDireccion);
    final snap = await _keysCol.doc(key).get();
    final data = snap.data();
    if (data == null) return null;
    final c = data['conductorId'];
    return c is String ? c : c?.toString();
  }

  Future<Delivery?> getDeliveryById(String id) async {
    final snap = await _col.doc(id).get();
    if (snap.data() == null) return null;
    return _docToDelivery(snap);
  }

  /// Busca la primera entrega por orderId (.limit(1)). Puede fallar si hay duplicados: devuelve solo una.
  Future<Delivery?> getDeliveryByOrderId(String orderId) async {
    final list = await getDeliveriesByOrderId(orderId);
    return list.isEmpty ? null : list.first;
  }

  /// Busca TODAS las entregas con este orderId (fuente de verdad: deliveries).
  /// No asume que hay como máximo una; devuelve la lista completa.
  Future<List<Delivery>> getDeliveriesByOrderId(String orderId) async {
    final snap = await _col
        .where('orderId', isEqualTo: orderId)
        .get();
    final list = snap.docs.map(_docToDelivery).toList();
    deliveryDebugLog(
      'delivery_repository.getDeliveriesByOrderId',
      'found deliveries by orderId',
      data: {
        'orderId': orderId,
        'count': list.length,
        'ids': list.map((d) => d.id).toList(),
        'withConductor': list.where((d) => d.conductorId.trim().isNotEmpty).map((d) => d.id).toList(),
        'withoutConductor': list.where((d) => d.conductorId.trim().isEmpty).map((d) => d.id).toList(),
      },
    );
    return list;
  }

  /// Elimina un documento de deliveries por id (para resolver duplicados).
  Future<void> deleteDelivery(String deliveryId) async {
    await _col.doc(deliveryId).delete();
  }

  /// Borra una entrega por id y deja delivery_keys consistente:
  /// si tenía orderId y quedan otras entregas con ese orderId, actualiza la key;
  /// si no queda ninguna, elimina el documento de la key.
  Future<void> deleteDeliveryAndCleanKey(String deliveryId) async {
    final delivery = await getDeliveryById(deliveryId);
    if (delivery == null) return;
    final orderId = delivery.orderId?.trim();
    await _col.doc(deliveryId).delete();
    if (orderId == null || orderId.isEmpty) return;
    final remaining = await getDeliveriesByOrderId(orderId);
    if (remaining.isEmpty) {
      await _keysCol.doc(_orderIdDocId(orderId)).delete();
    } else {
      final first = remaining.first;
      await updateKeyConductor(orderId, first.conductorId, first.id);
    }
  }

  /// Regla de duplicados: para un mismo orderId solo debe quedar una entrega válida,
  /// salvo el caso permitido de "Agregar igual" (varias con distintos conductores).
  /// - Si hay al menos una con conductor: se conservan todas las que tienen conductor, se eliminan las sin conductor.
  /// - Si todas están sin conductor: se conserva una (la primera), se eliminan el resto.
  /// Actualiza delivery_keys según la entrega conservada y devuelve la lista final.
  Future<List<Delivery>> resolveDuplicatesForOrderId(String orderId) async {
    final all = await getDeliveriesByOrderId(orderId);
    if (all.isEmpty) return [];
    if (all.length == 1) {
      await updateKeyConductor(orderId, all.first.conductorId, all.first.id);
      deliveryDebugLog(
        'delivery_repository.resolveDuplicatesForOrderId',
        'single delivery, no cleanup',
        data: {'orderId': orderId, 'keptId': all.first.id},
      );
      return all;
    }
    final withConductor = all.where((d) => d.conductorId.trim().isNotEmpty).toList();
    final withoutConductor = all.where((d) => d.conductorId.trim().isEmpty).toList();
    if (withConductor.isNotEmpty) {
      for (final d in withoutConductor) {
        await _col.doc(d.id).delete();
        deliveryDebugLog(
          'delivery_repository.resolveDuplicatesForOrderId',
          'deleted duplicate without conductor',
          data: {'orderId': orderId, 'deletedId': d.id},
        );
      }
      await updateKeyConductor(orderId, withConductor.first.conductorId, withConductor.first.id);
      deliveryDebugLog(
        'delivery_repository.resolveDuplicatesForOrderId',
        'kept deliveries with conductor',
        data: {'orderId': orderId, 'keptIds': withConductor.map((d) => d.id).toList()},
      );
      return withConductor;
    }
    for (var i = 1; i < withoutConductor.length; i++) {
      await _col.doc(withoutConductor[i].id).delete();
      deliveryDebugLog(
        'delivery_repository.resolveDuplicatesForOrderId',
        'deleted duplicate without conductor',
        data: {'orderId': orderId, 'deletedId': withoutConductor[i].id},
      );
    }
    final kept = withoutConductor.first;
    await updateKeyConductor(orderId, '', kept.id);
    deliveryDebugLog(
      'delivery_repository.resolveDuplicatesForOrderId',
      'kept single without conductor',
      data: {'orderId': orderId, 'canonicalId': kept.id},
    );
    return [kept];
  }

  /// REGLA ESTRICTA: Si existe al menos una entrega sin conductor para este orderId,
  /// actualiza la canónica con el conductor y elimina el resto sin conductor. NO crear.
  /// Devuelve true si se hizo claim+limpieza; false si todas ya tenían conductor.
  Future<bool> claimCanonicalAndRemoveDuplicatesWithoutConductor(
    String orderId,
    String conductorId,
  ) async {
    final all = await getDeliveriesByOrderId(orderId);
    final withoutConductor = all.where((d) => d.conductorId.trim().isEmpty).toList();
    if (withoutConductor.isEmpty) {
      deliveryDebugLog(
        'delivery_repository.claimCanonicalAndRemoveDuplicatesWithoutConductor',
        'no delivery without conductor, will not create',
        data: {'orderId': orderId, 'allHaveConductor': true},
      );
      return false;
    }
    final canonical = withoutConductor.first;
    deliveryDebugLog(
      'delivery_repository.claimCanonicalAndRemoveDuplicatesWithoutConductor',
      'chose canonical without conductor',
      data: {'orderId': orderId, 'canonicalId': canonical.id, 'withoutCount': withoutConductor.length},
    );
    final updated = canonical.copyWith(conductorId: conductorId);
    await _col.doc(updated.id).update(updated.toMap());
    await updateKeyConductor(orderId, conductorId, updated.id);
    deliveryDebugLog(
      'delivery_repository.claimCanonicalAndRemoveDuplicatesWithoutConductor',
      'updated canonical with conductor',
      data: {'orderId': orderId, 'updatedId': updated.id, 'conductorId': conductorId},
    );
    for (var i = 1; i < withoutConductor.length; i++) {
      await _col.doc(withoutConductor[i].id).delete();
      deliveryDebugLog(
        'delivery_repository.claimCanonicalAndRemoveDuplicatesWithoutConductor',
        'deleted duplicate without conductor',
        data: {'orderId': orderId, 'deletedId': withoutConductor[i].id},
      );
    }
    return true;
  }

  /// Reasigna una entrega existente (por id) al conductor. Actualiza doc y key.
  Future<void> claimDeliveryById(String deliveryId, String conductorId) async {
    final delivery = await getDeliveryById(deliveryId);
    if (delivery == null || !delivery.hasOrderId) return;
    final updated = delivery.copyWith(conductorId: conductorId);
    await _col.doc(updated.id).update(updated.toMap());
    await updateKeyConductor(delivery.orderId!, conductorId, updated.id);
  }

  /// Reasigna una entrega existente (por orderId) al conductor. Actualiza doc y key.
  /// Usa la primera entrega encontrada; conviene llamar después de resolveDuplicatesForOrderId.
  Future<void> claimDeliveryByOrderId(String orderId, String conductorId) async {
    final delivery = await getDeliveryByOrderId(orderId);
    if (delivery == null) return;
    final updated = delivery.copyWith(conductorId: conductorId);
    await _col.doc(updated.id).update(updated.toMap());
    await updateKeyConductor(orderId, conductorId, updated.id);
  }

  /// Actualiza el conductor en delivery_keys para un orderId (al editar asignación).
  /// Si se pasa deliveryId se mantiene/actualiza en la key.
  Future<void> updateKeyConductor(String orderId, String conductorId, [String? deliveryId]) async {
    final keyId = _orderIdDocId(orderId);
    final data = <String, dynamic>{
      'orderId': orderId,
      'conductorId': conductorId,
    };
    if (deliveryId != null && deliveryId.isNotEmpty) data['deliveryId'] = deliveryId;
    await _keysCol.doc(keyId).set(data, SetOptions(merge: true));
  }

  Future<List<Delivery>> getDeliveriesByDriver(String conductorId) async {
    // ── Local-first: devolver datos locales + sync en background ──
    try {
      return await SyncService.instance.getDeliveriesByDriver(conductorId);
    } catch (_) {
      // Fallback a Firestore directo si local falla
      final snap = await _col
          .where('conductorId', isEqualTo: conductorId)
          .orderBy('fechaEscaneo', descending: true)
          .get();
      return snap.docs.map(_docToDelivery).toList();
    }
  }

  Stream<List<Delivery>> watchAllDeliveries() {
    return _col
        .orderBy('fechaEscaneo', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(_docToDelivery).toList());
  }

  Stream<List<Delivery>> watchDeliveriesByDriver(String conductorId) {
    return _col
        .where('conductorId', isEqualTo: conductorId)
        .orderBy('fechaEscaneo', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(_docToDelivery).toList());
  }

  Future<void> updateDelivery(Delivery delivery) async {
    // ── Local-first: actualizar local + sync ──
    await SyncService.instance.updateDelivery(delivery);
  }

  /// Limpieza admin: para cada orderId con 2+ entregas donde al menos una tiene conductor y al menos una no:
  /// elimina solo las que no tienen conductor y deja las que sí tienen.
  /// No toca orderIds donde todas tienen conductor ni donde todas están sin conductor.
  /// Devuelve { 'orderIdsAffected': N, 'documentsDeleted': M }.
  Future<Map<String, int>> cleanDuplicateManualWithoutConductor(List<Delivery> all) async {
    final withOrderId = all.where((d) => d.hasOrderId).toList();
    final byOrderId = <String, List<Delivery>>{};
    for (final d in withOrderId) {
      byOrderId.putIfAbsent(d.orderId!, () => []).add(d);
    }
    int documentsDeleted = 0;
    int orderIdsAffected = 0;
    for (final entry in byOrderId.entries) {
      final list = entry.value;
      if (list.length < 2) continue;
      final withConductor = list.where((d) => d.conductorId.trim().isNotEmpty).toList();
      final withoutConductor = list.where((d) => d.conductorId.trim().isEmpty).toList();
      if (withConductor.isEmpty || withoutConductor.isEmpty) continue;
      orderIdsAffected++;
      for (final d in withoutConductor) {
        await _col.doc(d.id).delete();
        documentsDeleted++;
      }
      await updateKeyConductor(entry.key, withConductor.first.conductorId, withConductor.first.id);
    }
    return {'orderIdsAffected': orderIdsAffected, 'documentsDeleted': documentsDeleted};
  }

  Delivery _docToDelivery(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = Map<String, dynamic>.from(doc.data()!);
    _timestampToDateTime(data, 'fechaEscaneo');
    _timestampToDateTime(data, 'fechaEntrega');
    _timestampToDateTime(data, 'fechaFirma');
    _timestampToDateTime(data, 'fechaNoEntrega');
    return Delivery.fromMap(data);
  }

  void _timestampToDateTime(Map<String, dynamic> data, String key) {
    final v = data[key];
    if (v is Timestamp) data[key] = v.toDate();
  }
}
