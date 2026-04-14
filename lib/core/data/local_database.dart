import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:sqflite/sqflite.dart';

// path_provider y path no funcionan en web
// Solo se importan para mobile/desktop
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/delivery/domain/delivery.dart';
import '../../features/delivery/domain/delivery_state.dart';

/// Base de datos SQLite local para entregas.
/// Permite operar sin conexión y sincronizar después con Firestore.
class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase _instance = LocalDatabase._();
  static LocalDatabase get instance => _instance;

  static const String _dbName = 'acuaflex_deliveries.db';
  static const int _dbVersion = 4;
  static const String _tableDeliveries = 'deliveries';
  static const String _tablePendingSync = 'pending_sync';

  Database? _db;

  /// Inicializa la base de datos. Llamar una vez al inicio de la app.
  /// En web, esta es un no-op ya que sqflite no funciona en web.
  Future<void> init() async {
    if (_db != null) return;

    // En web, sqflite no está disponible — usar Firestore directamente
    if (kIsWeb) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[LOCAL_DB] Running on web — offline sync disabled (use Firestore directly)');
      }
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = p.join(dir.path, _dbName);
      _db = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      if (kDebugMode) {
        // ignore: avoid_print
        print('[LOCAL_DB] Database initialized at $path');
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[LOCAL_DB] Failed to initialize: $e');
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableDeliveries (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL DEFAULT '',
        telefono TEXT NOT NULL DEFAULT '',
        dni TEXT NOT NULL DEFAULT '',
        direccion TEXT NOT NULL DEFAULT '',
        observaciones TEXT NOT NULL DEFAULT '',
        estado TEXT NOT NULL DEFAULT 'pendiente',
        conductorId TEXT NOT NULL DEFAULT '',
        fechaEscaneo TEXT NOT NULL,
        fechaEntrega TEXT,
        nombreRecibe TEXT,
        dniRecibe TEXT,
        relacionRecibe TEXT,
        orderId TEXT,
        direccionCompleta TEXT,
        codigoPostal TEXT,
        localidad TEXT,
        provincia TEXT,
        sourceType TEXT NOT NULL DEFAULT 'PED',
        sourceNumber TEXT,
        createdManually INTEGER NOT NULL DEFAULT 0,
        firmaBase64 TEXT,
        fechaFirma TEXT,
        motivoNoEntrega TEXT,
        fechaNoEntrega TEXT,
        evidenciaNoEntrega TEXT,
        evidenciaNoEntregaPaths TEXT,
        cierreLatitud REAL,
        cierreLongitud REAL,
        adminAvisoRetiroCambioLeido INTEGER,
        lastModified TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $_tablePendingSync (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deliveryId TEXT NOT NULL,
        operation TEXT NOT NULL,
        data TEXT,
        createdAt TEXT NOT NULL,
        retryCount INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_deliveries_conductor ON $_tableDeliveries(conductorId)',
    );
    await db.execute(
      'CREATE INDEX idx_deliveries_orderId ON $_tableDeliveries(orderId)',
    );
    await db.execute(
      'CREATE INDEX idx_pending_sync_deliveryId ON $_tablePendingSync(deliveryId)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Recrear tablas si upgrade desde v1
      await db.execute('DROP TABLE IF EXISTS $_tablePendingSync');
      await db.execute('DROP TABLE IF EXISTS $_tableDeliveries');
      await _onCreate(db, newVersion);
      return;
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE $_tableDeliveries ADD COLUMN cierreLatitud REAL',
      );
      await db.execute(
        'ALTER TABLE $_tableDeliveries ADD COLUMN cierreLongitud REAL',
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE $_tableDeliveries ADD COLUMN adminAvisoRetiroCambioLeido INTEGER',
      );
    }
  }

  Database get _database {
    if (_db == null) {
      throw StateError(
        'LocalDatabase not initialized. '
        'This should not happen on mobile/desktop. '
        'On web, database is not available (use Firestore instead).',
      );
    }
    return _db!;
  }

  /// Verifica si la base de datos está disponible (no en web).
  bool get isAvailable => _db != null;

  // ─────────────────── Deliveries CRUD ───────────────────

  /// Guarda o actualiza una entrega localmente.
  Future<void> upsertDelivery(Delivery delivery) async {
    if (!isAvailable) {
      throw UnsupportedError('LocalDatabase not available on this platform (web?)');
    }
    final map = _deliveryToRow(delivery);
    await _database.insert(
      _tableDeliveries,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Guarda múltiples entregas (batch desde Firestore sync).
  Future<void> upsertDeliveries(List<Delivery> deliveries) async {
    if (!isAvailable) {
      throw UnsupportedError('LocalDatabase not available on this platform (web?)');
    }
    final batch = _database.batch();
    for (final d in deliveries) {
      batch.insert(
        _tableDeliveries,
        _deliveryToRow(d),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Obtiene una entrega por id.
  Future<Delivery?> getDeliveryById(String id) async {
    final rows = await _database.query(
      _tableDeliveries,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToDelivery(rows.first);
  }

  /// Obtiene entregas por conductor.
  Future<List<Delivery>> getDeliveriesByDriver(String conductorId) async {
    final rows = await _database.query(
      _tableDeliveries,
      where: 'conductorId = ?',
      whereArgs: [conductorId],
      orderBy: 'fechaEscaneo DESC',
    );
    return rows.map(_rowToDelivery).toList();
  }

  /// Obtiene entregas por orderId.
  Future<List<Delivery>> getDeliveriesByOrderId(String orderId) async {
    final rows = await _database.query(
      _tableDeliveries,
      where: 'orderId = ?',
      whereArgs: [orderId],
    );
    return rows.map(_rowToDelivery).toList();
  }

  /// Obtiene todas las entregas locales.
  Future<List<Delivery>> getAllDeliveries() async {
    final rows = await _database.query(
      _tableDeliveries,
      orderBy: 'fechaEscaneo DESC',
    );
    return rows.map(_rowToDelivery).toList();
  }

  /// Elimina una entrega local.
  Future<void> deleteDelivery(String id) async {
    await _database.delete(
      _tableDeliveries,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ─────────────────── Pending Sync Queue ───────────────────

  /// Agrega una operación pendiente de sync.
  /// [operation] puede ser: 'create', 'update', 'delete'.
  /// [data] es el JSON serializado de la entrega (null para delete).
  Future<void> addPendingSync({
    required String deliveryId,
    required String operation,
    Map<String, dynamic>? data,
  }) async {
    await _database.insert(_tablePendingSync, {
      'deliveryId': deliveryId,
      'operation': operation,
      'data': data != null ? jsonEncode(data) : null,
      'createdAt': DateTime.now().toIso8601String(),
      'retryCount': 0,
    });
    if (kDebugMode) {
      // ignore: avoid_print
      print('[LOCAL_DB] Pending sync added: $operation for $deliveryId');
    }
  }

  /// Obtiene todas las operaciones pendientes de sync, ordenadas por antigüedad.
  Future<List<Map<String, dynamic>>> getPendingSyncs() async {
    return _database.query(
      _tablePendingSync,
      orderBy: 'createdAt ASC',
    );
  }

  /// Elimina una operación pendiente por id (después de sync exitoso).
  Future<void> removePendingSync(int id) async {
    await _database.delete(
      _tablePendingSync,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Incrementa el contador de reintentos de una operación pendiente.
  Future<void> incrementRetryCount(int id) async {
    await _database.rawUpdate(
      'UPDATE $_tablePendingSync SET retryCount = retryCount + 1 WHERE id = ?',
      [id],
    );
  }

  /// Elimina operaciones con demasiados reintentos (> maxRetries).
  Future<int> cleanupFailedSyncs({int maxRetries = 10}) async {
    return _database.delete(
      _tablePendingSync,
      where: 'retryCount > ?',
      whereArgs: [maxRetries],
    );
  }

  /// Cantidad de operaciones pendientes.
  Future<int> pendingSyncCount() async {
    if (!isAvailable) {
      return 0; // En web o cuando no está disponible, asumir 0 pendientes
    }
    try {
      final result = await _database.rawQuery(
        'SELECT COUNT(*) as c FROM $_tablePendingSync',
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  // ─────────────────── Conversión ───────────────────

  Map<String, dynamic> _deliveryToRow(Delivery d) {
    return {
      'id': d.id,
      'nombre': d.nombre,
      'telefono': d.telefono,
      'dni': d.dni,
      'direccion': d.direccion,
      'observaciones': d.observaciones,
      'estado': d.estado.name,
      'conductorId': d.conductorId,
      'fechaEscaneo': d.fechaEscaneo.toIso8601String(),
      'fechaEntrega': d.fechaEntrega?.toIso8601String(),
      'nombreRecibe': d.nombreRecibe,
      'dniRecibe': d.dniRecibe,
      'relacionRecibe': d.relacionRecibe,
      'orderId': d.orderId,
      'direccionCompleta': d.direccionCompleta,
      'codigoPostal': d.codigoPostal,
      'localidad': d.localidad,
      'provincia': d.provincia,
      'sourceType': d.sourceType,
      'sourceNumber': d.sourceNumber,
      'createdManually': d.createdManually ? 1 : 0,
      'firmaBase64': d.firmaBase64,
      'fechaFirma': d.fechaFirma?.toIso8601String(),
      'motivoNoEntrega': d.motivoNoEntrega,
      'fechaNoEntrega': d.fechaNoEntrega?.toIso8601String(),
      'evidenciaNoEntrega':
          d.evidenciaNoEntrega != null ? jsonEncode(d.evidenciaNoEntrega) : null,
      'evidenciaNoEntregaPaths': d.evidenciaNoEntregaPaths != null
          ? jsonEncode(d.evidenciaNoEntregaPaths)
          : null,
      'cierreLatitud': d.cierreLatitud,
      'cierreLongitud': d.cierreLongitud,
      'adminAvisoRetiroCambioLeido': d.adminAvisoRetiroCambioLeido == null
          ? null
          : (d.adminAvisoRetiroCambioLeido! ? 1 : 0),
      'lastModified': DateTime.now().toIso8601String(),
    };
  }

  Delivery _rowToDelivery(Map<String, dynamic> row) {
    return Delivery(
      id: row['id'] as String,
      nombre: row['nombre'] as String? ?? '',
      telefono: row['telefono'] as String? ?? '',
      dni: row['dni'] as String? ?? '',
      direccion: row['direccion'] as String? ?? '',
      observaciones: row['observaciones'] as String? ?? '',
      estado: _parseEstado(row['estado'] as String?),
      conductorId: row['conductorId'] as String? ?? '',
      fechaEscaneo: DateTime.tryParse(row['fechaEscaneo'] as String? ?? '') ?? DateTime.now(),
      fechaEntrega: _parseNullableDate(row['fechaEntrega']),
      nombreRecibe: row['nombreRecibe'] as String?,
      dniRecibe: row['dniRecibe'] as String?,
      relacionRecibe: row['relacionRecibe'] as String?,
      orderId: row['orderId'] as String?,
      direccionCompleta: row['direccionCompleta'] as String?,
      codigoPostal: row['codigoPostal'] as String?,
      localidad: row['localidad'] as String?,
      provincia: row['provincia'] as String?,
      sourceType: (row['sourceType'] as String?)?.isNotEmpty == true
          ? row['sourceType'] as String
          : 'PED',
      sourceNumber: row['sourceNumber'] as String?,
      createdManually: (row['createdManually'] as int?) == 1,
      firmaBase64: row['firmaBase64'] as String?,
      fechaFirma: _parseNullableDate(row['fechaFirma']),
      motivoNoEntrega: row['motivoNoEntrega'] as String?,
      fechaNoEntrega: _parseNullableDate(row['fechaNoEntrega']),
      evidenciaNoEntrega: _parseStringList(row['evidenciaNoEntrega']),
      evidenciaNoEntregaPaths: _parseStringList(row['evidenciaNoEntregaPaths']),
      cierreLatitud: _parseDouble(row['cierreLatitud']),
      cierreLongitud: _parseDouble(row['cierreLongitud']),
      adminAvisoRetiroCambioLeido: _parseTriBool(row['adminAvisoRetiroCambioLeido']),
    );
  }

  static bool? _parseTriBool(dynamic v) {
    if (v == null) return null;
    if (v is int) {
      if (v == 1) return true;
      if (v == 0) return false;
    }
    return null;
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static DeliveryState _parseEstado(String? s) {
    if (s == 'entregado') return DeliveryState.entregado;
    if (s == 'noEntregado') return DeliveryState.noEntregado;
    return DeliveryState.pendiente;
  }

  static DateTime? _parseNullableDate(dynamic v) {
    if (v == null) return null;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  static List<String>? _parseStringList(dynamic v) {
    if (v == null) return null;
    if (v is String && v.isNotEmpty) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is List) {
          return decoded.cast<String>();
        }
      } catch (_) {}
    }
    return null;
  }
}
