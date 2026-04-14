import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/data/user_repository.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart' as app_date;
import '../../../core/widgets/summary_card.dart';
import '../../delivery/data/delivery_repository.dart';
import '../../delivery/domain/delivery.dart';
import '../../delivery/domain/delivery_state.dart';
import '../../delivery/presentation/manual_label_pdf.dart';

String _adminFormatDateTime(DateTime d) {
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Filtro por fecha en panel admin.
enum _AdminDateFilter { hoy, ayer, ultimos7 }

/// Filtro por estado en panel admin (sincronizado con tarjetas).
enum _AdminStateFilter { all, pendientes, entregadas, noEntregadas }

/// Ocultar el aviso de depósito (retiro/cambio) al pulsar la X; vuelve a verse pasado este tiempo o si expiró al abrir la app.
const Duration _kRetiroBannerSnooze = Duration(hours: 4);

const String _kPrefsRetiroBannerSnoozeUntilMs =
    'admin_retiro_banner_snooze_until_ms';

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

  /// Entregas manuales seleccionadas para imprimir etiquetas (PDF 8 por hoja).
  final Set<String> _selectedLabelIds = {};

  /// Último snapshot del stream (para imprimir desde el AppBar con los mismos filtros).
  List<Delivery>? _latestDeliveries;

  /// Búsqueda en tiempo real sobre la lista ya filtrada (fecha, conductor, estado).
  final TextEditingController _searchController = TextEditingController();

  /// Si no es null y [DateTime.now] es anterior, el banner verde de depósito no se muestra (snooze por la X).
  DateTime? _retiroBannerSnoozeUntil;

  @override
  void initState() {
    super.initState();
    _loadRetiroBannerSnooze();
    _checkAccess();
  }

  Future<void> _loadRetiroBannerSnooze() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_kPrefsRetiroBannerSnoozeUntilMs);
      if (!mounted) return;
      if (ms == null) {
        setState(() => _retiroBannerSnoozeUntil = null);
        return;
      }
      final until = DateTime.fromMillisecondsSinceEpoch(ms);
      if (!until.isAfter(DateTime.now())) {
        await prefs.remove(_kPrefsRetiroBannerSnoozeUntilMs);
        if (!mounted) return;
        setState(() => _retiroBannerSnoozeUntil = null);
        return;
      }
      setState(() => _retiroBannerSnoozeUntil = until);
    } catch (_) {
      if (mounted) setState(() => _retiroBannerSnoozeUntil = null);
    }
  }

  Future<void> _snoozeRetiroBanner() async {
    final until = DateTime.now().add(_kRetiroBannerSnooze);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _kPrefsRetiroBannerSnoozeUntilMs,
        until.millisecondsSinceEpoch,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() => _retiroBannerSnoozeUntil = until);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Aviso oculto unas horas. Volvé a verlo si sigue pendiente.',
        ),
        backgroundColor: AppTheme.adminEntregadoColor,
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      map[u.uid] = UserRepository.driverDisplayLabel(u);
      ids.add(u.uid);
    }
    ids.sort((a, b) => (map[a] ?? a).compareTo(map[b] ?? b));
    setState(() {
      _conductorLabels = map;
      _allConductorIds = ids;
    });
  }

  /// Etiqueta para mostrar en UI; valor interno sigue siendo uid.
  String _conductorDisplay(String uid) {
    if (uid.trim().isEmpty) return 'Sin asignar';
    return _conductorLabels[uid] ?? UserRepository.uidFallbackLabel(uid);
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
          backgroundColor: AppTheme.adminEntregadoColor,
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

  /// Marca como vistos los avisos de retiro/cambio pendientes (Firestore).
  Future<void> _markAllRetiroCambioAvisosLeidos(List<Delivery> pendientes) async {
    final messenger = ScaffoldMessenger.of(context);
    for (final d in pendientes) {
      try {
        await DeliveryRepository.instance.updateDelivery(
          d.copyWith(adminAvisoRetiroCambioLeido: true),
        );
      } catch (_) {
        // Continuar con el resto
      }
    }
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Avisos de retiro/cambio marcados como vistos.'),
        backgroundColor: AppTheme.adminEntregadoColor,
      ),
    );
  }

  /// Pedido / factura / referencia para el aviso de depósito.
  String _adminDeliveryRefLine(Delivery d) {
    return d.documentRefForBadge ?? d.detailHeaderPrimaryTitle;
  }

  String _retiroCambioIdsSummary(List<Delivery> list) {
    if (list.isEmpty) return '';
    final refs = list.map(_adminDeliveryRefLine).toList();
    if (refs.length <= 4) return refs.join(', ');
    return '${refs.take(4).join(', ')} (+${refs.length - 4})';
  }

  /// Lista detallada: marcar de a uno o todos.
  void _showRetiroCambioListaDialog(List<Delivery> initial) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final local = List<Delivery>.from(initial);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final theme = Theme.of(ctx);
            final screenW = MediaQuery.sizeOf(ctx).width;
            // Mismo “tamaño teléfono” en web y mobile: ancho acotado, centrado.
            final maxDialogW = math.min(360.0, screenW - 32);
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxDialogW,
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
                ),
                child: Material(
                  color: theme.colorScheme.surface,
                  elevation: 6,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 8),
                          child: Text(
                            'Retiros / cambios en depósito',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (local.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No hay pendientes.',
                              style: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 360),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: local.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: theme.dividerColor),
                              itemBuilder: (context, i) {
                                final d = local[i];
                                final ref = _adminDeliveryRefLine(d);
                                final subtitle =
                                    '${DeliverySourceType.label(d.sourceType)} · ${d.nombre}';
                                return ListTile(
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 0,
                                    horizontal: 4,
                                  ),
                                  title: Text(
                                    ref,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    subtitle,
                                    style: theme.textTheme.bodySmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Marcar como visto',
                                    icon: Icon(
                                      Icons.task_alt_rounded,
                                      color: theme.colorScheme.primary,
                                      size: 22,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
                                    onPressed: () async {
                                      try {
                                        await DeliveryRepository.instance
                                            .updateDelivery(
                                          d.copyWith(
                                            adminAvisoRetiroCambioLeido: true,
                                          ),
                                        );
                                        setDialogState(() {
                                          local.removeWhere(
                                              (x) => x.id == d.id);
                                        });
                                        scaffoldMessenger.showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Marcado como visto.',
                                            ),
                                            backgroundColor:
                                                AppTheme.adminEntregadoColor,
                                          ),
                                        );
                                        if (local.isEmpty && ctx.mounted) {
                                          Navigator.of(ctx).pop();
                                        }
                                      } catch (e) {
                                        scaffoldMessenger.showSnackBar(
                                          SnackBar(
                                            content: Text('Error: $e'),
                                            backgroundColor:
                                                theme.colorScheme.error,
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Cerrar'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton.tonal(
                              onPressed: local.isEmpty
                                  ? null
                                  : () async {
                                      await _markAllRetiroCambioAvisosLeidos(
                                        List<Delivery>.from(local),
                                      );
                                      if (ctx.mounted) Navigator.of(ctx).pop();
                                    },
                              child: const Text('Todos'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
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
          backgroundColor: AppTheme.adminEntregadoColor,
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

  /// Texto agregado en minúsculas para buscar en nombre, dirección, documentos y datos relacionados.
  String _adminSearchHaystack(Delivery d) {
    final parts = <String>[
      d.nombre,
      if ((d.nombreRecibe ?? '').trim().isNotEmpty) d.nombreRecibe!,
      if ((d.relacionRecibe ?? '').trim().isNotEmpty) d.relacionRecibe!,
      if ((d.dniRecibe ?? '').trim().isNotEmpty) d.dniRecibe!,
      d.direccion,
      if ((d.direccionCompleta ?? '').trim().isNotEmpty) d.direccionCompleta!,
      if ((d.localidad ?? '').trim().isNotEmpty) d.localidad!,
      if ((d.provincia ?? '').trim().isNotEmpty) d.provincia!,
      if ((d.codigoPostal ?? '').trim().isNotEmpty) d.codigoPostal!,
      d.telefono,
      d.dni,
      d.observaciones,
      if ((d.orderId ?? '').trim().isNotEmpty) ...[
        d.orderId!,
        Delivery.formatOrderIdForDisplay(d.orderId!),
      ],
      if ((d.sourceNumber ?? '').trim().isNotEmpty) d.sourceNumber!,
      d.sourceType,
      DeliverySourceType.label(d.sourceType),
      if (d.createdManually &&
          (d.sourceNumber ?? '').trim().isNotEmpty) ...[
        Delivery.manualOrderId(d.sourceType, d.sourceNumber!.trim()),
      ],
      _conductorDisplay(d.conductorId),
      if ((d.motivoNoEntrega ?? '').trim().isNotEmpty) d.motivoNoEntrega!,
    ];
    return parts.join(' ').toLowerCase();
  }

  /// Varias palabras: deben aparecer todas (en cualquier campo).
  bool _deliveryMatchesSearchTokens(Delivery d, List<String> tokensLower) {
    final hay = _adminSearchHaystack(d);
    return tokensLower.every(hay.contains);
  }

  List<Delivery> _applySearch(List<Delivery> list) {
    final raw = _searchController.text.trim();
    if (raw.isEmpty) return list;
    final tokens = raw
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return list;
    return list.where((d) => _deliveryMatchesSearchTokens(d, tokens)).toList();
  }

  /// Imprime etiquetas PDF para las seleccionadas que sigan en la lista filtrada actual.
  Future<void> _printSelectedManualLabels() async {
    final all = _latestDeliveries;
    if (all == null || _selectedLabelIds.isEmpty) return;
    final visible =
        _applySearch(_applyStateFilter(_applyDateAndConductor(all)));
    final list = visible
        .where((d) =>
            _selectedLabelIds.contains(d.id) && ManualLabelPdf.canPrintLabel(d))
        .toList();
    if (list.isEmpty) {
      if (mounted) {
        setState(_selectedLabelIds.clear);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No hay etiquetas para imprimir. Solo manuales que no estén entregadas.',
            ),
          ),
        );
      }
      return;
    }
    await ManualLabelPdf.printLabels(list);
    if (mounted) setState(_selectedLabelIds.clear);
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
          if (_selectedLabelIds.isNotEmpty)
            IconButton(
              icon: Badge(
                label: Text('${_selectedLabelIds.length}'),
                child: const Icon(Icons.print_outlined),
              ),
              tooltip: 'Imprimir etiquetas seleccionadas',
              onPressed: _printSelectedManualLabels,
            ),
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: 'Reportes',
            onPressed: () => context.push(AppRoutes.adminReports),
          ),
          IconButton(
            icon: const Icon(Icons.group_outlined),
            tooltip: 'Usuarios',
            onPressed: () => context.push(AppRoutes.adminUsers),
          ),
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
          _latestDeliveries = all;
          final pendingRetiroCambio =
              all.where((d) => d.needsAdminAvisoRetiroCambio).toList();

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

          // Lista visible: fecha + conductor + estado (+ búsqueda en vivo)
          final filtered = _applyStateFilter(byDateAndConductor);
          final displayed = _applySearch(filtered);

          // Dropdown: Todos + todos los conductores (desde Firestore); si aún no cargó, fallback a los que aparecen en entregas
          var conductorIds = _allConductorIds;
          if (conductorIds.isEmpty) {
            conductorIds = all.map((d) => d.conductorId).toSet().toList()
              ..sort((a, b) =>
                  (_conductorLabels[a] ?? a).compareTo(_conductorLabels[b] ?? b));
          }

          final screenW = MediaQuery.sizeOf(context).width;
          final narrow = screenW < 600;
          final hPad = narrow ? 12.0 : 24.0;
          final theme = Theme.of(context);
          final retiroOnSurface = theme.colorScheme.onSecondaryContainer;
          final retiroBodyStyle = theme.textTheme.bodyMedium?.copyWith(
            color: retiroOnSurface,
          );
          final retiroIdsLine = pendingRetiroCambio.isNotEmpty
              ? _retiroCambioIdsSummary(pendingRetiroCambio)
              : '';
          final retiroCount = pendingRetiroCambio.length;
          final showRetiroDepositBanner = pendingRetiroCambio.isNotEmpty &&
              (_retiroBannerSnoozeUntil == null ||
                  !DateTime.now().isBefore(_retiroBannerSnoozeUntil!));

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
                children: [
              if (showRetiroDepositBanner) ...[
                Material(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 40, 14),
                    child: narrow
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    color: retiroOnSurface,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Pedidos / referencias: $retiroIdsLine',
                                          style: retiroBodyStyle?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Hay $retiroCount envío(s) de retiro o cambio de producto por recibir en depósito. '
                                          'Abrí la lista para ver el detalle y marcar de a uno cuando lo recibas; '
                                          'o usá "Marcar todos" si ya están registrados.',
                                          style: retiroBodyStyle,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: () => _showRetiroCambioListaDialog(
                                  pendingRetiroCambio,
                                ),
                                child: const Text('Ver lista'),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.tonal(
                                onPressed: () => _markAllRetiroCambioAvisosLeidos(
                                  pendingRetiroCambio,
                                ),
                                child: const Text('Marcar todos como vistos'),
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                color: retiroOnSurface,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Pedidos / referencias: $retiroIdsLine',
                                      style: retiroBodyStyle?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Hay $retiroCount envío(s) de retiro o cambio de producto por recibir en depósito. '
                                      'Abrí la lista para ver el detalle y marcar de a uno cuando lo recibas; '
                                      'o usá "Marcar todos" si ya están registrados.',
                                      style: retiroBodyStyle,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _showRetiroCambioListaDialog(
                                      pendingRetiroCambio,
                                    ),
                                    child: const Text('Ver lista'),
                                  ),
                                  const SizedBox(height: 8),
                                  FilledButton.tonal(
                                    onPressed: () => _markAllRetiroCambioAvisosLeidos(
                                      pendingRetiroCambio,
                                    ),
                                    child: const Text('Marcar todos'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: IconButton(
                          onPressed: _snoozeRetiroBanner,
                          tooltip:
                              'Ocultar este aviso unas horas (se guarda en este dispositivo)',
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: retiroOnSurface.withValues(alpha: 0.85),
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 30,
                            minHeight: 30,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              SummaryCardsGrid(
                children: [
                  SummaryCard(
                    compact: true,
                    title: 'Total',
                    value: total.toString(),
                    icon: AppTheme.iconTotal,
                    selected: _stateFilter == _AdminStateFilter.all,
                    onTap: () => setState(
                        () => _stateFilter = _AdminStateFilter.all),
                  ),
                  SummaryCard(
                    compact: true,
                    title: 'Pendientes',
                    value: pendientes.toString(),
                    icon: AppTheme.iconPendientes,
                    color: AppTheme.adminPendienteColor,
                    selected:
                        _stateFilter == _AdminStateFilter.pendientes,
                    onTap: () => setState(
                        () => _stateFilter =
                            _AdminStateFilter.pendientes),
                  ),
                  SummaryCard(
                    compact: true,
                    title: 'Entregadas',
                    value: entregadas.toString(),
                    icon: AppTheme.iconEntregadas,
                    color: AppTheme.adminEntregadoColor,
                    selected:
                        _stateFilter == _AdminStateFilter.entregadas,
                    onTap: () => setState(
                        () => _stateFilter =
                            _AdminStateFilter.entregadas),
                  ),
                  SummaryCard(
                    compact: true,
                    title: 'No entregadas',
                    value: noEntregadas.toString(),
                    icon: AppTheme.iconNoEntregadas,
                    color: AppTheme.adminNoEntregadoColor,
                    selected:
                        _stateFilter == _AdminStateFilter.noEntregadas,
                    onTap: () => setState(
                        () => _stateFilter =
                            _AdminStateFilter.noEntregadas),
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _DateChip(
                            label: 'Hoy',
                            selected: _dateFilter == _AdminDateFilter.hoy,
                            onTap: () => setState(
                                () => _dateFilter = _AdminDateFilter.hoy),
                          ),
                          _DateChip(
                            label: 'Ayer',
                            selected: _dateFilter == _AdminDateFilter.ayer,
                            onTap: () => setState(
                                () => _dateFilter = _AdminDateFilter.ayer),
                          ),
                          _DateChip(
                            label: 'Últimos 7 días',
                            selected: _dateFilter ==
                                _AdminDateFilter.ultimos7,
                            onTap: () => setState(() =>
                                _dateFilter =
                                    _AdminDateFilter.ultimos7),
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
              if (displayed.any(ManualLabelPdf.canPrintLabel)) ...[
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      initiallyExpanded: false,
                      leading: Icon(
                        Icons.print_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(
                        'Imprimir etiquetas (A4)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      subtitle: Text(
                        'Manuales sin entregar · hasta 8 por hoja',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      childrenPadding: EdgeInsets.fromLTRB(
                        narrow ? 12 : 16,
                        0,
                        narrow ? 12 : 16,
                        12,
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _selectedLabelIds
                                      ..clear()
                                      ..addAll(displayed
                                          .where(ManualLabelPdf.canPrintLabel)
                                          .map((d) => d.id));
                                  });
                                },
                                icon: const Icon(Icons.checklist_outlined,
                                    size: 20),
                                label:
                                    const Text('Seleccionar manuales visibles'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    setState(_selectedLabelIds.clear),
                                child: const Text('Limpiar selección'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 16,
                              ),
                            ),
                            onPressed: _selectedLabelIds.isEmpty
                                ? null
                                : _printSelectedManualLabels,
                            icon: const Icon(Icons.print_outlined, size: 22),
                            label: Text(
                              _selectedLabelIds.isEmpty
                                  ? 'Imprimir'
                                  : 'Imprimir (${_selectedLabelIds.length})',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    decoration: InputDecoration(
                      hintText:
                          'Buscar: nombre, dirección, pedido, FC, OV, COT, RET, CAM, retiro, cambio…',
                      border: InputBorder.none,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              tooltip: 'Limpiar búsqueda',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (displayed.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    filtered.isEmpty
                        ? 'No hay entregas con los filtros seleccionados.'
                        : 'Ninguna entrega coincide con la búsqueda.'
                            ' Probá otras palabras o limpiá el filtro.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ...displayed.map(
                  (d) => _AdminDeliveryCard(
                    delivery: d,
                    narrow: narrow,
                    conductorLabel: _conductorDisplay(d.conductorId),
                    labelSelectionEnabled: ManualLabelPdf.canPrintLabel(d),
                    selectedForLabel: _selectedLabelIds.contains(d.id),
                    onToggleLabel: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedLabelIds.add(d.id);
                        } else {
                          _selectedLabelIds.remove(d.id);
                        }
                      });
                    },
                    onOpenDetail: () => context
                        .push(AppRoutes.deliveryDetailPath(d.id)),
                    onDelete: () => _confirmDeleteDelivery(context, d),
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

/// Tarjeta de entrega: en pantallas < 600 px el texto va en columna (legible en Android).
class _AdminDeliveryCard extends StatelessWidget {
  const _AdminDeliveryCard({
    required this.delivery,
    required this.narrow,
    required this.conductorLabel,
    required this.labelSelectionEnabled,
    required this.selectedForLabel,
    required this.onToggleLabel,
    required this.onOpenDetail,
    required this.onDelete,
  });

  final Delivery delivery;
  final bool narrow;
  final String conductorLabel;
  /// Etiquetas A4: solo manuales aún no entregadas.
  final bool labelSelectionEnabled;
  final bool selectedForLabel;
  final void Function(bool?) onToggleLabel;
  final VoidCallback onOpenDetail;
  final VoidCallback onDelete;

  /// Icono + nombre en negrita, sin fondo tipo chip.
  Widget _buildConductorRow(BuildContext context, {required bool alignEnd}) {
    final theme = Theme.of(context);
    final d = delivery;
    final isUnassigned = d.hasNoConductor;
    final color = isUnassigned
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;
    final text = Text(
      conductorLabel,
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: color,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
    );
    final icon = Icon(
      isUnassigned ? Icons.person_off_outlined : Icons.person_outline,
      size: 18,
      color: color,
    );
    if (alignEnd) {
      return Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: text,
            ),
          ],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        icon,
        const SizedBox(width: 6),
        Expanded(child: text),
      ],
    );
  }

  /// Badge pedido / FC / OV / etc.
  Widget _buildDocumentBadge(BuildContext context, {double maxWidth = 280}) {
    final theme = Theme.of(context);
    final ref = delivery.documentRefForBadge;
    if (ref == null) return const SizedBox.shrink();
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.38),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 15,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              ref,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Mobile: dirección y badge siempre en columna (badge debajo de la dirección).
  Widget _buildDireccionLineNarrow(BuildContext context) {
    final theme = Theme.of(context);
    final d = delivery;
    final ref = d.documentRefForBadge;
    final addrStyle = theme.textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(d.direccion, style: addrStyle),
        if (ref != null) ...[
          const SizedBox(height: 6),
          _buildDocumentBadge(context, maxWidth: 360),
        ],
      ],
    );
  }

  static const String _tooltipEtiquetaActiva =
      'Incluir esta entrega en el PDF de etiquetas A4';
  static const String _tooltipEtiquetaBloqueada =
      'Etiqueta A4 solo para pedidos manuales aún pendientes de entrega';

  Widget _labelCheckbox(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = labelSelectionEnabled;
    final checkbox = enabled
        ? CheckboxTheme(
            data: CheckboxThemeData(
              side: WidgetStateBorderSide.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return BorderSide.none;
                }
                return BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.65),
                  width: 2,
                );
              }),
            ),
            child: Checkbox(
              value: selectedForLabel,
              onChanged: onToggleLabel,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          )
        : Opacity(
            opacity: 0.45,
            child: CheckboxTheme(
              data: CheckboxThemeData(
                fillColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.9);
                  }
                  return null;
                }),
                side: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Checkbox(
                value: false,
                onChanged: null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          );

    return Tooltip(
      message: enabled ? _tooltipEtiquetaActiva : _tooltipEtiquetaBloqueada,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!enabled) ...[
            Icon(
              Icons.lock_outline,
              size: 17,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 2),
          ],
          checkbox,
        ],
      ),
    );
  }

  Widget _buildScanAndCierreLines(BuildContext context) {
    final theme = Theme.of(context);
    final d = delivery;
    final baseSmall = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final Widget cierreLine;
    if (d.estado == DeliveryState.pendiente) {
      cierreLine = Text.rich(
        TextSpan(
          style: baseSmall,
          children: [
            const TextSpan(text: 'Cierre: '),
            TextSpan(
              text: 'Pendiente',
              style: baseSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ),
      );
    } else if (d.estado == DeliveryState.entregado &&
        d.fechaEntrega != null) {
      cierreLine = Text(
        'Cierre (entregado): ${_adminFormatDateTime(d.fechaEntrega!)}',
        style: baseSmall,
      );
    } else if (d.estado == DeliveryState.noEntregado &&
        d.fechaNoEntrega != null) {
      cierreLine = Text(
        'Cierre (no entregado): ${_adminFormatDateTime(d.fechaNoEntrega!)}',
        style: baseSmall,
      );
    } else {
      cierreLine = Text(
        'Cierre: —',
        style: baseSmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Escaneo: ${_adminFormatDateTime(d.fechaEscaneo)}',
          style: baseSmall,
        ),
        const SizedBox(height: 2),
        cierreLine,
      ],
    );
  }

  Widget _estadoChip(BuildContext context) {
    final theme = Theme.of(context);
    final d = delivery;
    final pendiente = d.estado == DeliveryState.pendiente;
    return Chip(
      avatar: Icon(
        AppTheme.iconFor(d.estado),
        color: pendiente ? theme.colorScheme.error : AppTheme.adminColorFor(d.estado),
        size: 18,
      ),
      label: Text(
        d.estado.label,
        style: pendiente
            ? theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              )
            : theme.textTheme.labelLarge,
      ),
      backgroundColor: AppTheme.adminBackgroundColorFor(d.estado),
      side: pendiente
          ? BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5))
          : null,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = delivery;
    final motivo = (d.motivoNoEntrega ?? '').trim();
    final showMotivo =
        d.estado == DeliveryState.noEntregado && motivo.isNotEmpty;

    if (narrow) {
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpenDetail,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _labelCheckbox(context),
                    Expanded(
                      child: Text(
                        d.nombre,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.delete_outline,
                        color: theme.colorScheme.error,
                      ),
                      tooltip: 'Borrar entrega',
                      onPressed: onDelete,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildDireccionLineNarrow(context),
                const SizedBox(height: 8),
                _buildScanAndCierreLines(context),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _estadoChip(context),
                    _buildConductorRow(context, alignEnd: false),
                  ],
                ),
                if (showMotivo) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Motivo: $motivo',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          // ListView da altura ilimitada al hijo: sin esto, Row → Expanded → Center pide altura ∞.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4, top: 4),
                    child: _labelCheckbox(context),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        d.nombre,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        d.direccion,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 6),
                      _buildScanAndCierreLines(context),
                      if (showMotivo) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Motivo: $motivo',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _buildDocumentBadge(context, maxWidth: 300),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _estadoChip(context),
                      const SizedBox(height: 6),
                      _buildConductorRow(context, alignEnd: true),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                        ),
                        tooltip: 'Borrar entrega',
                        onPressed: onDelete,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
      backgroundColor: selected ? AppTheme.adminSelectedTint : null,
      side: BorderSide(
        color: selected
            ? theme.colorScheme.primary
            : AppTheme.adminBorderLight,
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
      backgroundColor: selected ? AppTheme.adminSelectedTint : null,
      side: BorderSide(
        color: selected
            ? theme.colorScheme.primary
            : AppTheme.adminBorderLight,
        width: selected ? 2 : 1,
      ),
    );
  }
}
