import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Log temporal para depurar flujo de entregas manuales / orderId.
/// Escribe NDJSON a debug-269885.log vía servidor y además print a consola.
const String _sessionId = '269885';
const String _ingestUrl =
    'http://127.0.0.1:7666/ingest/fc7c4238-7a2e-479f-bb95-e493d88961e8';

void _log(String location, String message, Map<String, dynamic> data) {
  final payload = {
    'sessionId': _sessionId,
    'id': 'log_${DateTime.now().millisecondsSinceEpoch}',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'location': location,
    'message': message,
    'data': data,
  };
  if (kDebugMode) {
    // ignore: avoid_print
    print('[DELIVERY_DEBUG] $location | $message | ${jsonEncode(data)}');
  }
  // No usar .catchError(() {}) sobre Future<Response>: el handler debe devolver Response.
  Future.microtask(() async {
    try {
      await http.post(
        Uri.parse(_ingestUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Debug-Session-Id': _sessionId,
        },
        body: jsonEncode(payload),
      );
    } catch (_) {
      // Servidor de ingest opcional (127.0.0.1:7666); ignorar si no está levantado.
    }
  });
}

/// Llamar desde scan/repo para registrar pasos del flujo orderId.
void deliveryDebugLog(
  String location,
  String message, {
  required Map<String, dynamic> data,
}) {
  _log(location, message, data);
}
