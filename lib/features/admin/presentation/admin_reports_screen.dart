import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_breakpoints.dart';
import '../../../core/data/user_repository.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart' as app_date;
import '../../delivery/data/delivery_repository.dart';
import '../../delivery/domain/delivery.dart';
import '../reporting/admin_report_pdf.dart';
import '../reporting/delivery_report_builder.dart';
import '../reporting/delivery_report_models.dart';

/// Reportes de envíos para admin: vista tipo documento (como el PDF), exportación PDF.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

enum _ReportPeriod { day, week7, month, custom }

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  _ReportPeriod _mode = _ReportPeriod.day;
  DateTime _day = DateTime.now();
  DateTime _customStart = DateTime.now();
  DateTime _customEnd = DateTime.now();
  bool _compare = false;
  Map<String, String> _conductorLabels = {};
  bool _labelsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLabels();
  }

  Future<void> _loadLabels() async {
    setState(() => _labelsLoading = true);
    try {
      final users = await UserRepository.instance.getAllUsers();
      if (!mounted) return;
      final map = <String, String>{};
      for (final u in users) {
        map[u.uid] = UserRepository.driverDisplayLabel(u);
      }
      setState(() {
        _conductorLabels = map;
        _labelsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _labelsLoading = false);
    }
  }

  (DateTime start, DateTime endExclusive) _resolveRange() {
    final now = DateTime.now();
    switch (_mode) {
      case _ReportPeriod.day:
        final d = _day;
        return (
          app_date.AppDateUtils.startOfDay(d),
          app_date.AppDateUtils.endOfDay(d),
        );
      case _ReportPeriod.week7:
        final end = app_date.AppDateUtils.endOfDay(now);
        final start = app_date.AppDateUtils
            .startOfDay(now)
            .subtract(const Duration(days: 6));
        return (start, end);
      case _ReportPeriod.month:
        final s = app_date.AppDateUtils.startOfMonth(now);
        final e = app_date.AppDateUtils.startOfNextMonth(now);
        return (s, e);
      case _ReportPeriod.custom:
        final a = _customStart;
        final b = _customEnd;
        final first = a.isBefore(b) ? a : b;
        final last = a.isBefore(b) ? b : a;
        return (
          app_date.AppDateUtils.startOfDay(first),
          app_date.AppDateUtils.endOfDay(last),
        );
    }
  }

  String _compareHint() {
    switch (_mode) {
      case _ReportPeriod.month:
        return 'Se comparará con el mes calendario anterior.';
      default:
        return 'Se comparará con la ventana anterior de la misma duración.';
    }
  }

  DeliveryPeriodReport _buildReport(List<Delivery> all) {
    final (start, end) = _resolveRange();
    var report = DeliveryReportBuilder.build(
      rangeStartInclusive: start,
      rangeEndExclusive: end,
      all: all,
      conductorLabels: _conductorLabels,
    );
    if (_compare) {
      if (_mode == _ReportPeriod.month) {
        report = DeliveryReportBuilder.attachCalendarMonthComparison(
          main: report,
          all: all,
          conductorLabels: _conductorLabels,
        );
      } else {
        report = DeliveryReportBuilder.attachSlidingComparison(
          main: report,
          all: all,
          conductorLabels: _conductorLabels,
        );
      }
    }
    return report;
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _day = picked);
  }

  Future<void> _pickCustomStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customStart,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _customStart = picked);
  }

  Future<void> _pickCustomEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customEnd,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _customEnd = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes de envíos'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar etiquetas de conductores',
            icon: const Icon(Icons.refresh),
            onPressed: _loadLabels,
          ),
        ],
      ),
      body: _labelsLoading
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Delivery>>(
              stream: DeliveryRepository.instance.watchAllDeliveries(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snapshot.data ?? [];
                final report = _buildReport(all);
                final screenW = MediaQuery.sizeOf(context).width;
                final pad = screenW < AppBreakpoints.narrowScreenWidth ? 12.0 : 16.0;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: ListView(
                      padding: EdgeInsets.all(pad),
                      children: [
                        _PeriodSelector(
                          mode: _mode,
                          onModeChanged: (m) => setState(() => _mode = m),
                        ),
                        if (_mode == _ReportPeriod.day) ...[
                          const SizedBox(height: 8),
                          _DayPickerCard(day: _day, onPick: _pickDay),
                        ],
                        if (_mode == _ReportPeriod.custom) ...[
                          const SizedBox(height: 8),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.date_range_outlined,
                                    ),
                                    title: const Text('Desde'),
                                    subtitle: Text(
                                      DeliveryReportBuilder.formatRangeLabel(
                                        app_date.AppDateUtils
                                            .startOfDay(_customStart),
                                        app_date.AppDateUtils
                                            .endOfDay(_customStart),
                                      ),
                                    ),
                                    trailing: FilledButton.tonal(
                                      onPressed: _pickCustomStart,
                                      child: const Text('Elegir'),
                                    ),
                                  ),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.event_outlined,
                                    ),
                                    title: const Text('Hasta'),
                                    subtitle: Text(
                                      DeliveryReportBuilder.formatRangeLabel(
                                        app_date.AppDateUtils
                                            .startOfDay(_customEnd),
                                        app_date.AppDateUtils
                                            .endOfDay(_customEnd),
                                      ),
                                    ),
                                    trailing: FilledButton.tonal(
                                      onPressed: _pickCustomEnd,
                                      child: const Text('Elegir'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        SwitchListTile(
                          secondary: const Icon(Icons.compare_arrows),
                          title: const Text('Comparar con período anterior'),
                          subtitle: Text(
                            _compareHint(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          value: _compare,
                          onChanged: (v) => setState(() => _compare = v),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Los totales principales usan la fecha de carga (escaneo). '
                          'Los cierres usan la fecha en que se marcó entregado o no entregado.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _ReportDocumentView(report: report),
                        const SizedBox(height: 24),
                        _ExportButtons(report: report),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.mode,
    required this.onModeChanged,
  });

  final _ReportPeriod mode;
  final ValueChanged<_ReportPeriod> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Período',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Un día'),
                  selected: mode == _ReportPeriod.day,
                  onSelected: (_) => onModeChanged(_ReportPeriod.day),
                ),
                ChoiceChip(
                  label: const Text('7 días'),
                  selected: mode == _ReportPeriod.week7,
                  onSelected: (_) => onModeChanged(_ReportPeriod.week7),
                ),
                ChoiceChip(
                  label: const Text('Este mes'),
                  selected: mode == _ReportPeriod.month,
                  onSelected: (_) => onModeChanged(_ReportPeriod.month),
                ),
                ChoiceChip(
                  label: const Text('Rango'),
                  selected: mode == _ReportPeriod.custom,
                  onSelected: (_) => onModeChanged(_ReportPeriod.custom),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayPickerCard extends StatelessWidget {
  const _DayPickerCard({required this.day, required this.onPick});

  final DateTime day;
  final VoidCallback onPick;

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.calendar_today_outlined),
        title: Text('Día del reporte: ${_fmt(day)}'),
        trailing: FilledButton.tonal(
          onPressed: onPick,
          child: const Text('Cambiar fecha'),
        ),
      ),
    );
  }
}

