import 'delivery_state.dart';

/// Tipos de origen de documento (pedido web vs documentos comerciales manuales).
abstract class DeliverySourceType {
  static const String ped = 'PED'; // Pedido web (QR)
  static const String fc = 'FC';   // Factura
  static const String ov = 'OV';   // Orden de venta
  static const String cot = 'COT'; // Cotización

  static const List<String> manualTypes = [fc, ov, cot];
  static const List<String> allManualOptions = [ped, fc, ov, cot];

  static String label(String type) {
    switch (type) {
      case ped: return 'Pedido web';
      case fc: return 'Factura (FC)';
      case ov: return 'Orden de venta (OV)';
      case cot: return 'Cotización (COT)';
      default: return type;
    }
  }
}

/// Modelo de una entrega. Identificación principal por [orderId] cuando existe.
/// Soporta pedidos por QR (PED), entregas manuales (FC, OV, COT) y documentos antiguos sin orderId.
class Delivery {
  const Delivery({
    required this.id,
    required this.nombre,
    required this.telefono,
    required this.dni,
    required this.direccion,
    required this.observaciones,
    required this.estado,
    required this.conductorId,
    required this.fechaEscaneo,
    this.fechaEntrega,
    this.nombreRecibe,
    this.dniRecibe,
    this.relacionRecibe,
    this.orderId,
    this.direccionCompleta,
    this.codigoPostal,
    this.localidad,
    this.provincia,
    this.sourceType = DeliverySourceType.ped,
    this.sourceNumber,
    this.createdManually = false,
    this.firmaBase64,
    this.fechaFirma,
    this.motivoNoEntrega,
    this.fechaNoEntrega,
    this.evidenciaNoEntrega,
    this.evidenciaNoEntregaPaths,
  });

  final String id;
  final String nombre;
  final String telefono;
  final String dni;
  final String direccion;
  final String observaciones;
  final DeliveryState estado;
  /// Conductor asignado. Vacío '' = sin asignar (solo admin ve la entrega hasta que se asigne).
  final String conductorId;
  final DateTime fechaEscaneo;
  final DateTime? fechaEntrega;
  final String? nombreRecibe;
  final String? dniRecibe;
  final String? relacionRecibe;

  /// Identificador único: para PED viene del QR; para manual = MAN-{sourceType}-{sourceNumber}.
  final String? orderId;
  final String? direccionCompleta;
  final String? codigoPostal;
  final String? localidad;
  final String? provincia;

  /// Tipo de documento: PED (pedido web), FC, OV, COT.
  final String sourceType;
  /// Número de documento (FC/OV/COT). Null para PED.
  final String? sourceNumber;
  /// True si se creó desde el formulario manual de admin.
  final bool createdManually;

  /// Firma del receptor en base64 (PNG). null si no hay firma cargada.
  final String? firmaBase64;
  /// Fecha/hora en la que se guardó la firma.
  final DateTime? fechaFirma;

  /// Motivo de "No entregado" (obligatorio si estado = noEntregado).
  final String? motivoNoEntrega;
  /// Fecha/hora en la que se marcó "No entregado".
  final DateTime? fechaNoEntrega;
  /// URLs de hasta 2 fotos de evidencia al marcar no entregado (Firebase Storage).
  final List<String>? evidenciaNoEntrega;
  /// Paths de Storage (backup) para resolver URLs si faltan.
  /// Ej: deliveries/{deliveryId}/no_entrega_0.jpg
  final List<String>? evidenciaNoEntregaPaths;

  bool get hasOrderId => orderId != null && orderId!.trim().isNotEmpty;

  /// True si la entrega no tiene conductor asignado todavía.
  bool get hasNoConductor => conductorId.trim().isEmpty;

  bool get hasFirma => firmaBase64 != null && firmaBase64!.trim().isNotEmpty;
  bool get isNoEntregado => estado == DeliveryState.noEntregado;

  /// True si es pedido web (QR con orderId).
  bool get isWebPedido =>
      sourceType == DeliverySourceType.ped && hasOrderId && !createdManually;

  /// True si es carga manual (FC/OV/COT o PED manual).
  bool get isManual => createdManually;

  /// Etiqueta corta para UI: "FC 12345", "Pedido web", etc.
  String get sourceLabel {
    if (createdManually && sourceNumber != null && sourceNumber!.trim().isNotEmpty) {
      return '${DeliverySourceType.label(sourceType)} ${sourceNumber!.trim()}';
    }
    if (hasOrderId && !createdManually) return 'Pedido web';
    return DeliverySourceType.label(sourceType);
  }

