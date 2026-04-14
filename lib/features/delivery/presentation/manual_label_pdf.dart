import 'dart:convert';
import 'dart:math' show min;

import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/delivery.dart';
import '../domain/delivery_state.dart';

/// Etiquetas físicas para entregas manuales: hasta 8 por hoja A4 (rejilla 2×4; ~1/8 de hoja cada una).
class ManualLabelPdf {
  ManualLabelPdf._();

  /// Manual y aún no entregada (no se imprimen etiquetas de pedidos ya cerrados como entregados).
  static bool canPrintLabel(Delivery d) =>
      d.isManual && d.estado != DeliveryState.entregado;

  /// Abre el diálogo de impresión del sistema con una o más etiquetas.
  /// Solo incluye entregas que cumplan [canPrintLabel]; el resto se ignora.
  static Future<void> printLabels(List<Delivery> deliveries) async {
    final eligible = deliveries.where(canPrintLabel).toList();
    if (eligible.isEmpty) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ManualLabelPdf] printLabels: ninguna entrega elegible, se omite.');
      }
      return;
    }

    final doc = _buildDocument(eligible);
    final bytes = await doc.save();

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name: 'etiquetas_manuales_acuaflex.pdf',
    );
  }

  static pw.Document _buildDocument(List<Delivery> list) {
    final doc = pw.Document();
    const perPage = 8;

    for (var i = 0; i < list.length; i += perPage) {
      final end = min(i + perPage, list.length);
      final chunk = list.sublist(i, end);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) => _eightLabelGrid(chunk),
        ),
      );
    }
    return doc;
  }

  /// Rejilla 2 columnas × 4 filas en A4; cada celda ≈ 1/8 de hoja.
  static pw.Widget _eightLabelGrid(List<Delivery> chunk) {
    assert(chunk.length <= 8);
    final padded = List<Delivery?>.from(chunk);
    while (padded.length < 8) {
      padded.add(null);
    }

    pw.Widget rowPair(int a, int b) {
      return pw.Expanded(
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Expanded(child: _cell(padded[a])),
            pw.SizedBox(width: 6),
            pw.Expanded(child: _cell(padded[b])),
          ],
        ),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        children: [
          rowPair(0, 1),
          rowPair(2, 3),
          rowPair(4, 5),
          rowPair(6, 7),
        ],
      ),
    );
  }

  static const PdfColor _ink = PdfColors.black;

  static pw.Widget _cell(Delivery? d) {
    if (d == null) {
      return pw.SizedBox();
    }
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _ink, width: 0.65),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.SizedBox.expand(
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: pw.Center(
            child: _labelBody(d),
          ),
        ),
      ),
    );
  }

  static pw.Widget _labelBody(Delivery d) {
    final qrPayload = jsonEncode(d.toQrJson());
    const tBrand = 6.5;
    const tHero = 10.0;
    const tName = 9.0;
    const tAddr = 7.0;
    const tMeta = 6.5;
    const tObs = 6.0;
    const tFoot = 5.5;

    final brandStyle = pw.TextStyle(
      fontSize: tBrand,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 0.6,
      color: _ink,
    );
    final heroStyle = pw.TextStyle(
      fontSize: tHero,
      fontWeight: pw.FontWeight.bold,
      color: _ink,
      height: 1.15,
    );
    final nameStyle = pw.TextStyle(
      fontSize: tName,
      fontWeight: pw.FontWeight.bold,
      color: _ink,
      height: 1.2,
    );
    final addrStyle = pw.TextStyle(
      fontSize: tAddr,
      color: _ink,
      height: 1.25,
    );
    final metaStyle = pw.TextStyle(
      fontSize: tMeta,
      color: _ink,
      height: 1.2,
    );
    final obsStyle = pw.TextStyle(
      fontSize: tObs,
      color: _ink,
      height: 1.2,
    );
    final footStyle = pw.TextStyle(
      fontSize: tFoot,
      color: _ink,
    );

    final idLine = d.hasOrderId
        ? Delivery.formatOrderIdForDisplay(d.orderId!)
        : (d.sourceNumber != null && d.sourceNumber!.trim().isNotEmpty
            ? '${d.sourceType.trim().toUpperCase()} ${d.sourceNumber!.trim()}'
            : d.sourceLabel);

    pw.Widget centeredText(String text, pw.TextStyle style, {int maxLines = 4}) {
      return pw.Text(
        text,
        style: style,
        textAlign: pw.TextAlign.center,
        maxLines: maxLines,
      );
    }

    final addressLines = <String>[
      d.direccion.trim(),
      if (d.localidad != null && d.localidad!.trim().isNotEmpty)
        d.localidad!.trim(),
      if (d.codigoPostal != null && d.codigoPostal!.trim().isNotEmpty)
        'CP ${d.codigoPostal!.trim()}',
      if (d.direccionCompleta != null &&
          d.direccionCompleta!.trim().isNotEmpty &&
          d.direccionCompleta!.trim() != d.direccion.trim())
        d.direccionCompleta!.trim(),
    ].where((s) => s.isNotEmpty).toList();

    final contactParts = <String>[];
    if (d.telefono.trim().isNotEmpty) contactParts.add('Tel. ${d.telefono.trim()}');
    if (d.dni.trim().isNotEmpty) contactParts.add('DNI ${d.dni.trim()}');
    final contactLine = contactParts.join('  ·  ');

    return pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        centeredText('ACUAFLEX · ENTREGA MANUAL', brandStyle, maxLines: 1),
        pw.SizedBox(height: 6),
        centeredText(idLine, heroStyle, maxLines: 2),
        pw.SizedBox(height: 6),
        centeredText(d.nombre.trim(), nameStyle, maxLines: 2),
        pw.SizedBox(height: 6),
        ...addressLines.map(
          (line) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: centeredText(line, addrStyle, maxLines: 3),
          ),
        ),
        if (contactLine.isNotEmpty) ...[
          pw.SizedBox(height: 5),
          centeredText(contactLine, metaStyle, maxLines: 2),
        ],
        pw.SizedBox(height: 8),
        pw.SizedBox(
          width: 58,
          height: 58,
          child: pw.BarcodeWidget(
            barcode: Barcode.qrCode(),
            data: qrPayload,
            drawText: false,
          ),
        ),
        pw.SizedBox(height: 4),
        centeredText('Escanear QR', footStyle, maxLines: 1),
        if (d.observaciones.trim().isNotEmpty) ...[
          pw.SizedBox(height: 6),
          centeredText(
            'Obs. ${_truncate(d.observaciones, 120)}',
            obsStyle,
            maxLines: 4,
          ),
        ],
      ],
    );
  }

  static String _truncate(String s, int max) {
    final t = s.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1)}…';
  }
}
