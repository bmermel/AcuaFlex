import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_breakpoints.dart';
import '../../../core/data/user_repository.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../data/delivery_repository.dart';
import '../domain/delivery.dart';
import '../domain/delivery_state.dart';

/// Pantalla para que el admin cree una entrega manual (pedido web sin QR, FC, OV, COT, retiro, cambio).
class CrearEntregaManualScreen extends StatefulWidget {
  const CrearEntregaManualScreen({super.key});

  @override
  State<CrearEntregaManualScreen> createState() => _CrearEntregaManualScreenState();
}

class _CrearEntregaManualScreenState extends State<CrearEntregaManualScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sourceNumberController = TextEditingController();
  final _nombreController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _dniController = TextEditingController();
  final _direccionController = TextEditingController();
  final _localidadController = TextEditingController();
  final _observacionesController = TextEditingController();

  String _sourceType = DeliverySourceType.fc;
  String? _conductorId; // null o '' = sin asignar
  List<AppUser> _users = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final list = await UserRepository.instance.getAllUsers();
    if (mounted) setState(() => _users = list);
  }

  @override
  void dispose() {
    _sourceNumberController.dispose();
    _nombreController.dispose();
    _telefonoController.dispose();
    _dniController.dispose();
    _direccionController.dispose();
    _localidadController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final sourceNumber = _sourceNumberController.text.trim();
    if (sourceNumber.isEmpty) {
      setState(() => _error = _sourceType == DeliverySourceType.ped
          ? 'Ingresá el número de pedido.'
          : DeliverySourceType.isRetiroOCambio(_sourceType)
              ? 'Ingresá el número de retiro o cambio.'
              : 'Ingresá el número de documento.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });

    final String orderId;
    final String sourceNumberStored;
    if (_sourceType == DeliverySourceType.ped) {
      orderId = Delivery.manualPedOrderId(sourceNumber);
      if (orderId.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Revisá el número de pedido.';
          });
        }
        return;
      }
      sourceNumberStored =
          orderId.startsWith('PED-') ? orderId.substring(4) : sourceNumber.trim();
    } else {
      orderId = Delivery.manualOrderId(_sourceType, sourceNumber);
      sourceNumberStored = sourceNumber;
    }

    final existing = await DeliveryRepository.instance.getConductorIdByOrderId(orderId);
    if (existing != null && mounted) {
      setState(() {
        _loading = false;
        _error =
            'Ya existe una entrega con el mismo identificador (${Delivery.formatOrderIdForDisplay(orderId)}).';
      });
      return;
    }

    final now = DateTime.now();
    final delivery = Delivery(
      id: 'D-${now.millisecondsSinceEpoch}',
      nombre: _nombreController.text.trim(),
      telefono: _telefonoController.text.trim(),
      dni: _dniController.text.trim(),
      direccion: _direccionController.text.trim(),
      observaciones: _observacionesController.text.trim(),
      estado: DeliveryState.pendiente,
      conductorId: _conductorId?.trim() ?? '',
      fechaEscaneo: now,
      orderId: orderId,
      codigoPostal: null,
      localidad: _localidadController.text.trim().isEmpty ? null : _localidadController.text.trim(),
      provincia: null,
      sourceType: _sourceType,
      sourceNumber: sourceNumberStored,
      createdManually: true,
      adminAvisoRetiroCambioLeido:
          DeliverySourceType.isRetiroOCambio(_sourceType) ? false : null,
    );

    try {
      await DeliveryRepository.instance.createDelivery(delivery);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entrega manual creada.'),
          backgroundColor: AppTheme.adminEntregadoColor,
        ),
      );
      context.go(AppRoutes.admin);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'No se pudo guardar. Intentá de nuevo.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenW = MediaQuery.sizeOf(context).width;
    final hPad = screenW < AppBreakpoints.narrowScreenWidth ? 12.0 : 20.0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear entrega manual'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
              children: [
            Text(
              'Tipo de documento',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _sourceType,
              decoration: const InputDecoration(
                labelText: 'Tipo',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: DeliverySourceType.manualTypes
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(
                          t == DeliverySourceType.ped
                              ? 'Pedido web (sin QR)'
                              : DeliverySourceType.label(t),
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _sourceType = v ?? DeliverySourceType.fc),
            ),
            if (_sourceType == DeliverySourceType.ped) ...[
              const SizedBox(height: 8),
              Text(
                'Mismo identificador que el pedido web (como en el QR: PED-…). '
                'Así el conductor puede escanear el QR después y se reconoce la misma entrega.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _sourceNumberController,
              decoration: InputDecoration(
                labelText: _sourceType == DeliverySourceType.ped
                    ? 'Número de pedido'
                    : DeliverySourceType.isRetiroOCambio(_sourceType)
                        ? 'Número de retiro / cambio'
                        : 'Número de documento',
                hintText: _sourceType == DeliverySourceType.ped
                    ? 'Ej. 12345 o PED-12345'
                    : DeliverySourceType.isRetiroOCambio(_sourceType)
                        ? 'Ej. 4521'
                        : 'Ej. 0001-00001234',
                helperText: _sourceType == DeliverySourceType.ped
                    ? 'Podés escribir solo el número o el código completo PED-…'
                    : null,
                helperMaxLines: 2,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  if (_sourceType == DeliverySourceType.ped) {
                    return 'Ingresá el número de pedido.';
                  }
                  return DeliverySourceType.isRetiroOCambio(_sourceType)
                      ? 'Ingresá el número de retiro o cambio.'
                      : 'Ingresá el número.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nombreController,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingresá el nombre.';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _telefonoController,
              decoration: const InputDecoration(
                labelText: 'Teléfono',
                hintText: 'Opcional',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _dniController,
              decoration: const InputDecoration(
                labelText: 'DNI',
                hintText: 'Opcional',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _direccionController,
              decoration: const InputDecoration(labelText: 'Dirección'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingresá la dirección.';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _localidadController,
              decoration: const InputDecoration(
                labelText: 'Localidad / barrio',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _observacionesController,
              decoration: InputDecoration(
                labelText: 'Observaciones',
                helperText: DeliverySourceType.isRetiroOCambio(_sourceType)
                    ? 'Horarios, datos del retiro o del cambio, etc.'
                    : null,
                helperMaxLines: 2,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            Text(
              'Conductor',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: _conductorId,
              decoration: const InputDecoration(
                labelText: 'Asignar conductor',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Sin asignar'),
                ),
                ..._users.map((u) {
                  return DropdownMenuItem<String?>(
                    value: u.uid,
                    child: Text(UserRepository.driverDisplayLabel(u)),
                  );
                }),
              ],
              onChanged: (v) => setState(() => _conductorId = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Crear entrega'),
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
