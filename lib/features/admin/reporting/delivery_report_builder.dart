import '../../../core/data/user_repository.dart';
import '../../../core/utils/date_utils.dart' as app_date;
import '../../delivery/domain/delivery.dart';
import '../../delivery/domain/delivery_state.dart';
import 'delivery_report_models.dart';

/// Construye [DeliveryPeriodReport] desde el listado de entregas.
class DeliveryReportBuilder {
  DeliveryReportBuilder._();

  static String formatRangeLabel(DateTime start, DateTime endExclusive) {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final lastDay = endExclusive.subtract(const Duration(milliseconds: 1));
    if (app_date.AppDateUtils.startOfDay(start) ==
            app_date.AppDateUtils.startOfDay(lastDay) &&
        start.day == lastDay.day) {
      return fmt(start);
    }
    return '${fmt(start)} – ${fmt(lastDay)}';
  }

  static DeliveryPeriodReport build({
    required DateTime rangeStartInclusive,
    required DateTime rangeEndExclusive,
    required List<Delivery> all,
    required Map<String, String> conductorLabels,
    String? rangeLabel,
  }) {
    final start = app_date.AppDateUtils.startOfDay(rangeStartInclusive);
    final end = rangeEndExclusive;

    final cargas = all
        .where(
          (d) => app_date.AppDateUtils.isInRange(d.fechaEscaneo, start, end),
        )
        .toList();

    final byConductor = <String, List<Delivery>>{};
    for (final d in cargas) {
      final k = d.conductorId.trim();
      byConductor.putIfAbsent(k, () => []).add(d);
    }

    final rows = <ConductorDayRow>[];
    for (final e in byConductor.entries) {
      final uid = e.key;
      final list = e.value;
      final label = uid.isEmpty
          ? 'Sin asignar'
          : (conductorLabels[uid] ?? UserRepository.uidFallbackLabel(uid));
      rows.add(
        ConductorDayRow(
          conductorId: uid,
          label: label,
          total: list.length,
          pendientes:
              list.where((x) => x.estado == DeliveryState.pendiente).length,
          entregadas:
              list.where((x) => x.estado == DeliveryState.entregado).length,
          noEntregadas:
              list.where((x) => x.estado == DeliveryState.noEntregado).length,
        ),
      );
    }
    rows.sort((a, b) => b.total.compareTo(a.total));

    var cierreEnt = 0;
    var cierreNo = 0;
    for (final d in all) {
      if (d.estado == DeliveryState.entregado &&
          d.fechaEntrega != null &&
          app_date.AppDateUtils.isInRange(d.fechaEntrega!, start, end)) {
        cierreEnt++;
      }
      if (d.estado == DeliveryState.noEntregado &&
          d.fechaNoEntrega != null &&
          app_date.AppDateUtils.isInRange(d.fechaNoEntrega!, start, end)) {
        cierreNo++;
      }
    }

    final label = rangeLabel ?? formatRangeLabel(start, end);

    return DeliveryPeriodReport(
      rangeStartInclusive: start,
      rangeEndExclusive: end,
      rangeLabel: label,
      totalCargas: cargas.length,
      pendientes:
          cargas.where((d) => d.estado == DeliveryState.pendiente).length,
      entregadas:
          cargas.where((d) => d.estado == DeliveryState.entregado).length,
      noEntregadas:
          cargas.where((d) => d.estado == DeliveryState.noEntregado).length,
      cierresEntregadosEnPeriodo: cierreEnt,
      cierresNoEntregadosEnPeriodo: cierreNo,
      byConductor: rows,
    );
  }

  /// [comparison] = mes calendario anterior al inicio de [rangeStartInclusive].
  static DeliveryPeriodReport attachCalendarMonthComparison({
    required DeliveryPeriodReport main,
    required List<Delivery> all,
    required Map<String, String> conductorLabels,
  }) {
    final start = main.rangeStartInclusive;
    final prevMonthStart = app_date.AppDateUtils.startOfPreviousMonth(start);
    final prevMonthEnd = app_date.AppDateUtils.startOfMonth(start);
    final comp = build(
      rangeStartInclusive: prevMonthStart,
      rangeEndExclusive: prevMonthEnd,
      all: all,
      conductorLabels: conductorLabels,
      rangeLabel: formatRangeLabel(prevMonthStart, prevMonthEnd),
    );
    return main.copyWith(
      comparison: comp,
      comparisonRangeLabel: 'Mes calendario anterior (${comp.rangeLabel})',
    );
  }

  /// [comparison] = ventana de la misma duración que termina donde empieza el período actual.
  static DeliveryPeriodReport attachSlidingComparison({
    required DeliveryPeriodReport main,
    required List<Delivery> all,
    required Map<String, String> conductorLabels,
  }) {
    final duration = main.rangeEndExclusive.difference(main.rangeStartInclusive);
    if (duration.inMilliseconds <= 0) return main;
    final compEnd = main.rangeStartInclusive;
    final compStart = compEnd.subtract(duration);
    final comp = build(
      rangeStartInclusive: compStart,
      rangeEndExclusive: compEnd,
      all: all,
      conductorLabels: conductorLabels,
      rangeLabel: formatRangeLabel(
        app_date.AppDateUtils.startOfDay(compStart),
        compEnd,
      ),
    );
    return main.copyWith(
      comparison: comp,
      comparisonRangeLabel: 'Período anterior (${comp.rangeLabel})',
    );
  }
}
