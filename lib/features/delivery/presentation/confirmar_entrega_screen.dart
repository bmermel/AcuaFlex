import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_breakpoints.dart';
import '../../../core/debug_delivery_log.dart';
import '../../../core/utils/driver_location.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../core/auth/auth_service.dart';
import '../data/delivery_repository.dart';
import '../domain/delivery.dart';
import '../domain/delivery_state.dart';
import 'firma_entrega_screen.dart';
import 'no_entregado_dialog.dart';

/// Opciones para relación con el destinatario.
const List<String> _opcionesRelacion = [
  'Titular',
  'Familiar',
  'Vecino',
  'Otro',
];

class ConfirmarEntregaScreen extends StatelessWidget {
  const ConfirmarEntregaScreen({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Delivery?>(
      future: DeliveryRepository.instance.getDeliveryById(deliveryId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Confirmar entrega'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final delivery = snapshot.data;
        if (delivery == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Confirmar entrega'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: Center(child: Text('No se encontró la entrega: $deliveryId')),
          );
        }
        if (delivery.estado == DeliveryState.entregado) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Confirmar entrega'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: const Center(
              child: Text('Esta entrega ya está marcada como entregada.'),
            ),
          );
        }
        // noEntregado es reversible: se muestra el mismo formulario para completar como entregado.
        return _ConfirmarForm(delivery: delivery);
      },
    );
  }
}

class _ConfirmarForm extends StatefulWidget {
  const _ConfirmarForm({required this.delivery});

  final Delivery delivery;

  @override
  State<_ConfirmarForm> createState() => _ConfirmarFormState();
}

