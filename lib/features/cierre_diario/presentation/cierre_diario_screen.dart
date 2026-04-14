import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_breakpoints.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart' as app_date;
import '../../../core/widgets/summary_card.dart';
import '../../delivery/data/delivery_repository.dart';
import '../../delivery/domain/delivery.dart';
import '../../delivery/domain/delivery_state.dart';

/// Filtro para la lista del cierre diario.
enum _CierreFilter { all, pendientes, entregadas, noEntregadas }

/// Rango de fechas (mismo criterio que panel admin).
enum _CierreDateFilter { hoy, ayer, ultimos7 }

class CierreDiarioScreen extends StatefulWidget {
  const CierreDiarioScreen({super.key});

  @override
  State<CierreDiarioScreen> createState() => _CierreDiarioScreenState();
}

class _CierreDiarioScreenState extends State<CierreDiarioScreen> {
  _CierreFilter _filter = _CierreFilter.pendientes;
  _CierreDateFilter _dateFilter = _CierreDateFilter.hoy;

  List<Delivery> _inDateRange(List<Delivery> all) {
    switch (_dateFilter) {
      case _CierreDateFilter.hoy:
        final r = app_date.AppDateUtils.todayRange;
        return all
            .where((d) =>
                app_date.AppDateUtils.isInRange(d.fechaEscaneo, r.$1, r.$2))
            .toList();
      case _CierreDateFilter.ayer:
        final r = app_date.AppDateUtils.yesterdayRange;
        return all
            .where((d) =>
                app_date.AppDateUtils.isInRange(d.fechaEscaneo, r.$1, r.$2))
            .toList();
      case _CierreDateFilter.ultimos7:
        final start = app_date.AppDateUtils.last7DaysStart;
        return all.where((d) => !d.fechaEscaneo.isBefore(start)).toList();
    }
  }

