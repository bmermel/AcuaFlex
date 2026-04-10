import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/data/user_repository.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../data/delivery_repository.dart';
import '../domain/delivery.dart';
import '../domain/delivery_state.dart';

/// Pantalla para que el admin cree una entrega manual (FC, OV, COT).
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
  final _codigoPostalController = TextEditingController();
  final _localidadController = TextEditingController();
  final _provinciaController = TextEditingController();
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
    _codigoPostalController.dispose();
    _localidadController.dispose();
    _provinciaController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final sourceNumber = _sourceNumberController.text.trim();
    if (sourceNumber.isEmpty) {
      setState(() => _error = 'Ingresá el número de documento.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });

    final orderId = Delivery.manualOrderId(_sourceType, sourceNumber);
    final existing = await DeliveryRepository.instance.getConductorIdByOrderId(orderId);
    if (existing != null && mounted) {
      setState(() {
        _loading = false;
        _error = 'Ya existe una entrega con ese tipo y número de documento (${DeliverySourceType.label(_sourceType)} $sourceNumber).';
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
      codigoPostal: _codigoPostalController.text.trim().isEmpty ? null : _codigoPostalController.text.trim(),
      localidad: _localidadController.text.trim().isEmpty ? null : _localidadController.text.trim(),
      provincia: _provinciaController.text.trim().isEmpty ? null : _provinciaController.text.trim(),
      sourceType: _sourceType,
      sourceNumber: sourceNumber,
      createdManually: true,
    );

    try {
      await DeliveryRepository.instance.createDelivery(delivery);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entrega manual creada.'),
          backgroundColor: AppTheme.entregadoColor,
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                        child: Text(DeliverySourceType.label(t)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _sourceType = v ?? DeliverySourceType.fc),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _sourceNumberController,
              decoration: const InputDecoration(
                labelText: 'Número de documento',
                hintText: 'Ej. 0001-00001234',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingresá el número.';
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
              decoration: const InputDecoration(labelText: 'Teléfono'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _dniController,
              decoration: const InputDecoration(labelText: 'DNI'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingresá el DNI.';
                return null;
              },
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
              controller: _codigoPostalController,
              decoration: const InputDecoration(labelText: 'Código postal'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _localidadController,
              decoration: const InputDecoration(labelText: 'Localidad'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _provinciaController,
              decoration: const InputDecoration(labelText: 'Provincia'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _observacionesController,
              decoration: const InputDecoration(labelText: 'Observaciones'),
              maxLines: 2,
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
                  final label = AuthService.shortDisplayName(u.email);
                  final fallback = u.uid.length > 6 ? '…${u.uid.substring(u.uid.length - 6)}' : u.uid;
                  return DropdownMenuItem<String?>(
                    value: u.uid,
                    child: Text(label.isNotEmpty ? label : 'Conductor ($fallback)'),
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
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Crear entrega'),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
