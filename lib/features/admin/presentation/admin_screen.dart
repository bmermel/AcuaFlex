import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/data/user_repository.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart' as app_date;
import '../../../core/widgets/summary_card.dart';
import '../../delivery/data/delivery_repository.dart';
import '../../delivery/domain/delivery.dart';
import '../../delivery/domain/delivery_state.dart';

/// Filtro por fecha en panel admin.
enum _AdminDateFilter { hoy, ayer, ultimos7 }

/// Filtro por estado en panel admin (sincronizado con tarjetas).
enum _AdminStateFilter { all, pendientes, entregadas, noEntregadas }

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool _isAdmin = false;
  bool _checked = false;

  /// uid -> etiqueta legible (usuario o fallback).
  Map<String, String> _conductorLabels = {};
  /// Todos los usuarios de Firestore (conductores disponibles para el dropdown).
  List<String> _allConductorIds = [];

  _AdminDateFilter _dateFilter = _AdminDateFilter.hoy;
  String? _selectedConductorId;
  _AdminStateFilter _stateFilter = _AdminStateFilter.all;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _checked = true);
      return;
    }
    final admin = await UserRepository.instance.isAdmin(uid);
    if (!mounted) return;
    setState(() {
      _isAdmin = admin;
      _checked = true;
    });
    if (admin) _loadConductorLabels();
  }

  /// Carga desde Firestore colección [users] solo usuarios con role = driver para el selector de conductor.
  /// Origen: solo Firestore users. Si un usuario existe en Authentication pero no tiene doc en users, no aparecerá.
  Future<void> _loadConductorLabels() async {
    final users = await UserRepository.instance.getAllUsers();
    if (kDebugMode) {
      // ignore: avoid_print
      print('[ADMIN] getAllUsers() trajo ${users.length} usuario(s) desde Firestore (colección users).');
      for (final u in users) {
        // ignore: avoid_print
        print('[ADMIN]   uid=${u.uid} email="${u.email}" role="${u.role}" isDriver=${u.isDriver} isAdmin=${u.isAdmin}');
      }
    }
    if (!mounted) return;
    final drivers = users.where((u) => u.isDriver).toList();
    final excluded = users.where((u) => !u.isDriver).toList();
    if (kDebugMode) {
      // ignore: avoid_print
      print('[ADMIN] Filtro role=driver: ${drivers.length} pasan, ${excluded.length} quedan afuera.');
      for (final u in excluded) {
        // ignore: avoid_print
        print('[ADMIN]   Excluido (no driver): uid=${u.uid} email="${u.email}" role="${u.role}"');
      }
      if (users.isEmpty) {
        // ignore: avoid_print
        print('[ADMIN] El dropdown se arma solo desde Firestore users. Si un usuario está en Authentication pero no tiene documento en la colección users, no aparecerá aquí.');
      }
    }
    if (!mounted) return;
    final map = <String, String>{};
    final ids = <String>[];
    for (final u in drivers) {
      map[u.uid] = _labelForUser(u);
      ids.add(u.uid);
    }
    ids.sort((a, b) => (map[a] ?? a).compareTo(map[b] ?? b));
    setState(() {
      _conductorLabels = map;
      _allConductorIds = ids;
    });
  }

  /// Label corto: parte antes de @ del email; si no hay email, fallback con uid.
  static String _labelForUser(AppUser u) {
    final short = AuthService.shortDisplayName(u.email);
    if (short.isNotEmpty) return short;
    if (u.uid.length <= 8) return 'Conductor (${u.uid})';
    return 'Conductor (…${u.uid.substring(u.uid.length - 6)})';
  }

  /// Etiqueta para mostrar en UI; valor interno sigue siendo uid.
  String _conductorDisplay(String uid) {
    return _conductorLabels[uid] ?? 'Conductor (…${uid.length >= 6 ? uid.substring(uid.length - 6) : uid})';
  }

  /// Botón atrás del AppBar: si hay stack para volver hace pop; si no, va a home (evita GoError "There is nothing to pop").
  void _onAdminBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ADMIN] canPop=false, navegando a home (evitar GoError: There is nothing to pop)');
      }
      context.go(AppRoutes.home);
    }
  }

  /// Diálogo de confirmación y ejecución de limpieza de duplicados manuales.
  Future<void> _showCleanupConfirm(BuildContext context, List<Delivery> all) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar duplicados manuales'),
        content: const SingleChildScrollView(
          child: Text(
            'Se buscarán orderIds con 2 o más entregas donde:\n'
            '• Al menos una tiene conductor asignado\n'
            '• Al menos una no tiene conductor\n\n'
            'En esos casos se eliminarán solo las que NO tienen conductor '
            'y se conservarán las que sí tienen.\n\n'
            'No se tocan entregas que estén solas ni grupos donde todas tengan o todas no tengan conductor.\n\n'
            '¿Ejecutar limpieza?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      final result = await DeliveryRepository.instance.cleanDuplicateManualWithoutConductor(all);
      if (!mounted) return;
      final affected = result['orderIdsAffected'] ?? 0;
      final deleted = result['documentsDeleted'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Limpieza hecha: $affected orderId(s) afectados, $deleted documento(s) eliminados.',
          ),
          backgroundColor: AppTheme.entregadoColor,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al limpiar: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Confirmación y borrado de una entrega puntual (solo admin).
  Future<void> _confirmDeleteDelivery(BuildContext context, Delivery d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar entrega'),
        content: Text(
          '¿Borrar esta entrega?\n\n${d.nombre}\n${d.direccion}\n\nSe eliminará de Firestore. '
          'Si tenía orderId, se actualizará delivery_keys para no dejar referencias inconsistentes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await DeliveryRepository.instance.deleteDeliveryAndCleanKey(d.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entrega borrada.'),
          backgroundColor: AppTheme.entregadoColor,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al borrar: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Filtra por fecha (fechaEscaneo) usando utilidades compartidas.
  List<Delivery> _filterByDate(List<Delivery> list) {
    switch (_dateFilter) {
      case _AdminDateFilter.hoy:
        final range = app_date.AppDateUtils.todayRange;
        return list
            .where((d) => app_date.AppDateUtils.isInRange(
                d.fechaEscaneo, range.$1, range.$2))
            .toList();
      case _AdminDateFilter.ayer:
        final range = app_date.AppDateUtils.yesterdayRange;
        return list
            .where((d) => app_date.AppDateUtils.isInRange(
                d.fechaEscaneo, range.$1, range.$2))
            .toList();
      case _AdminDateFilter.ultimos7:
        final start = app_date.AppDateUtils.last7DaysStart;
        return list
            .where((d) => !d.fechaEscaneo.isBefore(start))
            .toList();
    }
  }

  /// Orden: fecha → conductor → estado. Resumen usa fecha + conductor. Lista usa los tres.
  List<Delivery> _applyDateAndConductor(List<Delivery> list) {
    var result = _filterByDate(list);
    if (_selectedConductorId != null) {
      result =
          result.where((d) => d.conductorId == _selectedConductorId).toList();
    }
    return result;
  }

  List<Delivery> _applyStateFilter(List<Delivery> list) {
    switch (_stateFilter) {
      case _AdminStateFilter.all:
        return list;
      case _AdminStateFilter.pendientes:
        return list
            .where((d) => d.estado == DeliveryState.pendiente)
            .toList();
      case _AdminStateFilter.entregadas:
        return list
            .where((d) => d.estado == DeliveryState.entregado)
            .toList();
      case _AdminStateFilter.noEntregadas:
        return list
            .where((d) => d.estado == DeliveryState.noEntregado)
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Panel admin')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Panel admin'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _onAdminBack(context),
          ),
        ),
        body: const Center(
          child: Text('No tenés permisos de administrador.'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel admin'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _onAdminBack(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Registrar nuevo driver',
            onPressed: () => context.push(AppRoutes.registrarDriver),
          ),
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: 'Limpiar duplicados manuales',
            onPressed: () async {
              final list = await DeliveryRepository.instance.watchAllDeliveries().first;
              if (context.mounted) _showCleanupConfirm(context, list);
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Crear entrega manual',
            onPressed: () => context.push(AppRoutes.crearEntregaManual),
          ),
        ],
      ),
      body: StreamBuilder<List<Delivery>>(
        stream: DeliveryRepository.instance.watchAllDeliveries(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;

          // 1) Filtro por conductor (incluye fecha internamente)
          final byDateAndConductor = _applyDateAndConductor(all);

          // Resumen: contadores sobre fecha + conductor
          final total = byDateAndConductor.length;
          final pendientes = byDateAndConductor
              .where((d) => d.estado == DeliveryState.pendiente)
              .length;
          final entregadas = byDateAndConductor
              .where((d) => d.estado == DeliveryState.entregado)
              .length;
          final noEntregadas = byDateAndConductor
              .where((d) => d.estado == DeliveryState.noEntregado)
              .length;

          // Lista visible: fecha + conductor + estado
          final filtered = _applyStateFilter(byDateAndConductor);

          // Dropdown: Todos + todos los conductores (desde Firestore); si aún no cargó, fallback a los que aparecen en entregas
          var conductorIds = _allConductorIds;
          if (conductorIds.isEmpty) {
            conductorIds = all.map((d) => d.conductorId).toSet().toList()
              ..sort((a, b) =>
                  (_conductorLabels[a] ?? a).compareTo(_conductorLabels[b] ?? b));
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                children: [
              // Tarjetas de resumen primero (fecha + conductor; clickeables = estado)
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
                      selected: _stateFilter == _AdminStateFilter.all,
                      onTap: () => setState(
                          () => _stateFilter = _AdminStateFilter.all),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: SummaryCard(
                      title: 'Pendientes',
                      value: pendientes.toString(),
                      icon: AppTheme.iconPendientes,
                      color: AppTheme.pendienteColor,
                      selected:
                          _stateFilter == _AdminStateFilter.pendientes,
                      onTap: () => setState(
                          () => _stateFilter =
                              _AdminStateFilter.pendientes),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: SummaryCard(
                      title: 'Entregadas',
                      value: entregadas.toString(),
                      icon: AppTheme.iconEntregadas,
                      color: AppTheme.entregadoColor,
                      selected:
                          _stateFilter == _AdminStateFilter.entregadas,
                      onTap: () => setState(
                          () => _stateFilter =
                              _AdminStateFilter.entregadas),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: SummaryCard(
                      title: 'No entregadas',
                      value: noEntregadas.toString(),
                      icon: AppTheme.iconNoEntregadas,
                      color: AppTheme.noEntregadoColor,
                      selected:
                          _stateFilter == _AdminStateFilter.noEntregadas,
                      onTap: () => setState(
                          () => _stateFilter =
                              _AdminStateFilter.noEntregadas),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Filtros agrupados en una Card con secciones
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionLabel(title: 'Período'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _DateChip(
                              label: 'Hoy',
                              selected: _dateFilter == _AdminDateFilter.hoy,
                              onTap: () => setState(
                                  () => _dateFilter = _AdminDateFilter.hoy),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DateChip(
                              label: 'Ayer',
                              selected: _dateFilter == _AdminDateFilter.ayer,
                              onTap: () => setState(
                                  () => _dateFilter = _AdminDateFilter.ayer),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DateChip(
                              label: 'Últimos 7 días',
                              selected: _dateFilter ==
                                  _AdminDateFilter.ultimos7,
                              onTap: () => setState(() =>
                                  _dateFilter =
                                      _AdminDateFilter.ultimos7),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SectionLabel(title: 'Conductor'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        value: _selectedConductorId,
                        decoration: const InputDecoration(
                          labelText: 'Conductor',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Todos'),
                          ),
                          ...conductorIds.map(
                            (id) => DropdownMenuItem<String?>(
                              value: id,
                              child: Text(_conductorDisplay(id)),
                            ),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedConductorId = v),
                      ),
                      const SizedBox(height: 20),
                      _SectionLabel(title: 'Estado'),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _FilterChip(
                              label: 'Todas',
                              selected:
                                  _stateFilter == _AdminStateFilter.all,
                              onTap: () => setState(
                                  () => _stateFilter =
                                      _AdminStateFilter.all),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Pendientes',
                              selected: _stateFilter ==
                                  _AdminStateFilter.pendientes,
                              onTap: () => setState(() =>
                                  _stateFilter =
                                      _AdminStateFilter.pendientes),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Entregadas',
                              selected: _stateFilter ==
                                  _AdminStateFilter.entregadas,
                              onTap: () => setState(() =>
                                  _stateFilter =
                                      _AdminStateFilter.entregadas),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'No entregadas',
                              selected: _stateFilter ==
                                  _AdminStateFilter.noEntregadas,
                              onTap: () => setState(() =>
                                  _stateFilter =
                                      _AdminStateFilter.noEntregadas),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No hay entregas con los filtros seleccionados.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
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
                            ? '${d.direccion} · ${d.estado.label} · ${_conductorDisplay(d.conductorId)}\nMotivo: ${(d.motivoNoEntrega ?? '').trim()}'
                            : '${d.direccion} · ${d.estado.label} · ${_conductorDisplay(d.conductorId)}',
                      ),
                      subtitleTextStyle: Theme.of(context).textTheme.bodySmall,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Chip(
                            avatar: Icon(
                              AppTheme.iconFor(d.estado),
                              color: AppTheme.colorFor(d.estado),
                              size: 18,
                            ),
                            label: Text(d.estado.label),
                            backgroundColor:
                                AppTheme.backgroundColorFor(d.estado),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            tooltip: 'Borrar entrega',
                            onPressed: () => _confirmDeleteDelivery(context, d),
                          ),
                        ],
                      ),
                      onTap: () => context
                          .push(AppRoutes.deliveryDetailPath(d.id)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          );
        },
      ),
    );
  }
}

/// Título de sección dentro del panel de filtros.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: selected ? AppTheme.selectedTint : null,
      side: BorderSide(
        color: selected
            ? theme.colorScheme.primary
            : AppTheme.borderLight,
        width: selected ? 2 : 1,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) ...[
            Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
          ],
          Text(label),
        ],
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: selected ? AppTheme.selectedTint : null,
      side: BorderSide(
        color: selected
            ? theme.colorScheme.primary
            : AppTheme.borderLight,
        width: selected ? 2 : 1,
      ),
    );
  }
}