  static String _s(dynamic v) => v == null ? '' : v.toString().trim();
  static String? _sOrNull(dynamic v) {
    if (v == null) return null;
    final s = (v is String ? v : v.toString()).trim();
    return s.isEmpty ? null : s;
  }

  static List<String>? _readStringList(dynamic v) {
    if (v == null) return null;
    if (v is! List) return null;
    final list = v
        .map((e) => e == null ? '' : e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return list.isEmpty ? null : list;
  }

  /// orderId para entregas manuales (duplicados por tipo + número).
  static String manualOrderId(String sourceType, String sourceNumber) {
    final t = sourceType.trim().toUpperCase();
    final n = sourceNumber.trim();
    return 'MAN-$t-$n';
  }

  /// Crea una entrega desde el JSON del QR.
  /// Lee orderId, sourceType, sourceNumber y createdManually si vienen en el QR (entregas manuales).
  factory Delivery.fromQrJson(
    Map<String, dynamic> json, {
    required String id,
    required String conductorId,
    required DateTime fechaEscaneo,
  }) {
    final dir = _s(json['direccion']);
    final orderIdVal = _sOrNull(json['orderId']);
    final sourceTypeVal = _s(json['sourceType']).isEmpty ? DeliverySourceType.ped : _s(json['sourceType']);
    final createdManuallyVal = json['createdManually'] == true;
    return Delivery(
      id: id,
      nombre: _s(json['nombre']),
      telefono: _s(json['telefono']),
      dni: _s(json['dni']),
      direccion: dir,
      observaciones: _s(json['observaciones']),
      estado: DeliveryState.pendiente,
      conductorId: conductorId,
      fechaEscaneo: fechaEscaneo,
      orderId: orderIdVal,
      direccionCompleta: _sOrNull(json['direccionCompleta']),
      codigoPostal: _sOrNull(json['codigoPostal']),
      localidad: _sOrNull(json['localidad']),
      provincia: _sOrNull(json['provincia']),
      sourceType: sourceTypeVal,
      sourceNumber: _sOrNull(json['sourceNumber']),
      createdManually: createdManuallyVal,
    );
  }

  /// JSON para generar QR (mismo formato que espera el escáner).
  /// Para entregas manuales debe incluir orderId, sourceType, sourceNumber para que el escaneo reconozca la entrega existente.
  Map<String, dynamic> toQrJson() {
    final map = <String, dynamic>{
      'nombre': nombre,
      'telefono': telefono,
      'dni': dni,
      'direccion': direccion,
      'observaciones': observaciones,
    };
    if (orderId != null && orderId!.trim().isNotEmpty) {
      map['orderId'] = orderId!.trim();
    }
    if (codigoPostal != null && codigoPostal!.trim().isNotEmpty) {
      map['codigoPostal'] = codigoPostal!.trim();
    }
    if (localidad != null && localidad!.trim().isNotEmpty) {
      map['localidad'] = localidad!.trim();
    }
    if (provincia != null && provincia!.trim().isNotEmpty) {
      map['provincia'] = provincia!.trim();
    }
    if (direccionCompleta != null && direccionCompleta!.trim().isNotEmpty) {
      map['direccionCompleta'] = direccionCompleta!.trim();
    }
    if (sourceType.trim().isNotEmpty) {
      map['sourceType'] = sourceType;
    }
    if (sourceNumber != null && sourceNumber!.trim().isNotEmpty) {
      map['sourceNumber'] = sourceNumber!.trim();
    }
    if (createdManually) {
      map['createdManually'] = true;
    }
    return map;
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'nombre': nombre,
      'telefono': telefono,
      'dni': dni,
      'direccion': direccion,
      'observaciones': observaciones,
      'estado': estado.name,
      'conductorId': conductorId,
      'fechaEscaneo': fechaEscaneo,
      'fechaEntrega': fechaEntrega,
      'nombreRecibe': nombreRecibe,
      'dniRecibe': dniRecibe,
      'relacionRecibe': relacionRecibe,
      'firmaBase64': firmaBase64,
      'fechaFirma': fechaFirma,
      'motivoNoEntrega': motivoNoEntrega,
      'fechaNoEntrega': fechaNoEntrega,
      'evidenciaNoEntrega': evidenciaNoEntrega,
      'evidenciaNoEntregaPaths': evidenciaNoEntregaPaths,
      'sourceType': sourceType,
      'createdManually': createdManually,
    };
    if (orderId != null) map['orderId'] = orderId;
    if (direccionCompleta != null) map['direccionCompleta'] = direccionCompleta;
    if (codigoPostal != null) map['codigoPostal'] = codigoPostal;
    if (localidad != null) map['localidad'] = localidad;
    if (provincia != null) map['provincia'] = provincia;
    if (sourceNumber != null) map['sourceNumber'] = sourceNumber;
    return map;
  }

