import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/driver/driver_session_maintenance.dart';
import '../../../core/layout/app_breakpoints.dart';
import '../../../core/prefs_keys.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/driver_delivery_visibility.dart';
import '../../../core/widgets/summary_card.dart';
import '../data/delivery_repository.dart';
import '../domain/delivery.dart';
import '../domain/delivery_state.dart';

/// Filtro de estado para el listado (null = todas).
enum _ListFilter { all, pendientes, entregadas, noEntregadas }

class DeliveryListScreen extends StatefulWidget {
  const DeliveryListScreen({super.key});

  @override
  State<DeliveryListScreen> createState() => _DeliveryListScreenState();
}

class _DeliveryListScreenState extends State<DeliveryListScreen> {
  _ListFilter _filter = _ListFilter.all;
  bool _compact = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(
          () => _compact = p.getBool(PrefsKeys.driverListCompact) ?? false,
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DriverSessionMaintenance.runIfNeeded(context);
    });
  }

  Future<void> _toggleCompact() async {
    final next = !_compact;
    setState(() => _compact = next);
    final p = await SharedPreferences.getInstance();
    await p.setBool(PrefsKeys.driverListCompact, next);
  }

  @override
  Widget build(BuildContext context) {
    final conductorId = AuthService.instance.currentUser?.uid ?? '';
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entregas cargadas'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: _compact ? 'Vista amplia' : 'Vista compacta',
            icon: Icon(
              _compact ? Icons.view_agenda_outlined : Icons.grid_view_outlined,
            ),
            onPressed: _toggleCompact,
          ),
        ],
      ),
      body: conductorId.isEmpty
          ? const Center(child: Text('Iniciá sesión para ver tus entregas.'))
          : StreamBuilder<List<Delivery>>(
              stream: DeliveryRepository.instance
                  .watchDeliveriesByDriver(conductorId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snapshot.data ?? [];
                final visible =
                    DriverDeliveryVisibility.filterForDailyDriverList(list);
                if (visible.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        list.isEmpty
                            ? 'Aún no tenés entregas cargadas.'
                            : 'No hay entregas para mostrar ahora. Las ya '
                                'entregadas en días anteriores se ocultan al '
                                'cambiar el día.',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final total = visible.length;
                final pendientes = visible
                    .where((d) => d.estado == DeliveryState.pendiente)
                    .length;
                final entregadas = visible
                    .where((d) => d.estado == DeliveryState.entregado)
                    .length;
                final noEntregadas = visible
                    .where((d) => d.estado == DeliveryState.noEntregado)
                    .length;

                final filtered = visible.where((d) {
                  switch (_filter) {
                    case _ListFilter.all:
                      return true;
                    case _ListFilter.pendientes:
                      return d.estado == DeliveryState.pendiente;
                    case _ListFilter.entregadas:
                      return d.estado == DeliveryState.entregado;
                    case _ListFilter.noEntregadas:
                      return d.estado == DeliveryState.noEntregado;
                  }
                }).toList();

                final screenW = MediaQuery.sizeOf(context).width;
                final narrow = screenW < AppBreakpoints.narrowScreenWidth;
                final pad = _compact ? (narrow ? 6.0 : 8.0) : (narrow ? 12.0 : 16.0);
                final cardBottom = _compact ? 4.0 : 12.0;

                return ListView(
                  padding: EdgeInsets.all(pad),
                  children: [
                    SummaryCardsGrid(
                      compact: _compact,
                      children: [
                        SummaryCard(
                          compact: _compact,
                          title: 'Total',
                          value: total.toString(),
                          icon: AppTheme.iconTotal,
                          selected: _filter == _ListFilter.all,
                          onTap: () =>
                              setState(() => _filter = _ListFilter.all),
                        ),
                        SummaryCard(
                          compact: _compact,
                          title: 'Pendientes',
                          value: pendientes.toString(),
                          icon: AppTheme.iconPendientes,
                          color: AppTheme.pendienteColor,
                          selected: _filter == _ListFilter.pendientes,
                          onTap: () => setState(
                              () => _filter = _ListFilter.pendientes),
                        ),
                        SummaryCard(
                          compact: _compact,
                          title: 'Entregadas',
                          value: entregadas.toString(),
                          icon: AppTheme.iconEntregadas,
                          color: AppTheme.entregadoColor,
                          selected: _filter == _ListFilter.entregadas,
                          onTap: () => setState(
                              () => _filter = _ListFilter.entregadas),
                        ),
                        SummaryCard(
                          compact: _compact,
                          title: 'No entregadas',
                          value: noEntregadas.toString(),
                          icon: AppTheme.iconNoEntregadas,
                          color: AppTheme.noEntregadoColor,
                          selected: _filter == _ListFilter.noEntregadas,
                          onTap: () => setState(
                              () => _filter = _ListFilter.noEntregadas),
                        ),
                      ],
                    ),
                    SizedBox(height: _compact ? 8 : 12),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _filter == _ListFilter.all
                              ? 'No hay entregas.'
                              : _filter == _ListFilter.pendientes
                                  ? 'No hay pendientes.'
                                  : _filter == _ListFilter.entregadas
                                      ? 'No hay entregadas.'
                                      : 'No hay no entregadas.',
                          style: theme.textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ...filtered.map(
                        (d) => Card(
                          margin: EdgeInsets.only(bottom: cardBottom),
                          child: ListTile(
                            dense: _compact,
                            visualDensity: _compact
                                ? VisualDensity.compact
                                : VisualDensity.standard,
                            minVerticalPadding:
                                _compact ? 0 : kMinInteractiveDimension / 2,
                            title: Text(
                              d.nombre,
                              maxLines: _compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: _compact
                                  ? theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    )
                                  : theme.textTheme.titleMedium,
                            ),
                            subtitle: Text(
                              d.estado == DeliveryState.noEntregado &&
                                      (d.motivoNoEntrega ?? '')
                                          .trim()
                                          .isNotEmpty
                                  ? '${d.direccion}\nMotivo: ${(d.motivoNoEntrega ?? '').trim()}'
                                  : d.direccion,
                              maxLines: _compact ? 2 : 4,
                              overflow: TextOverflow.ellipsis,
                              style: _compact
                                  ? theme.textTheme.bodySmall
                                  : null,
                            ),
                            trailing: _compact
                                ? Icon(
                                    AppTheme.iconFor(d.estado),
                                    color: AppTheme.colorFor(d.estado),
                                    size: 20,
                                  )
                                : Chip(
                                    avatar: Icon(
                                      AppTheme.iconFor(d.estado),
                                      color: AppTheme.colorFor(d.estado),
                                      size: 18,
                                    ),
                                    label: Text(d.estado.label),
                                    backgroundColor:
                                        AppTheme.backgroundColorFor(d.estado),
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
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
