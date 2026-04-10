import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart' as app_date;
import '../../../core/widgets/summary_card.dart';
import '../../delivery/data/delivery_repository.dart';
import '../../delivery/domain/delivery.dart';
import '../../delivery/domain/delivery_state.dart';

/// Filtro para la lista del cierre diario (null = todas).
enum _CierreFilter { all, pendientes, entregadas, noEntregadas }

class CierreDiarioScreen extends StatefulWidget {
  const CierreDiarioScreen({super.key});

  @override
  State<CierreDiarioScreen> createState() => _CierreDiarioScreenState();
}

class _CierreDiarioScreenState extends State<CierreDiarioScreen> {
  _CierreFilter _filter = _CierreFilter.pendientes;

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.currentUser?.uid ?? '';
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
                final todayRange = app_date.AppDateUtils.todayRange;
                final today = all.where((d) =>
                    app_date.AppDateUtils.isInRange(
                        d.fechaEscaneo, todayRange.$1, todayRange.$2)).toList();
                final total = today.length;
                final pendientes = today
                    .where((d) => d.estado == DeliveryState.pendiente)
                    .length;
                final entregadas = today
                    .where((d) => d.estado == DeliveryState.entregado)
                    .length;
                final noEntregadas = today
                    .where((d) => d.estado == DeliveryState.noEntregado)
                    .length;

                final filtered = today.where((d) {
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
                    listTitle = 'Entregas del día';
                    break;
                  case _CierreFilter.pendientes:
                    listTitle = 'Pendientes del día';
                    break;
                  case _CierreFilter.entregadas:
                    listTitle = 'Entregadas del día';
                    break;
                  case _CierreFilter.noEntregadas:
                    listTitle = 'No entregadas del día';
                    break;
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 240,
                          child: SummaryCard(
                            title: 'Total hoy',
                            value: total.toString(),
                            icon: AppTheme.iconTotal,
                            selected: _filter == _CierreFilter.all,
                            onTap: () =>
                                setState(() => _filter = _CierreFilter.all),
                          ),
                        ),
                        SizedBox(
                          width: 240,
                          child: SummaryCard(
                            title: 'Pendientes',
                            value: pendientes.toString(),
                            icon: AppTheme.iconPendientes,
                            color: AppTheme.pendienteColor,
                            selected: _filter == _CierreFilter.pendientes,
                            onTap: () => setState(
                                () => _filter = _CierreFilter.pendientes),
                          ),
                        ),
                        SizedBox(
                          width: 240,
                          child: SummaryCard(
                            title: 'Entregadas',
                            value: entregadas.toString(),
                            icon: AppTheme.iconEntregadas,
                            color: AppTheme.entregadoColor,
                            selected: _filter == _CierreFilter.entregadas,
                            onTap: () => setState(
                                () => _filter = _CierreFilter.entregadas),
                          ),
                        ),
                        SizedBox(
                          width: 240,
                          child: SummaryCard(
                            title: 'No entregadas',
                            value: noEntregadas.toString(),
                            icon: AppTheme.iconNoEntregadas,
                            color: AppTheme.noEntregadoColor,
                            selected: _filter == _CierreFilter.noEntregadas,
                            onTap: () => setState(
                                () => _filter = _CierreFilter.noEntregadas),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      listTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _filter == _CierreFilter.pendientes
                              ? 'No tenés pendientes de hoy.'
                              : _filter == _CierreFilter.entregadas
                                  ? 'No tenés entregadas de hoy.'
                                  : _filter == _CierreFilter.noEntregadas
                                      ? 'No tenés no entregadas de hoy.'
                                      : 'No hay entregas de hoy.',
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
