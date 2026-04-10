import 'dart:convert';

/// Resultado del parseo de un QR con cualquier formato.
/// [fields] contiene los datos extraídos (nombre, dni, direccion, etc.).
/// [rawValue] es el valor original del QR sin procesar.
/// [parseMethod] indica cómo se parseó ('json', 'url', 'keyvalue', 'text').
/// [isComplete] indica si tiene los 3 campos requeridos (nombre, dni, direccion).
class QrParseResult {
  final Map<String, dynamic> fields;
  final String rawValue;
  final String parseMethod;

  QrParseResult({
    required this.fields,
    required this.rawValue,
    required this.parseMethod,
  });

  bool get isComplete {
    return _notEmpty(fields['nombre']) &&
        _notEmpty(fields['dni']) &&
        _notEmpty(fields['direccion']);
  }

  /// True si al menos un campo tiene valor (parseo parcial).
  bool get hasAnyData {
    return fields.values.any((v) =>
        v != null && v.toString().trim().isNotEmpty);
  }

  static bool _notEmpty(dynamic v) {
    if (v == null) return false;
    return v.toString().trim().isNotEmpty;
  }
}

/// Parser flexible que intenta múltiples estrategias para extraer datos de un QR.
///
/// Orden de intentos:
/// 1. JSON directo (formato actual de la app)
/// 2. URL con query params (?nombre=X&dni=Y&...)
/// 3. Pares clave=valor separados por & o ;
/// 4. Valores separados por | o , (posicional)
/// 5. Texto libre → va a observaciones para edición manual
class QrParser {
  QrParser._();

  /// Mapeo de alias comunes a nombres de campo de la app.
  /// Permite reconocer QRs de otros sistemas que usen nombres diferentes.
  static const Map<String, String> _fieldAliases = {
    // nombre
    'nombre': 'nombre',
    'name': 'nombre',
    'cliente': 'nombre',
    'customer': 'nombre',
    'razon_social': 'nombre',
    'razonSocial': 'nombre',
    'razonsocial': 'nombre',
    'client_name': 'nombre',
    'clientName': 'nombre',
    'nombrecliente': 'nombre',
    'nombre_cliente': 'nombre',
    // telefono
    'telefono': 'telefono',
    'tel': 'telefono',
    'phone': 'telefono',
    'celular': 'telefono',
    'mobile': 'telefono',
    'whatsapp': 'telefono',
    // dni
    'dni': 'dni',
    'cuit': 'dni',
    'cuil': 'dni',
    'documento': 'dni',
    'doc': 'dni',
    'rut': 'dni',
    'nit': 'dni',
    'id': 'dni',
    'identification': 'dni',
    'tax_id': 'dni',
    'taxId': 'dni',
    // direccion
    'direccion': 'direccion',
    'address': 'direccion',
    'domicilio': 'direccion',
    'dir': 'direccion',
    'calle': 'direccion',
    'street': 'direccion',
    'delivery_address': 'direccion',
    'deliveryAddress': 'direccion',
    'direccion_entrega': 'direccion',
    'direccionEntrega': 'direccion',
    // observaciones
    'observaciones': 'observaciones',
    'obs': 'observaciones',
    'notas': 'observaciones',
    'notes': 'observaciones',
    'comentarios': 'observaciones',
    'comments': 'observaciones',
    // orderId
    'orderId': 'orderId',
    'orderid': 'orderId',
    'order_id': 'orderId',
    'pedido': 'orderId',
    'nro_pedido': 'orderId',
    'nroPedido': 'orderId',
    'numero_pedido': 'orderId',
    'numeroPedido': 'orderId',
    'order': 'orderId',
    'order_number': 'orderId',
    'orderNumber': 'orderId',
    // localidad
    'localidad': 'localidad',
    'city': 'localidad',
    'ciudad': 'localidad',
    // provincia
    'provincia': 'provincia',
    'state': 'provincia',
    'province': 'provincia',
    // codigoPostal
    'codigoPostal': 'codigoPostal',
    'codigopostal': 'codigoPostal',
    'codigo_postal': 'codigoPostal',
    'cp': 'codigoPostal',
    'zip': 'codigoPostal',
    'zipcode': 'codigoPostal',
    'postalCode': 'codigoPostal',
    'postal_code': 'codigoPostal',
    // sourceType
    'sourceType': 'sourceType',
    'sourcetype': 'sourceType',
    'source_type': 'sourceType',
    'tipo': 'sourceType',
    'tipoDoc': 'sourceType',
    'tipo_doc': 'sourceType',
    // sourceNumber
    'sourceNumber': 'sourceNumber',
    'sourcenumber': 'sourceNumber',
    'source_number': 'sourceNumber',
    'nroDoc': 'sourceNumber',
    'nro_doc': 'sourceNumber',
    'docNumber': 'sourceNumber',
    'doc_number': 'sourceNumber',
    // direccionCompleta
    'direccionCompleta': 'direccionCompleta',
    'direccioncompleta': 'direccionCompleta',
    'direccion_completa': 'direccionCompleta',
    'fullAddress': 'direccionCompleta',
    'full_address': 'direccionCompleta',
  };

  /// Parsea el valor crudo de un QR intentando múltiples formatos.
  static QrParseResult parse(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return QrParseResult(
        fields: {},
        rawValue: rawValue,
        parseMethod: 'empty',
      );
    }

    // 1. Intentar JSON
    final jsonResult = _tryJson(trimmed);
    if (jsonResult != null) return jsonResult;

    // 2. Intentar URL con query params
    final urlResult = _tryUrl(trimmed);
    if (urlResult != null) return urlResult;