class _ConfirmarFormState extends State<_ConfirmarForm> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _dniController = TextEditingController();
  String? _relacion;
  String? _firmaBase64;
  DateTime? _fechaFirma;
  bool _saving = false;
  bool _signing = false;
  /// True solo tras confirmar entrega con éxito (no al volver atrás).
  bool _confirmedExit = false;
  /// True si se cerró la pantalla tras guardar "no entregado" (evita limpieza errónea en dispose).
  bool _closedByNoEntregadoFlow = false;

  @override
  void initState() {
    super.initState();
    _nombreController.text = widget.delivery.nombreRecibe ?? '';
    _dniController.text = widget.delivery.dniRecibe ?? '';
    _relacion = widget.delivery.relacionRecibe;
    if (_relacion != null && !_opcionesRelacion.contains(_relacion)) {
      _relacion = 'Otro';
    }
    _firmaBase64 = widget.delivery.firmaBase64;
    _fechaFirma = widget.delivery.fechaFirma;
  }

  @override
  void dispose() {
    // Evitar firmas guardadas en BD sin confirmar (p. ej. datos viejos o bug previo).
    if (!_confirmedExit &&
        !_closedByNoEntregadoFlow &&
        widget.delivery.estado == DeliveryState.pendiente &&
        widget.delivery.firmaBase64 != null &&
        widget.delivery.firmaBase64!.trim().isNotEmpty) {
      DeliveryRepository.instance
          .updateDelivery(
            widget.delivery.copyWith(clearFirma: true),
          )
          .catchError((_) {});
    }
    _nombreController.dispose();
    _dniController.dispose();
    super.dispose();
  }

  Future<void> _abrirFirma() async {
    if (_signing || _saving) return;
    setState(() => _signing = true);
    try {
      final base64Png = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const FirmaEntregaScreen(),
        ),
      );
      if (!mounted) return;
      if (base64Png == null || base64Png.trim().isEmpty) return;

      final now = DateTime.now();
      setState(() {
        _firmaBase64 = base64Png;
        _fechaFirma = now;
      });
      // La firma queda solo en memoria hasta "Confirmar entrega"; no persistir aquí.
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  Future<void> _marcarNoEntregado() async {
    if (_saving) return;
    final result = await showNoEntregadoDialog(context);
    if (result == null || result.motivo.trim().isEmpty) return;

    setState(() => _saving = true);
    try {
      final pos = await tryCaptureDriverLocation();
      final fechaNoEntrega = DateTime.now();
      final updatedBase = widget.delivery.copyWith(
        estado: DeliveryState.noEntregado,
        motivoNoEntrega: result.motivo.trim(),
        fechaNoEntrega: fechaNoEntrega,
        cierreLatitud: pos?.lat,
        cierreLongitud: pos?.lng,
        clearFirma: true,
      );
      // 1) Guardar siempre estado/motivo/fecha. Esto evita que un fallo de Storage
      // deje la entrega en un estado "no guardado".
      await DeliveryRepository.instance.updateDelivery(updatedBase);
      deliveryDebugLog(
        'confirmar_entrega_screen._marcarNoEntregado',
        'saved base noEntregado (without evidence)',
        data: {
          'deliveryId': widget.delivery.id,
          'motivo': result.motivo.trim(),
          'fechaNoEntrega': fechaNoEntrega.toIso8601String(),
        },
      );

      // 2) Intentar subir fotos (opcional) y, si sale bien, persistir URLs.
      if (result.fotos.isNotEmpty) {
        try {
          final uid = AuthService.instance.currentUser?.uid ?? '';
          await DeliveryRepository.instance.replaceNoEntregadoEvidences(
            deliveryId: widget.delivery.id,
            fotos: result.fotos
                .map((p) => (file: p.file, type: p.type))
                .toList(),
            createdAt: DateTime.now(),
            uploadedBy: uid,
          );
          deliveryDebugLog(
            'confirmar_entrega_screen._marcarNoEntregado',
            'evidence saved in firestore subcollection',
            data: {
              'deliveryId': widget.delivery.id,
              'count': result.fotos.length,
            },
          );
        } catch (e, st) {
          deliveryDebugLog(
            'confirmar_entrega_screen._marcarNoEntregado',
            'evidence save FAILED',
            data: {
              'deliveryId': widget.delivery.id,
              'error': e.toString(),
              'stackTrace': st.toString().split('\n').take(3).join(' '),
            },
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Se guardó el estado, pero no se pudieron guardar las fotos: ${e.toString().split('\n').first}',
                ),
                backgroundColor: Theme.of(context).colorScheme.error,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }

      if (!mounted) return;
      _closedByNoEntregadoFlow = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entrega marcada como NO ENTREGADA.'),
          backgroundColor: AppTheme.pendienteColor,
        ),
      );
      context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No se pudo guardar. Intentá de nuevo.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _confirmar() async {
    if (!_formKey.currentState!.validate()) return;
    final nombre = _nombreController.text.trim();
    final dni = _dniController.text.trim();
    final relacion = _relacion;
    if (nombre.isEmpty || dni.isEmpty || relacion == null || relacion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Completá nombre, DNI y relación.'),
          backgroundColor: AppTheme.pendienteColor,
        ),
      );
      return;
    }
    if (_firmaBase64 == null || _firmaBase64!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Firmá el receptor antes de confirmar.'),
          backgroundColor: AppTheme.pendienteColor,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final pos = await tryCaptureDriverLocation();
      final fechaFirma = _fechaFirma ?? DateTime.now();
      final updated = widget.delivery.copyWith(
        estado: DeliveryState.entregado,
        fechaEntrega: DateTime.now(),
        nombreRecibe: nombre,
        dniRecibe: dni,
        relacionRecibe: relacion,
        firmaBase64: _firmaBase64,
        fechaFirma: fechaFirma,
        cierreLatitud: pos?.lat,
        cierreLongitud: pos?.lng,
      );
      await DeliveryRepository.instance.updateDelivery(updated);
      if (!mounted) return;
      _confirmedExit = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Entrega confirmada.'),
          backgroundColor: AppTheme.entregadoColor,
        ),
      );
      context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No se pudo guardar. Intentá de nuevo.'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final delivery = widget.delivery;
    final screenW = MediaQuery.sizeOf(context).width;
    final hPad = screenW < AppBreakpoints.narrowScreenWidth ? 12.0 : 20.0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirmar entrega'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _saving ? null : () => context.pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
              children: [
            Text(
              'Datos de quien recibe',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Entrega a: ${delivery.nombre} · ${delivery.direccion}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nombreController,
              decoration: const InputDecoration(
                labelText: 'Nombre de quien recibe',
                hintText: 'Ej. Juan Pérez',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Ingresá el nombre de quien recibe';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _dniController,
              decoration: const InputDecoration(
                labelText: 'DNI de quien recibe',
                hintText: 'Ej. 12345678',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Ingresá el DNI de quien recibe';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Relación con el destinatario',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _opcionesRelacion.map((op) {
                final selected = _relacion == op;
                return ChoiceChip(
                  label: Text(op),
                  selected: selected,
                  onSelected: (sel) {
                    if (sel) setState(() => _relacion = op);
                  },
                  showCheckmark: true,
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text(
              'Firma del receptor',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            if (_firmaBase64 != null && _firmaBase64!.trim().isNotEmpty) ...[
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    base64Decode(_firmaBase64!),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Chip(
                avatar: Icon(Icons.verified, size: 18),
                label: Text('Firma cargada'),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _signing || _saving ? null : _abrirFirma,
                icon: const Icon(Icons.edit_document),
                label: Text(
                  _signing ? 'Abriendo firma...' : 'Firmar',
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: _saving ? null : _marcarNoEntregado,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text(
                  'No entregado',
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _confirmar,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(
                  _saving ? 'Guardando...' : 'Confirmar entrega',
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
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
