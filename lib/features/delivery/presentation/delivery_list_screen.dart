import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    final conductorId = AuthService.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entregas cargadas'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
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
                if (list.isEmpty) {
                  return const Center(
                    child: Text('Aún no tenés entregas cargadas.'),
                  );
                }
                final total = list.length;
                final pendientes = list
                    .where((d) => d.estado == DeliveryState.pendiente)
                    .length;
                final entregadas = list
                    .where((d) => d.estado == DeliveryState.entregado)
                    .length;
                final noEntregadas = list
                    .where((d) => d.estado == DeliveryState.noEntregado)
                    .length;

                final filtered = list.where((d) {
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
                            title: 'Total',
                            value: total.toString(),
                            icon: AppTheme.iconTotal,
                            selected: _filter == _ListFilter.all,
                            onTap: () =>
                                setState(() => _filter = _ListFilter.all),
                          ),
                        ),
                        SizedBox(
                          width: 240,
                          child: SummaryCard(
                            title: 'Pendientes',
                            value: pendientes.toString(),
                            icon: AppTheme.iconPendientes,
                            color: AppTheme.pendienteColor,
                            selected: _filter == _ListFilter.pendientes,
                            onTap: () => setState(
                                () => _filter = _ListFilter.pendientes),
                          ),
                        ),
                        SizedBox(
                          width: 240,
                          child: SummaryCard(
                            title: 'Entregadas',
                            value: entregadas.toString(),
                            icon: AppTheme.iconEntregadas,
                            color: AppTheme.entregadoColor,
                            selected: _filter == _ListFilter.entregadas,
                            onTap: () => setState(
                                () => _filter = _ListFilter.entregadas),
                          ),
                        ),
                        SizedBox(
                          width: 240,
                          child: SummaryCard(
                            title: 'No entregadas',
                            value: noEntregadas.toString(),
                            icon: AppTheme.iconNoEntregadas,
                            color: AppTheme.noEntregadoColor,
                            selected: _filter == _ListFilter.noEntregadas,
                            onTap: () => setState(
                                () => _filter = _ListFilter.noEntregadas),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
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
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ...filtered.map(
                        (d) => Card(
                          margin: const EdgeInsets.only(bottom: 12),
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