  String _periodPhrase() {
    switch (_dateFilter) {
      case _CierreDateFilter.hoy:
        return 'hoy';
      case _CierreDateFilter.ayer:
        return 'de ayer';
      case _CierreDateFilter.ultimos7:
        return 'de los últimos 7 días';
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.currentUser?.uid ?? '';
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cierre diario'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: uid.isEmpty
          ? const Center(child: Text('Iniciá sesión para ver tu cierre diario.'))
          : StreamBuilder<List<Delivery>>(
              stream: DeliveryRepository.instance.watchDeliveriesByDriver(uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snapshot.data ?? [];
                if (all.isEmpty) {
                  return const Center(
                    child: Text('Aún no tenés entregas cargadas.'),
                  );
                }

                final scoped = _inDateRange(all);
                final total = scoped.length;
                final pendientes = scoped
                    .where((d) => d.estado == DeliveryState.pendiente)
                    .length;
                final entregadas = scoped
                    .where((d) => d.estado == DeliveryState.entregado)
                    .length;
                final noEntregadas = scoped
                    .where((d) => d.estado == DeliveryState.noEntregado)
                    .length;

                final filtered = scoped.where((d) {
                  switch (_filter) {
                    case _CierreFilter.all:
                      return true;
                    case _CierreFilter.pendientes:
                      return d.estado == DeliveryState.pendiente;
                    case _CierreFilter.entregadas:
                      return d.estado == DeliveryState.entregado;
                    case _CierreFilter.noEntregadas:
                      return d.estado == DeliveryState.noEntregado;
                  }
                }).toList();

                String listTitle;
                switch (_filter) {
                  case _CierreFilter.all:
                    listTitle = 'Entregas ${_periodPhrase()}';
                    break;
                  case _CierreFilter.pendientes:
                    listTitle = 'Pendientes ${_periodPhrase()}';
                    break;
                  case _CierreFilter.entregadas:
                    listTitle = 'Entregadas ${_periodPhrase()}';
                    break;
                  case _CierreFilter.noEntregadas:
                    listTitle = 'No entregadas ${_periodPhrase()}';
                    break;
                }

                final screenW = MediaQuery.sizeOf(context).width;
                final outerPad = screenW < AppBreakpoints.narrowScreenWidth ? 12.0 : 16.0;
                return ListView(
                  padding: EdgeInsets.all(outerPad),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Período',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ChoiceChip(
                                  label: const Text('Hoy'),
                                  selected:
                                      _dateFilter == _CierreDateFilter.hoy,
                                  onSelected: (_) => setState(
                                      () => _dateFilter = _CierreDateFilter.hoy),
                                  selectedColor: AppTheme.selectedTint,
                                  side: BorderSide(
                                    color: _dateFilter == _CierreDateFilter.hoy
                                        ? theme.colorScheme.primary
                                        : AppTheme.borderLight,
                                    width:
                                        _dateFilter == _CierreDateFilter.hoy
                                            ? 2
                                            : 1,
                                  ),
                                ),
                                ChoiceChip(
                                  label: const Text('Ayer'),
                                  selected:
                                      _dateFilter == _CierreDateFilter.ayer,
                                  onSelected: (_) => setState(() =>
                                      _dateFilter = _CierreDateFilter.ayer),
                                  selectedColor: AppTheme.selectedTint,
                                  side: BorderSide(
                                    color: _dateFilter == _CierreDateFilter.ayer
                                        ? theme.colorScheme.primary
                                        : AppTheme.borderLight,
                                    width:
                                        _dateFilter == _CierreDateFilter.ayer
                                            ? 2
                                            : 1,
                                  ),
                                ),
                                ChoiceChip(
                                  label: const Text('Últimos 7 días'),
                                  selected: _dateFilter ==
                                      _CierreDateFilter.ultimos7,
                                  onSelected: (_) => setState(() =>
                                      _dateFilter =
                                          _CierreDateFilter.ultimos7),
                                  selectedColor: AppTheme.selectedTint,
                                  side: BorderSide(
                                    color: _dateFilter ==
                                            _CierreDateFilter.ultimos7
                                        ? theme.colorScheme.primary
                                        : AppTheme.borderLight,
                                    width: _dateFilter ==
                                            _CierreDateFilter.ultimos7
                                        ? 2
                                        : 1,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SummaryCardsGrid(
                      children: [
                        SummaryCard(
                          compact: true,
                          title: 'Total',
                          value: total.toString(),
                          icon: AppTheme.iconTotal,
                          selected: _filter == _CierreFilter.all,
                          onTap: () =>
                              setState(() => _filter = _CierreFilter.all),
                        ),
                        SummaryCard(
                          compact: true,
                          title: 'Pendientes',
                          value: pendientes.toString(),
                          icon: AppTheme.iconPendientes,
                          color: AppTheme.pendienteColor,
                          selected: _filter == _CierreFilter.pendientes,
                          onTap: () => setState(
                              () => _filter = _CierreFilter.pendientes),
                        ),
                        SummaryCard(
                          compact: true,
                          title: 'Entregadas',
                          value: entregadas.toString(),
                          icon: AppTheme.iconEntregadas,
                          color: AppTheme.entregadoColor,
                          selected: _filter == _CierreFilter.entregadas,
                          onTap: () => setState(
                              () => _filter = _CierreFilter.entregadas),
                        ),
                        SummaryCard(
                          compact: true,
                          title: 'No entregadas',
                          value: noEntregadas.toString(),
                          icon: AppTheme.iconNoEntregadas,
                          color: AppTheme.noEntregadoColor,
                          selected: _filter == _CierreFilter.noEntregadas,
                          onTap: () => setState(
                              () => _filter = _CierreFilter.noEntregadas),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      listTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (scoped.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No hay entregas en el período seleccionado.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    else if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _filter == _CierreFilter.pendientes
                              ? 'No tenés pendientes en el período.'
                              : _filter == _CierreFilter.entregadas
                                  ? 'No tenés entregadas en el período.'
                                  : _filter == _CierreFilter.noEntregadas
                                      ? 'No tenés no entregadas en el período.'
                                      : 'No hay entregas en el período.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    else
                      ...filtered.map(
                        (d) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(d.nombre),
                            subtitle: Text(
                              d.estado == DeliveryState.noEntregado &&
                                      (d.motivoNoEntrega ?? '').trim().isNotEmpty
                                  ? '${d.direccion}\nMotivo: ${(d.motivoNoEntrega ?? '').trim()}'
                                  : d.direccion,
                            ),
                            trailing: Chip(
                              avatar: Icon(
                                AppTheme.iconFor(d.estado),
                                color: AppTheme.colorFor(d.estado),
                                size: 18,
                              ),
                              label: Text(d.estado.label),
                              backgroundColor:
                                  AppTheme.backgroundColorFor(d.estado),
                            ),
                            onTap: () => context
                                .push(AppRoutes.deliveryDetailPath(d.id)),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}
