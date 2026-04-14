/// Métricas agregadas para un rango de fechas [rangeStartInclusive, rangeEndExclusive).
class DeliveryPeriodReport {
  const DeliveryPeriodReport({
    required this.rangeStartInclusive,
    required this.rangeEndExclusive,
    required this.rangeLabel,
    required this.totalCargas,
    required this.pendientes,
    required this.entregadas,
    required this.noEntregadas,
    required this.cierresEntregadosEnPeriodo,
    required this.cierresNoEntregadosEnPeriodo,
    required this.byConductor,
    this.comparison,
    this.comparisonRangeLabel,
  });

  final DateTime rangeStartInclusive;
  final DateTime rangeEndExclusive;

  /// Texto legible del rango (ej. "01/03/2026 – 31/03/2026").
  final String rangeLabel;

  /// Envíos cuya [fechaEscaneo] cae en el rango.
  final int totalCargas;
  final int pendientes;
  final int entregadas;
  final int noEntregadas;

  /// Cierres con [fechaEntrega] en el rango.
  final int cierresEntregadosEnPeriodo;

  /// Cierres con [fechaNoEntrega] en el rango.
  final int cierresNoEntregadosEnPeriodo;

  final List<ConductorDayRow> byConductor;

  /// Opcional: mismo reporte para el período de comparación (mes anterior o ventana anterior).
  final DeliveryPeriodReport? comparison;
  final String? comparisonRangeLabel;

  DeliveryPeriodReport copyWith({
    DeliveryPeriodReport? comparison,
    String? comparisonRangeLabel,
  }) {
    return DeliveryPeriodReport(
      rangeStartInclusive: rangeStartInclusive,
      rangeEndExclusive: rangeEndExclusive,
      rangeLabel: rangeLabel,
      totalCargas: totalCargas,
      pendientes: pendientes,
      entregadas: entregadas,
      noEntregadas: noEntregadas,
      cierresEntregadosEnPeriodo: cierresEntregadosEnPeriodo,
      cierresNoEntregadosEnPeriodo: cierresNoEntregadosEnPeriodo,
      byConductor: byConductor,
      comparison: comparison ?? this.comparison,
      comparisonRangeLabel: comparisonRangeLabel ?? this.comparisonRangeLabel,
    );
  }
}

class ConductorDayRow {
  const ConductorDayRow({
    required this.conductorId,
    required this.label,
    required this.total,
    required this.pendientes,
    required this.entregadas,
    required this.noEntregadas,
  });

  final String conductorId;
  final String label;
  final int total;
  final int pendientes;
  final int entregadas;
  final int noEntregadas;
}