/// Vista tipo documento PDF: encabezado, tablas, colores suaves.
class _ReportDocumentView extends StatelessWidget {
  const _ReportDocumentView({required this.report});

  final DeliveryPeriodReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = report;
    final comp = r.comparison;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.description_outlined, color: AppTheme.adminPrimaryBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AcuaFlex — Reporte de envíos',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Período: ${r.rangeLabel}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Criterio: envíos con fecha de carga (escaneo) en el período.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _SectionTitle(text: 'Totales (por fecha de carga)'),
            const SizedBox(height: 8),
            _TotalsTable(report: r),
            if (comp != null) ...[
              const SizedBox(height: 20),
              _SectionTitle(
                text: r.comparisonRangeLabel ?? 'Comparación',
              ),
              const SizedBox(height: 6),
              Text(
                comp.rangeLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              _ComparisonTable(current: r, previous: comp),
            ],
            const SizedBox(height: 20),
            _SectionTitle(text: 'Cierres en el período'),
            const SizedBox(height: 8),
            _ClosureRow(report: r),
            const SizedBox(height: 20),
            _SectionTitle(text: 'Por conductor'),
            const SizedBox(height: 8),
            _ConductorTable(report: r),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.adminPrimaryBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: AppTheme.adminPrimaryBlue,
        ),
      ),
    );
  }
}

class _TotalsTable extends StatelessWidget {
  const _TotalsTable({required this.report});

  final DeliveryPeriodReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final rows = [
      ('Total envíos', r.totalCargas, AppTheme.adminPrimaryBlue),
      ('Pendientes', r.pendientes, AppTheme.adminPendienteColor),
      ('Entregadas', r.entregadas, AppTheme.adminEntregadoColor),
      ('No entregadas', r.noEntregadas, AppTheme.adminNoEntregadoColor),
    ];
    return Table(
      border: TableBorder.all(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
          ),
          children: const [
            _ThCell('Concepto'),
            _ThCell('Cantidad', alignRight: true),
          ],
        ),
        for (final e in rows)
          TableRow(
            children: [
              _TdCell(e.$1),
              _TdCell(
                '${e.$2}',
                alignRight: true,
                valueColor: e.$3,
                emphasize: true,
              ),
            ],
          ),
      ],
    );
  }
}

class _ThCell extends StatelessWidget {
  const _ThCell(this.text, {this.alignRight = false});

