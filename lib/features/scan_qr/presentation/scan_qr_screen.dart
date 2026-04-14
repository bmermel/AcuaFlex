import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/debug_delivery_log.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/qr_parser.dart';
import '../../delivery/data/delivery_repository.dart';
import '../../delivery/domain/delivery.dart';

class _ScanMessages {
  static const String missingFields =
      'Faltan datos en el QR. Debe incluir nombre, DNI y dirección.';
  static const String duplicateOwn =
      'Este pedido ya fue cargado por vos.';
  static const String duplicateOtherDriver =
      'Este pedido ya fue escaneado por otro conductor. ¿Deseas agregarlo igual a tu lista?';
  static const String claimManualSuccess =
      'Entrega agregada a tu lista.';
  static const String qrLegacyWarning =
      'Este QR no incluye orderId (identificador único). '
      'Puede haber duplicados si se escanea más de una vez. ¿Agregar igual?';
  static const String success = 'Entrega cargada correctamente';
  static const String saveError =
      'No se pudo guardar. Revisá la conexión e intentá de nuevo.';
  static const String cameraError = 'Error de cámara o lectura.';
}

/// Resultado de intentar reclamar por delivery_keys -> deliveryId -> documento exacto.
enum _ReclaimByKeyResult { updated, sameDriver, otherDriver, fallback }