    // 3. Intentar pares clave=valor (&, ;, \n separados)
    final kvResult = _tryKeyValue(trimmed);
    if (kvResult != null) return kvResult;

    // 4. Intentar valores separados por | o ,
    final delimResult = _tryDelimited(trimmed);
    if (delimResult != null) return delimResult;

    // 5. Fallback: texto libre → observaciones
    return QrParseResult(
      fields: {'observaciones': trimmed, '_rawQr': trimmed},
      rawValue: rawValue,
      parseMethod: 'text',
    );
  }

  /// Intenta parsear como JSON (objeto).
  static QrParseResult? _tryJson(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        final mapped = _mapFieldNames(decoded);
        return QrParseResult(
          fields: mapped,
          rawValue: value,
          parseMethod: 'json',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Intenta parsear como URL con query params.
  static QrParseResult? _tryUrl(String value) {
    // Detectar si parece una URL
    if (!value.startsWith('http://') &&
        !value.startsWith('https://') &&
        !value.startsWith('www.') &&
        !value.contains('://')) {
      return null;
    }

    try {
      final uri = Uri.parse(value);
      if (uri.queryParameters.isEmpty) return null;

      final mapped = _mapFieldNames(
        uri.queryParameters.map((k, v) => MapEntry(k, Uri.decodeComponent(v))),
      );

      // Guardar la URL base como referencia
      mapped['_sourceUrl'] = '${uri.scheme}://${uri.host}${uri.path}';

      return QrParseResult(
        fields: mapped,
        rawValue: value,
        parseMethod: 'url',
      );
    } catch (_) {
      return null;
    }
  }

  /// Intenta parsear como pares clave=valor.
  static QrParseResult? _tryKeyValue(String value) {
    // Separadores comunes: &, ;, \n, \r\n
    final pairs = <String>[];

    if (value.contains('&')) {
      pairs.addAll(value.split('&'));
    } else if (value.contains(';')) {
      pairs.addAll(value.split(';'));
    } else if (value.contains('\n')) {
      pairs.addAll(value.split('\n'));
    } else {
      return null;
    }

    final map = <String, dynamic>{};
    int validPairs = 0;

    for (final pair in pairs) {
      final trimmedPair = pair.trim();
      if (trimmedPair.isEmpty) continue;

      final eqIndex = trimmedPair.indexOf('=');
      if (eqIndex <= 0) continue;

      final key = trimmedPair.substring(0, eqIndex).trim();
      final val = trimmedPair.substring(eqIndex + 1).trim();
      if (key.isNotEmpty) {
        map[key] = val;
        validPairs++;
      }
    }

    if (validPairs < 2) return null; // muy pocos pares, probablemente no es kv

    final mapped = _mapFieldNames(map);
    return QrParseResult(
      fields: mapped,
      rawValue: value,
      parseMethod: 'keyvalue',
    );
  }

  /// Intenta parsear como valores delimitados por | o , (posicional).
  /// Orden esperado: nombre|dni|direccion|telefono|observaciones
  static QrParseResult? _tryDelimited(String value) {
    List<String> parts;

    if (value.contains('|')) {
      parts = value.split('|').map((s) => s.trim()).toList();
    } else if (value.contains('\t')) {
      parts = value.split('\t').map((s) => s.trim()).toList();
    } else {
      return null;
    }

    if (parts.length < 2) return null;

    final map = <String, dynamic>{};
    final fieldOrder = ['nombre', 'dni', 'direccion', 'telefono', 'observaciones', 'orderId'];

    for (var i = 0; i < parts.length && i < fieldOrder.length; i++) {
      if (parts[i].isNotEmpty) {
        map[fieldOrder[i]] = parts[i];
      }
    }

    return QrParseResult(
      fields: map,
      rawValue: value,
      parseMethod: 'delimited',
    );
  }

  /// Mapea nombres de campo de distintos formatos a los nombres que usa la app.
  static Map<String, dynamic> _mapFieldNames(Map<dynamic, dynamic> input) {
    final result = <String, dynamic>{};

    for (final entry in input.entries) {
      final key = entry.key.toString().trim();
      final normalizedKey = key.toLowerCase();
      final mappedKey = _fieldAliases[key] ?? _fieldAliases[normalizedKey];

      if (mappedKey != null) {
        // Si ya hay un valor para este campo, no sobrescribir
        result.putIfAbsent(mappedKey, () => entry.value);
      } else {
        // Campo desconocido: conservar con nombre original (para debug)
        result['_extra_$key'] = entry.value;
      }
    }

    return result;
  }

  /// Construye un JSON Map compatible con Delivery.fromQrJson() a partir del resultado del parse.
  /// Completa campos faltantes con strings vacíos.
  static Map<String, dynamic> toDeliveryJson(QrParseResult result) {
    final fields = Map<String, dynamic>.from(result.fields);

    // Asegurar que los campos requeridos existan (pueden estar vacíos)
    fields.putIfAbsent('nombre', () => '');
    fields.putIfAbsent('telefono', () => '');
    fields.putIfAbsent('dni', () => '');
    fields.putIfAbsent('direccion', () => '');
    fields.putIfAbsent('observaciones', () => '');

    // Si no había observaciones y hay rawQr, agregarlo
    if (result.parseMethod != 'json' && result.parseMethod != 'empty') {
      final obs = (fields['observaciones'] ?? '').toString().trim();
      if (obs.isEmpty) {
        fields['observaciones'] = 'QR original: ${result.rawValue}';
      } else {
        fields['observaciones'] = '$obs | QR: ${result.rawValue}';
      }
    }

    // Limpiar campos internos que empiezan con _
    fields.removeWhere((k, _) => k.startsWith('_'));

    return fields;
  }
}