  final String text;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _TdCell extends StatelessWidget {
  const _TdCell(
    this.text, {
    this.alignRight = false,
    this.valueColor,
    this.emphasize = false,
  });

  final String text;
  final bool alignRight;
  final Color? valueColor;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: (emphasize ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
            ?.copyWith(
          color: valueColor,
          fontWeight: emphasize ? FontWeight.bold : null,
        ),
      ),
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({
    required this.current,
    required this.previous,
  });

  final DeliveryPeriodReport current;
  final DeliveryPeriodReport previous;

  int _d(int a, int b) => a - b;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget deltaCell(int a, int b) {
      final d = _d(a, b);
      final color = d > 0
          ? AppTheme.adminEntregadoColor
          : (d < 0 ? AppTheme.adminNoEntregadoColor : theme.colorScheme.onSurfaceVariant);
      return Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          d > 0 ? '+$d' : '$d',
          textAlign: TextAlign.right,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      );
    }

    final data = [
      ('Total envíos', current.totalCargas, previous.totalCargas),
      ('Pendientes', current.pendientes, previous.pendientes),
      ('Entregadas', current.entregadas, previous.entregadas),
      ('No entregadas', current.noEntregadas, previous.noEntregadas),
      (
        'Cierres entregado',
        current.cierresEntregadosEnPeriodo,
        previous.cierresEntregadosEnPeriodo,
      ),
      (
        'Cierres no entregado',
        current.cierresNoEntregadosEnPeriodo,
        previous.cierresNoEntregadosEnPeriodo,
      ),
    ];

    return Table(
      border: TableBorder.all(color: theme.colorScheme.outlineVariant),
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
          ),
          children: const [
            _ThCell('Concepto'),
            _ThCell('Actual', alignRight: true),
            _ThCell('Ant.', alignRight: true),
            _ThCell('Δ', alignRight: true),
          ],
        ),
        for (final row in data)
          TableRow(
            children: [
              _TdCell(row.$1),
              _TdCell('${row.$2}', alignRight: true, emphasize: true),
              _TdCell('${row.$3}', alignRight: true),
              deltaCell(row.$2, row.$3),
            ],
          ),
      ],
    );
  }
}

class _ClosureRow extends StatelessWidget {
  const _ClosureRow({required this.report});

  final DeliveryPeriodReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    return Row(
      children: [
        Expanded(
          child: _MiniStat(
            label: 'Entregado (fecha cierre)',
            value: r.cierresEntregadosEnPeriodo,
            color: AppTheme.adminEntregadoColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MiniStat(
            label: 'No entregado (fecha cierre)',
            value: r.cierresNoEntregadosEnPeriodo,
            color: AppTheme.adminNoEntregadoColor,
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConductorTable extends StatelessWidget {
  const _ConductorTable({required this.report});

  final DeliveryPeriodReport report;

  @override
  Widget build(BuildContext context) {
    final rows = report.byConductor;
    if (rows.isEmpty) {
      return Text(
        'Sin envíos en el período.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(
          AppTheme.adminPrimaryBlue.withValues(alpha: 0.08),
        ),
        columns: const [
          DataColumn(label: Text('Conductor')),
          DataColumn(label: Text('Total'), numeric: true),
          DataColumn(label: Text('Pend.'), numeric: true),
          DataColumn(label: Text('Entr.'), numeric: true),
          DataColumn(label: Text('No ent.'), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              cells: [
                DataCell(Text(r.label)),
                DataCell(Text('${r.total}')),
                DataCell(Text('${r.pendientes}')),
                DataCell(Text('${r.entregadas}')),
                DataCell(Text('${r.noEntregadas}')),
              ],
            ),
        ],
      ),
    );
  }
}

class _ExportButtons extends StatelessWidget {
  const _ExportButtons({required this.report});

  final DeliveryPeriodReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    Widget labeledButton({
      required Widget child,
    }) {
      return SizedBox(
        width: double.infinity,
        child: child,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < AppBreakpoints.compactButtonRow;
        final buttons = <Widget>[
          labeledButton(
            child: FilledButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text(
                'Vista previa PDF completo',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => AdminReportPdf.previewFull(r),
            ),
          ),
          labeledButton(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.text_snippet_outlined),
              label: const Text(
                'Vista previa resumen',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => AdminReportPdf.previewSummary(r),
            ),
          ),
          labeledButton(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.share_outlined),
              label: const Text(
                'Compartir PDF completo',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => AdminReportPdf.shareFull(r),
            ),
          ),
          labeledButton(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.share_outlined),
              label: const Text(
                'Compartir resumen',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => AdminReportPdf.shareSummary(r),
            ),
          ),
        ];

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                buttons[i],
              ],
            ],
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.start,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Vista previa PDF completo'),
              onPressed: () => AdminReportPdf.previewFull(r),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.text_snippet_outlined),
              label: const Text('Vista previa resumen'),
              onPressed: () => AdminReportPdf.previewSummary(r),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.share_outlined),
              label: const Text('Compartir PDF completo'),
              onPressed: () => AdminReportPdf.shareFull(r),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.share_outlined),
              label: const Text('Compartir resumen'),
              onPressed: () => AdminReportPdf.shareSummary(r),
            ),
          ],
        );
      },
    );
  }
}