class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessing = false;
  String? _lastScannedValue;
  DateTime? _lastScannedTime;
  static const _cooldownSeconds = 3;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  static String _normalize(String s) => s.trim().toLowerCase();

  static bool _hasRequiredFields(Map<String, dynamic> json) {
    String r(String key) {
      final v = json[key];
      if (v == null) return '';
      return (v is String ? v : v.toString()).trim();
    }
    return r('nombre').isNotEmpty && r('dni').isNotEmpty && r('direccion').isNotEmpty;
  }

  static bool _hasOrderId(Map<String, dynamic> json) {
    final v = json['orderId'];
    if (v == null) return false;
    return (v is String ? v : v.toString()).trim().isNotEmpty;
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (capture.barcodes.isEmpty) return;
    final rawValue = capture.barcodes.first.rawValue?.trim();
    if (rawValue == null || rawValue.isEmpty) return;
    if (_isProcessing) return;
    final now = DateTime.now();
    if (_lastScannedValue == rawValue &&
        _lastScannedTime != null &&
        now.difference(_lastScannedTime!).inSeconds < _cooldownSeconds) {
      return;
    }

    setState(() => _isProcessing = true);

    // ── Parser flexible: intenta JSON, URL, key=value, delimitado, texto ──
    final parseResult = QrParser.parse(rawValue);

    deliveryDebugLog(
      'scan_qr_screen._onBarcodeDetected',
      'QR parsed with flexible parser',
      data: {
        'parseMethod': parseResult.parseMethod,
        'isComplete': parseResult.isComplete,
        'hasAnyData': parseResult.hasAnyData,
        'fieldsKeys': parseResult.fields.keys.toList(),
      },
    );

    Map<String, dynamic> json;

    if (parseResult.parseMethod == 'json') {
      // JSON directo: usar el JSON original para compatibilidad completa
      try {
        json = jsonDecode(rawValue) as Map<String, dynamic>;
      } catch (_) {
        json = QrParser.toDeliveryJson(parseResult);
      }
    } else {
      // Formato no-JSON: construir JSON compatible
      json = QrParser.toDeliveryJson(parseResult);
    }

    // Si faltan campos requeridos → mostrar formulario de edición manual
    if (!_hasRequiredFields(json)) {
      if (mounted) {
        setState(() => _isProcessing = false);
        final editedJson = await _showEditQrDataDialog(json, rawValue, parseResult.parseMethod);
        if (editedJson == null) return; // usuario canceló
        json = editedJson;
        setState(() => _isProcessing = true);

        // Re-validar después de edición
        if (!_hasRequiredFields(json)) {
          if (mounted) {
            setState(() => _isProcessing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(_ScanMessages.missingFields),
                duration: const Duration(seconds: 4),
                backgroundColor: AppTheme.pendienteColor,
              ),
            );
          }
          return;
        }
      } else {
        return;
      }
    }

    final conductorId = AuthService.instance.currentUser?.uid ?? 'unknown';
    // FIX: orderId puede venir como int o String desde el QR — normalizar siempre a String.
    final rawOrderId = json['orderId'];
    final orderIdFromJson = rawOrderId == null ? '' : rawOrderId.toString().trim();
    final rawSourceType = json['sourceType'];
    final hasSourceType = rawSourceType != null && rawSourceType.toString().trim().isNotEmpty;
    final rawSourceNumber = json['sourceNumber'];
    final hasSourceNumber = rawSourceNumber != null && rawSourceNumber.toString().trim().isNotEmpty;
    final hasOrderId = _hasOrderId(json) || hasSourceType || hasSourceNumber;
    deliveryDebugLog(
      'scan_qr_screen._onBarcodeDetected',
      'QR scanned, parsed JSON',
      data: {
        'rawValueLength': rawValue.length,
        'rawValueExact': rawValue.length > 500 ? '${rawValue.substring(0, 500)}...' : rawValue,
        'parsedJsonKeys': json.keys.toList(),
        'hasOrderId': hasOrderId,
        'orderId': orderIdFromJson.isEmpty ? null : orderIdFromJson,
        'sourceType': json['sourceType'],
        'sourceNumber': json['sourceNumber'],
        'createdManually': json['createdManually'],
      },
    );
    if (kDebugMode) {
      // ignore: avoid_print
      print('[SCAN_QR] rawValue length=${rawValue.length} orderId="$orderIdFromJson" hasOrderId=$hasOrderId keys=${json.keys.toList()}');
    }

    if (hasOrderId) {
      await _processWithOrderId(context, json, conductorId, now, rawValue);
    } else {
      await _processLegacyQr(context, json, conductorId, now, rawValue);
    }

    if (mounted) setState(() => _isProcessing = false);
  }

  /// Ruta principal: delivery_keys por orderId -> deliveryId -> getDeliveryById.
  /// Si encuentra documento sin conductor: actualiza ese doc y la key, devuelve [updated].
  /// Si mismo conductor: [sameDriver]. Si otro conductor: [otherDriver]. Si no hay key/doc: [fallback].
  Future<_ReclaimByKeyResult> _tryReclaimByKey(String orderId, String conductorId) async {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[SCAN_QR] orderId leído del QR: "$orderId"');
    }
    deliveryDebugLog(
      'scan_qr_screen._tryReclaimByKey',
      'orderId from QR',
      data: {'orderId': orderId},
    );
    final key = await DeliveryRepository.instance.getKeyByOrderId(orderId);
    if (key == null) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SCAN_QR] key NO encontrada en delivery_keys -> fallback');
      }
      deliveryDebugLog('scan_qr_screen._tryReclaimByKey', 'key not found', data: {'orderId': orderId});
      return _ReclaimByKeyResult.fallback;
    }
    final deliveryIdRaw = key['deliveryId'];
    final deliveryId = deliveryIdRaw is String ? deliveryIdRaw.trim() : (deliveryIdRaw?.toString().trim() ?? '');
    if (deliveryId.isEmpty) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SCAN_QR] key sin deliveryId -> fallback');
      }
      deliveryDebugLog('scan_qr_screen._tryReclaimByKey', 'key has no deliveryId', data: {'orderId': orderId});
      return _ReclaimByKeyResult.fallback;
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print('[SCAN_QR] key encontrada, deliveryId: $deliveryId');
    }
    deliveryDebugLog('scan_qr_screen._tryReclaimByKey', 'key found', data: {'orderId': orderId, 'deliveryId': deliveryId});
    final doc = await DeliveryRepository.instance.getDeliveryById(deliveryId);
    if (doc == null) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SCAN_QR] documento deliveries/$deliveryId NO existe -> fallback');
      }
      deliveryDebugLog('scan_qr_screen._tryReclaimByKey', 'delivery doc not found', data: {'orderId': orderId, 'deliveryId': deliveryId});
      return _ReclaimByKeyResult.fallback;
    }
    final docConductor = (doc.conductorId).trim();
    if (kDebugMode) {
      // ignore: avoid_print
      print('[SCAN_QR] documento leído: id=${doc.id} conductorId="${doc.conductorId}" (vacío=${docConductor.isEmpty})');
    }
    deliveryDebugLog(
      'scan_qr_screen._tryReclaimByKey',
      'delivery doc read',
      data: {'orderId': orderId, 'deliveryId': doc.id, 'hasConductor': docConductor.isNotEmpty, 'conductorId': docConductor},
    );
    if (docConductor.isEmpty) {
      final updated = doc.copyWith(conductorId: conductorId);
      await DeliveryRepository.instance.updateDelivery(updated);
      await DeliveryRepository.instance.updateKeyConductor(orderId, conductorId, updated.id);
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SCAN_QR] documento SIN conductor -> ACTUALIZADO (no se creó uno nuevo)');
      }
      deliveryDebugLog(
        'scan_qr_screen._tryReclaimByKey',
        'updated existing doc, no new created',
        data: {'orderId': orderId, 'deliveryId': doc.id, 'conductorId': conductorId},
      );
      return _ReclaimByKeyResult.updated;
    }
    if (docConductor == conductorId) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SCAN_QR] mismo conductor -> ya cargado por vos');
      }
      deliveryDebugLog('scan_qr_screen._tryReclaimByKey', 'same driver', data: {'orderId': orderId});
      return _ReclaimByKeyResult.sameDriver;
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print('[SCAN_QR] otro conductor -> advertencia / Agregar igual');
    }
    deliveryDebugLog('scan_qr_screen._tryReclaimByKey', 'other driver', data: {'orderId': orderId, 'existingConductor': docConductor});
    return _ReclaimByKeyResult.otherDriver;
  }

  /// Reclama una entrega manual existente (sin conductor) para este orderId.
  /// FALLBACK: solo se usa cuando delivery_keys no tiene key o deliveryId. Busca en deliveries por orderId.
  Future<bool> _reclamarEntregaManualExistente(
    String orderId,
    String conductorId, {
    required String rawValue,
    required DateTime now,
  }) async {
    final all = await DeliveryRepository.instance.getDeliveriesByOrderId(orderId);
    deliveryDebugLog(
      'scan_qr_screen._reclamarEntregaManualExistente',
      'deliveries found by orderId',
      data: {
        'orderId': orderId,
        'count': all.length,
        'ids': all.map((d) => d.id).toList(),
        'withoutConductorIds': all.where((d) => d.conductorId.trim().isEmpty).map((d) => d.id).toList(),
      },
    );
    final withoutConductor = all.where((d) => d.conductorId.trim().isEmpty).toList();
    final withConductor = all.where((d) => d.conductorId.trim().isNotEmpty).toList();
    if (kDebugMode) {
      // ignore: avoid_print
      print('[SCAN_QR] orderId=$orderId entregasConEseOrderId=${all.length} ids=${all.map((e) => e.id).toList()} '
          'conConductor=${withConductor.map((e) => e.id).toList()} sinConductor=${withoutConductor.map((e) => e.id).toList()}');
    }
    if (withoutConductor.isEmpty) {
      deliveryDebugLog(
        'scan_qr_screen._reclamarEntregaManualExistente',
        'no delivery without conductor, will not reclaim',
        data: {'orderId': orderId},
      );
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SCAN_QR] NO ENTRA A RECLAMAR (todas tienen conductor)');
      }
      return false;
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print('[SCAN_QR] ENTRA A RECLAMAR EXISTENTE (hay ${withoutConductor.length} sin conductor)');
    }
    final didClaim = await DeliveryRepository.instance
        .claimCanonicalAndRemoveDuplicatesWithoutConductor(orderId, conductorId);
    if (kDebugMode) {
      // ignore: avoid_print
      print('[SCAN_QR] ${didClaim ? "RECLAMADO OK (actualiza doc, NO createDelivery)" : "claim returned false"}');
    }
    deliveryDebugLog(
      'scan_qr_screen._reclamarEntregaManualExistente',
      didClaim ? 'reclaimed, document updated' : 'claim returned false',
      data: {'orderId': orderId, 'didClaim': didClaim, 'createDeliveryExecuted': false},
    );
    return didClaim;
  }

  Future<void> _processWithOrderId(
    BuildContext context,
    Map<String, dynamic> json,
    String conductorId,
    DateTime now,
    String rawValue,
  ) async {
    // FIX: orderId puede venir como int o String desde el QR — normalizar siempre a String.
    String orderId = (json['orderId'] == null ? '' : json['orderId'].toString()).trim();
    if (orderId.isEmpty) {
      final st = (json['sourceType']?.toString() ?? '').trim();
      final sn = (json['sourceNumber']?.toString() ?? '').trim();
      if (st.isNotEmpty || sn.isNotEmpty) {
        orderId = Delivery.manualOrderId(st.isEmpty ? 'PED' : st, sn);
        deliveryDebugLog(
          'scan_qr_screen._processWithOrderId',
          'orderId was empty, built from sourceType+sourceNumber',
          data: {'orderId': orderId, 'sourceType': st, 'sourceNumber': sn},
        );
      }
    }
    final delivery = Delivery.fromQrJson(
      json,
      id: 'D-${DateTime.now().millisecondsSinceEpoch}',
      conductorId: conductorId,
      fechaEscaneo: DateTime.now(),
    );

    try {
      deliveryDebugLog(
        'scan_qr_screen._processWithOrderId',
        'orderId and parsed JSON',
        data: {
          'orderId': orderId,
          'orderIdLength': orderId.length,
          'rawValueLength': rawValue.length,
          'conductorId': conductorId,
          'sourceTypeFromJson': json['sourceType'],
          'sourceNumberFromJson': json['sourceNumber'],
        },
      );

      if (orderId.isNotEmpty) {
        final byKeyResult = await _tryReclaimByKey(orderId, conductorId);
        if (byKeyResult == _ReclaimByKeyResult.updated) {
          if (mounted) {
            _lastScannedValue = rawValue;
            _lastScannedTime = now;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(_ScanMessages.claimManualSuccess),
                backgroundColor: AppTheme.entregadoColor,
              ),
            );
          }
          if (kDebugMode) {
            // ignore: avoid_print
            print('[SCAN_QR] RETORNO SIN CREAR (reclamado por key, documento actualizado)');
          }
          deliveryDebugLog(
            'scan_qr_screen._processWithOrderId',
            'returning after reclaim by key, createDelivery NOT executed',
            data: {'orderId': orderId},
          );
          return;
        }
        if (byKeyResult == _ReclaimByKeyResult.sameDriver) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(_ScanMessages.duplicateOwn),
                duration: const Duration(seconds: 4),
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            );
          }
          return;
        }
        if (byKeyResult == _ReclaimByKeyResult.otherDriver) {
          if (mounted) {
            final addAnyway = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: const Text('Otro conductor'),
                content: const Text(_ScanMessages.duplicateOtherDriver),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Agregar igual'),
                  ),
                ],
              ),
            );
            if (!mounted) return;
            if (addAnyway != true) return;
          }
          if (kDebugMode) {
            // ignore: avoid_print
            print('[SCAN_QR] createDelivery (otro conductor, Agregar igual desde flujo key)');
          }
          deliveryDebugLog(
            'scan_qr_screen._processWithOrderId',
            'createDelivery after otherDriver from key',
            data: {'orderId': orderId},
          );
          await DeliveryRepository.instance.createDelivery(delivery);
          if (mounted) {
            _lastScannedValue = rawValue;
            _lastScannedTime = now;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(_ScanMessages.success),
                backgroundColor: AppTheme.entregadoColor,
              ),
            );
          }
          return;
        }
        // byKeyResult == fallback: continuar con query por orderId
        if (kDebugMode) {
          // ignore: avoid_print
          print('[SCAN_QR] fallback: getDeliveriesByOrderId / _reclamarEntregaManualExistente');
        }
        final didReclaim = await _reclamarEntregaManualExistente(
          orderId,
          conductorId,
          rawValue: rawValue,
          now: now,
        );
        if (didReclaim) {
          if (mounted) {
            _lastScannedValue = rawValue;
            _lastScannedTime = now;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(_ScanMessages.claimManualSuccess),
                backgroundColor: AppTheme.entregadoColor,
              ),
            );
          }
          if (kDebugMode) {
            // ignore: avoid_print
            print('[SCAN_QR] RETORNO SIN CREAR (reclamado por fallback, createDelivery NO ejecutado)');
          }
          deliveryDebugLog(
            'scan_qr_screen._processWithOrderId',
            'returning after fallback reclaim, createDelivery NOT executed',
            data: {'orderId': orderId},
          );
          return;
        }
      }

      // Fuente de verdad (fallback): colección deliveries por orderId.
      final allByOrderId = await DeliveryRepository.instance.getDeliveriesByOrderId(orderId);

      if (allByOrderId.isNotEmpty) {
        // Todas tienen conductor (si hubiera alguna sin conductor, _reclamarEntregaManualExistente ya la habría reclamado y habríamos hecho return).
        final canonical = await DeliveryRepository.instance.resolveDuplicatesForOrderId(orderId);
        if (canonical.isEmpty) {
          deliveryDebugLog(
            'scan_qr_screen._processWithOrderId',
            'canonical empty after resolve, fallback',
            data: {'orderId': orderId},
          );
          // Continuar al flujo de "no existe entrega" (más abajo).
        } else if (canonical.length == 1) {
          final d = canonical.first;
          if (d.conductorId == conductorId) {
            deliveryDebugLog(
              'scan_qr_screen._processWithOrderId',
              'same conductor, duplicate message',
              data: {'orderId': orderId},
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(_ScanMessages.duplicateOwn),
                  duration: const Duration(seconds: 4),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
              );
            }
            return;
          }
          // Otro conductor: solo crear si el usuario elige "Agregar igual".
          if (mounted) {
            final addAnyway = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: const Text('Otro conductor'),
                content: const Text(_ScanMessages.duplicateOtherDriver),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Agregar igual'),
                  ),
                ],
              ),
            );
            if (!mounted) return;
            if (addAnyway != true) return;
          }
          deliveryDebugLog(
            'scan_qr_screen._processWithOrderId',
            'createDelivery WILL BE CALLED (otro conductor, Agregar igual)',
            data: {'orderId': orderId},
          );
          await DeliveryRepository.instance.createDelivery(delivery);
          if (mounted) {
            _lastScannedValue = rawValue;
            _lastScannedTime = now;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(_ScanMessages.success),
                backgroundColor: AppTheme.entregadoColor,
              ),
            );
          }
          return;
        }
        // canonical.length > 1: varias con distintos conductores.
        final hasCurrent = canonical.any((d) => d.conductorId == conductorId);
        if (hasCurrent) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(_ScanMessages.duplicateOwn),
                duration: const Duration(seconds: 4),
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            );
          }
          return;
        }
        if (mounted) {
          final addAnyway = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Otro conductor'),
              content: const Text(_ScanMessages.duplicateOtherDriver),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Agregar igual'),
                ),
              ],
            ),
          );
          if (!mounted) return;
          if (addAnyway != true) return;
        }
        deliveryDebugLog(
          'scan_qr_screen._processWithOrderId',
          'createDelivery WILL BE CALLED (múltiples conductores, Agregar igual)',
          data: {'orderId': orderId},
        );
        await DeliveryRepository.instance.createDelivery(delivery);
        if (mounted) {
          _lastScannedValue = rawValue;
          _lastScannedTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(_ScanMessages.success),
              backgroundColor: AppTheme.entregadoColor,
            ),
          );
        }
        return;
      }

      // No existe ninguna entrega con este orderId: flujo normal (pedido web nuevo o key legacy).
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SCAN_QR] ENTRA A CREAR NUEVA (no hay entregas con orderId=$orderId)');
      }
      deliveryDebugLog(
        'scan_qr_screen._processWithOrderId',
        'no deliveries for orderId, may create',
        data: {'orderId': orderId},
      );
      final existing = await DeliveryRepository.instance.getDeliveriesByDriver(conductorId);
      final duplicateOwn = existing.any((d) => d.orderId == orderId);
      if (duplicateOwn) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(_ScanMessages.duplicateOwn),
              duration: const Duration(seconds: 4),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
        return;
      }

      final keyConductorId = await DeliveryRepository.instance.getConductorIdByOrderId(orderId);
      if (keyConductorId == conductorId) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(_ScanMessages.duplicateOwn),
              duration: const Duration(seconds: 4),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
        return;
      }
      if (keyConductorId != null && keyConductorId.isNotEmpty && keyConductorId != conductorId && mounted) {
        final addAnyway = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Otro conductor'),
            content: const Text(_ScanMessages.duplicateOtherDriver),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Agregar igual'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (addAnyway != true) return;
      }

      deliveryDebugLog(
        'scan_qr_screen._processWithOrderId',
        'createDelivery WILL BE CALLED (no existing for orderId)',
        data: {'orderId': orderId},
      );
      await DeliveryRepository.instance.createDelivery(delivery);
      if (mounted) {
        _lastScannedValue = rawValue;
        _lastScannedTime = now;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(_ScanMessages.success),
            backgroundColor: AppTheme.entregadoColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final theme = Theme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(_ScanMessages.saveError),
            duration: const Duration(seconds: 4),
            backgroundColor: theme.colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _processLegacyQr(
    BuildContext context,
    Map<String, dynamic> json,
    String conductorId,
    DateTime now,
    String rawValue,
  ) async {
    final st = (json['sourceType']?.toString() ?? '').trim();
    final sn = (json['sourceNumber']?.toString() ?? '').trim();
    if (st.isNotEmpty || sn.isNotEmpty) {
      final orderId = Delivery.manualOrderId(st.isEmpty ? 'PED' : st, sn);
      deliveryDebugLog(
        'scan_qr_screen._processLegacyQr',
        'QR sin orderId pero tiene sourceType/sourceNumber, intentando reclamar',
        data: {'orderId': orderId, 'sourceType': st, 'sourceNumber': sn},
      );
      final didReclaim = await _reclamarEntregaManualExistente(
        orderId,
        conductorId,
        rawValue: rawValue,
        now: now,
      );
      if (didReclaim) {
        if (mounted) {
          _lastScannedValue = rawValue;
          _lastScannedTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(_ScanMessages.claimManualSuccess),
              backgroundColor: AppTheme.entregadoColor,
            ),
          );
        }
        if (kDebugMode) {
          // ignore: avoid_print
          print('[SCAN_QR] RETORNO SIN CREAR (reclamado desde legacy por sourceType/sourceNumber)');
        }
        deliveryDebugLog(
          'scan_qr_screen._processLegacyQr',
          'reclamado por orderId construido, createDelivery NO ejecutado',
          data: {'orderId': orderId},
        );
        return;
      }
    }

    final delivery = Delivery.fromQrJson(
      json,
      id: 'D-${DateTime.now().millisecondsSinceEpoch}',
      conductorId: conductorId,
      fechaEscaneo: DateTime.now(),
    );

    final addAnyway = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('QR sin identificador único'),
        content: const Text(_ScanMessages.qrLegacyWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Agregar igual'),
          ),
        ],
      ),
    );
    if (!mounted || addAnyway != true) return;

    final nDni = _normalize(delivery.dni);
    final nDir = _normalize(delivery.direccion);
    final existing = await DeliveryRepository.instance.getDeliveriesByDriver(conductorId);
    final duplicateOwn = existing.any((d) =>
        _normalize(d.dni) == nDni && _normalize(d.direccion) == nDir);
    if (duplicateOwn) {
      if (mounted) {
        final theme = Theme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(_ScanMessages.duplicateOwn),
            duration: const Duration(seconds: 4),
            backgroundColor: theme.colorScheme.primary,
          ),
        );
      }
      return;
    }

    final keyConductorId = await DeliveryRepository.instance.getConductorIdByLegacyKey(nDni, nDir);
    if (keyConductorId != null && keyConductorId != conductorId && mounted) {
      final addAnyway2 = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Pedido ya cargado'),
          content: const Text(_ScanMessages.duplicateOtherDriver),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Agregar igual'),
            ),
          ],
        ),
      );
      if (!mounted || addAnyway2 != true) return;
    }

    try {
      await DeliveryRepository.instance.createDelivery(delivery);
      if (mounted) {
        _lastScannedValue = rawValue;
        _lastScannedTime = now;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(_ScanMessages.success),
            backgroundColor: AppTheme.entregadoColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final theme = Theme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(_ScanMessages.saveError),
            duration: const Duration(seconds: 4),
            backgroundColor: theme.colorScheme.error,
          ),
        );
      }
    }
  }

  /// Muestra un diálogo para completar/corregir datos extraídos del QR.
  /// Devuelve null si el usuario cancela, o el JSON editado si confirma.
  Future<Map<String, dynamic>?> _showEditQrDataDialog(
    Map<String, dynamic> initialData,
    String rawValue,
    String parseMethod,
  ) async {
    final nombreCtrl = TextEditingController(text: (initialData['nombre'] ?? '').toString());
    final dniCtrl = TextEditingController(text: (initialData['dni'] ?? '').toString());
    final direccionCtrl = TextEditingController(text: (initialData['direccion'] ?? '').toString());
    final telefonoCtrl = TextEditingController(text: (initialData['telefono'] ?? '').toString());
    final observacionesCtrl = TextEditingController(text: (initialData['observaciones'] ?? '').toString());
    final orderIdCtrl = TextEditingController(text: (initialData['orderId'] ?? '').toString());

    String parseMethodLabel;
    switch (parseMethod) {
      case 'json':
        parseMethodLabel = 'JSON (campos incompletos)';
        break;
      case 'url':
        parseMethodLabel = 'URL con parámetros';
        break;
      case 'keyvalue':
        parseMethodLabel = 'Pares clave=valor';
        break;
      case 'delimited':
        parseMethodLabel = 'Valores separados';
        break;
      default:
        parseMethodLabel = 'Texto libre';
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Completar datos del QR'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Formato detectado: $parseMethodLabel',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  'Faltan datos obligatorios. Completá los campos marcados con *',
                  style: TextStyle(fontSize: 13, color: AppTheme.pendienteColor),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre *',
                    hintText: 'Nombre del cliente',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dniCtrl,
                  decoration: const InputDecoration(
                    labelText: 'DNI / CUIT *',
                    hintText: 'Documento de identidad',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: direccionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dirección *',
                    hintText: 'Dirección de entrega',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: telefonoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    hintText: 'Teléfono de contacto',
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: orderIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ID de Pedido',
                    hintText: 'Identificador único',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: observacionesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones',
                    hintText: 'Notas adicionales',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final result = Map<String, dynamic>.from(initialData);
                result['nombre'] = nombreCtrl.text.trim();
                result['dni'] = dniCtrl.text.trim();
                result['direccion'] = direccionCtrl.text.trim();
                result['telefono'] = telefonoCtrl.text.trim();
                result['observaciones'] = observacionesCtrl.text.trim();
                if (orderIdCtrl.text.trim().isNotEmpty) {
                  result['orderId'] = orderIdCtrl.text.trim();
                }
                Navigator.of(ctx).pop(result);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  void _onDetectError(Object error, StackTrace stackTrace) {
    if (mounted) {
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(_ScanMessages.cameraError),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear QR'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () => context.push(AppRoutes.deliveryList),
            tooltip: 'Ver entregas cargadas',
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onBarcodeDetected,
            onDetectError: _onDetectError,
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Verificando...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
