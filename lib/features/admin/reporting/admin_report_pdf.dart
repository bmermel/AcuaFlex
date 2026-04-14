import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'delivery_report_models.dart';

/// PDF de reportes (compartible e imprimible; mismo contenido que la vista web).
class AdminReportPdf {
  AdminReportPdf._();

  static String _fileSlug(DeliveryPeriodReport r) {
    String ymd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final start = r.rangeStartInclusive;
    final last = r.rangeEndExclusive.subtract(const Duration(milliseconds: 1));
    if (start.year == last.year &&
        start.month == last.month &&
        start.day == last.day) {
      return ymd(start);
    }
    return '${ymd(start)}_${ymd(last)}';
  }

  static Future<void> previewFull(DeliveryPeriodReport r) async {
    final bytes = await buildFull(r);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'acuaflex_reporte_${_fileSlug(r)}.pdf',
    );
  }

  static Future<void> previewSummary(DeliveryPeriodReport r) async {
    final bytes = await buildSummary(r);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'acuaflex_resumen_${_fileSlug(r)}.pdf',
    );
  }

  static Future<void> shareFull(DeliveryPeriodReport r) async {
    final bytes = await buildFull(r);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'acuaflex_reporte_${_fileSlug(r)}.pdf',
    );
  }

  static Future<void> shareSummary(DeliveryPeriodReport r) async {
    final bytes = await buildSummary(r);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'acuaflex_resumen_${_fileSlug(r)}.pdf',
    );
  }

  static Future<Uint8List> buildFull(DeliveryPeriodReport r) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'AcuaFlex — Reporte de envíos',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Período: ${r.rangeLabel}',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Criterio principal: envíos con fecha de carga (escaneo) en el período.',
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Totales (por fecha de carga)',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          _totalsTable(r),
          if (r.comparison != null) ...[
            pw.SizedBox(height: 16),
            pw.Text(
              r.comparisonRangeLabel ?? 'Período de comparación',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              r.comparison!.rangeLabel,
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 8),
            _comparisonTable(r, r.comparison!),
          ],
          pw.SizedBox(height: 16),
          pw.Text(
            'Cierres registrados en el período',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Entregas marcadas como entregado con fecha de entrega en el período: ${r.cierresEntregadosEnPeriodo}',
          ),
          pw.Text(
            'Marcadas como no entregado con fecha en el período: ${r.cierresNoEntregadosEnPeriodo}',
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Por conductor (fecha de carga en el período)',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          if (r.byConductor.isEmpty)
            pw.Text('Sin envíos en el período.')
          else
            _conductorsTable(r),
        ],
      ),
    );
    return doc.save();
  }

  static Future<Uint8List> buildSummary(DeliveryPeriodReport r) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'AcuaFlex — Resumen',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(r.rangeLabel, style: const pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 28),
            _summaryLine('Total envíos (carga en el período)', r.totalCargas),
            _summaryLine('Pendientes', r.pendientes),
            _summaryLine('Entregadas', r.entregadas),
            _summaryLine('No entregadas', r.noEntregadas),
            pw.SizedBox(height: 16),
            pw.Text(
              'Cierres en el período',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            _summaryLine(
              'Entregado (fecha cierre)',
              r.cierresEntregadosEnPeriodo,
            ),
            _summaryLine(
              'No entregado (fecha cierre)',
              r.cierresNoEntregadosEnPeriodo,
            ),
            if (r.comparison != null) ...[
              pw.SizedBox(height: 20),
              pw.Text(
                r.comparisonRangeLabel ?? 'Comparación',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                r.comparison!.rangeLabel,
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 12),
              _summaryLine(
                'Total envíos (período anterior)',
                r.comparison!.totalCargas,
              ),
              _summaryLine(
                'Variación vs anterior',
                r.totalCargas - r.comparison!.totalCargas,
              ),
            ],
          ],
        ),
      ),
    );
    return doc.save();
  }

  static pw.Widget _summaryLine(String label, int value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(child: pw.Text(label)),
          pw.Text(
            '$value',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _totalsTable(DeliveryPeriodReport r) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _cell('Concepto', header: true),
            _cell('Cantidad', header: true),
          ],
        ),
        pw.TableRow(
          children: [
            _cell('Total envíos'),
            _cell('${r.totalCargas}'),
          ],
        ),
        pw.TableRow(
          children: [
            _cell('Pendientes'),
            _cell('${r.pendientes}'),
          ],
        ),
        pw.TableRow(
          children: [
            _cell('Entregadas'),
            _cell('${r.entregadas}'),
          ],
        ),
        pw.TableRow(
          children: [
            _cell('No entregadas'),
            _cell('${r.noEntregadas}'),
          ],
        ),
      ],
    );
  }

  static pw.Widget _comparisonTable(
    DeliveryPeriodReport current,
    DeliveryPeriodReport previous,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _cell('Concepto', header: true),
            _cell('Actual', header: true),
            _cell('Comparación', header: true),
            _cell('Δ', header: true),
          ],
        ),
        _cmpRow('Total envíos', current.totalCargas, previous.totalCargas),
        _cmpRow('Pendientes', current.pendientes, previous.pendientes),
        _cmpRow('Entregadas', current.entregadas, previous.entregadas),
        _cmpRow('No entregadas', current.noEntregadas, previous.noEntregadas),
        _cmpRow(
          'Cierres entregado',
          current.cierresEntregadosEnPeriodo,
          previous.cierresEntregadosEnPeriodo,
        ),
        _cmpRow(
          'Cierres no entregado',
          current.cierresNoEntregadosEnPeriodo,
          previous.cierresNoEntregadosEnPeriodo,
        ),
      ],
    );
  }

  static pw.TableRow _cmpRow(String label, int a, int b) {
    final d = a - b;
    final ds = d >= 0 ? '+$d' : '$d';
    return pw.TableRow(
      children: [
        _cell(label),
        _cell('$a'),
        _cell('$b'),
        _cell(ds),
      ],
    );
  }

  static pw.Widget _conductorsTable(DeliveryPeriodReport r) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FlexColumnWidth(2.2),
        1: const pw.FlexColumnWidth(0.7),
        2: const pw.FlexColumnWidth(0.7),
        3: const pw.FlexColumnWidth(0.7),
        4: const pw.FlexColumnWidth(0.7),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _cell('Conductor', header: true),
            _cell('Tot.', header: true),
            _cell('Pend.', header: true),
            _cell('Entr.', header: true),
            _cell('No ent.', header: true),
          ],
        ),
        ...r.byConductor.map(
          (row) => pw.TableRow(
            children: [
              _cell(row.label),
              _cell('${row.total}'),
              _cell('${row.pendientes}'),
              _cell('${row.entregadas}'),
              _cell('${row.noEntregadas}'),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _cell(String text, {bool header = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: header ? 9 : 9,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