  factory Delivery.fromMap(Map<String, dynamic> map) {
    return Delivery(
      id: _s(map['id']),
      nombre: _s(map['nombre']),
      telefono: _s(map['telefono']),
      dni: _s(map['dni']),
      direccion: _s(map['direccion']),
      observaciones: _s(map['observaciones']),
      estado: _readEstado(map['estado']),
      conductorId: _s(map['conductorId']),
      fechaEscaneo: (map['fechaEscaneo'] as DateTime?) ?? DateTime.now(),
      fechaEntrega: map['fechaEntrega'] as DateTime?,
      nombreRecibe: _sOrNull(map['nombreRecibe']),
      dniRecibe: _sOrNull(map['dniRecibe']),
      relacionRecibe: _sOrNull(map['relacionRecibe']),
      firmaBase64: _sOrNull(map['firmaBase64']),
      fechaFirma: map['fechaFirma'] as DateTime?,
      motivoNoEntrega: _sOrNull(map['motivoNoEntrega']),
      fechaNoEntrega: map['fechaNoEntrega'] as DateTime?,
      evidenciaNoEntrega: _readStringList(map['evidenciaNoEntrega']),
      evidenciaNoEntregaPaths: _readStringList(map['evidenciaNoEntregaPaths']),
      orderId: _sOrNull(map['orderId']),
      direccionCompleta: _sOrNull(map['direccionCompleta']),
      codigoPostal: _sOrNull(map['codigoPostal']),
      localidad: _sOrNull(map['localidad']),
      provincia: _sOrNull(map['provincia']),
      sourceType: _s(map['sourceType']).isEmpty ? DeliverySourceType.ped : _s(map['sourceType']),
      sourceNumber: _sOrNull(map['sourceNumber']),
      createdManually: map['createdManually'] == true,
    );
  }

  static DeliveryState _readEstado(dynamic v) {
    if (v == null) return DeliveryState.pendiente;
    final s = v.toString();
    if (s == 'entregado') return DeliveryState.entregado;
    if (s == 'noEntregado') return DeliveryState.noEntregado;
    return DeliveryState.pendiente;
  }

  Delivery copyWith({
    DeliveryState? estado,
    DateTime? fechaEntrega,
    String? nombreRecibe,
    String? dniRecibe,
    String? relacionRecibe,
    String? firmaBase64,
    DateTime? fechaFirma,
    String? motivoNoEntrega,
    DateTime? fechaNoEntrega,
    List<String>? evidenciaNoEntrega,
    List<String>? evidenciaNoEntregaPaths,
    String? conductorId,
    String? nombre,
    String? telefono,
    String? dni,
    String? direccion,
    String? observaciones,
    String? codigoPostal,
    String? localidad,
    String? provincia,
    String? direccionCompleta,
  }) {
    return Delivery(
      id: id,
      nombre: nombre ?? this.nombre,
      telefono: telefono ?? this.telefono,
      dni: dni ?? this.dni,
      direccion: direccion ?? this.direccion,
      observaciones: observaciones ?? this.observaciones,
      estado: estado ?? this.estado,
      conductorId: conductorId ?? this.conductorId,
      fechaEscaneo: fechaEscaneo,
      fechaEntrega: fechaEntrega ?? this.fechaEntrega,
      nombreRecibe: nombreRecibe ?? this.nombreRecibe,
      dniRecibe: dniRecibe ?? this.dniRecibe,
      relacionRecibe: relacionRecibe ?? this.relacionRecibe,
      firmaBase64: firmaBase64 ?? this.firmaBase64,
      fechaFirma: fechaFirma ?? this.fechaFirma,
      motivoNoEntrega: motivoNoEntrega ?? this.motivoNoEntrega,
      fechaNoEntrega: fechaNoEntrega ?? this.fechaNoEntrega,
      evidenciaNoEntrega: evidenciaNoEntrega ?? this.evidenciaNoEntrega,
      evidenciaNoEntregaPaths:
          evidenciaNoEntregaPaths ?? this.evidenciaNoEntregaPaths,
      orderId: orderId,
      direccionCompleta: direccionCompleta ?? this.direccionCompleta,
      codigoPostal: codigoPostal ?? this.codigoPostal,
      localidad: localidad ?? this.localidad,
      provincia: provincia ?? this.provincia,
      sourceType: sourceType,
      sourceNumber: sourceNumber,
      createdManually: createdManually,
    );
  }
}
