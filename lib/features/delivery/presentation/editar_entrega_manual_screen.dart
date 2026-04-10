import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/data/user_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../data/delivery_repository.dart';
import '../domain/delivery.dart';

/// Pantalla para que el admin edite una entrega manual (asignar/reasignar conductor, datos).
class EditarEntregaManualScreen extends StatefulWidget {
  const EditarEntregaManualScreen({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  State<EditarEntregaManualScreen> createState() => _EditarEntregaManualScreenState();
}

class _EditarEntregaManualScreenState extends State<EditarEntregaManualScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _dniController = TextEditingController();
  final _direccionController = TextEditingController();
  final _observacionesController = TextEditingController();

  Delivery? _delivery;
  String? _conductorId;
  List<AppUser> _users = [];
  bool _loading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final delivery = await DeliveryRepository.instance.getDeliveryById(widget.deliveryId);
    final users = await UserRepository.instance.getAllUsers();
    if (!mounted) return;
    setState(() {
      _delivery = delivery;
      _users = users;
      _loadError = delivery == null ? 'No se encontró la entrega.' : null;
      if (delivery != null) {
        _nombreController.text = delivery.nombre;
        _telefonoController.text = delivery.telefono;
        _dniController.text = delivery.dni;
        _direccionController.text = delivery.direccion;
        _observacionesController.text = delivery.observaciones;
        _conductorId = delivery.conductorId.trim().isEmpty ? null : delivery.conductorId;
      }
    });
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _dniController.dispose();
    _direccionController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_delivery == null || !_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final updated = _delivery!.copyWith(
      nombre: _nombreController.text.trim(),
      telefono: _telefonoController.text.trim(),
      dni: _dniController.text.trim(),
      direccion: _direccionController.text.trim(),
      observaciones: _observacionesController.text.trim(),
      conductorId: _conductorId?.trim() ?? '',
    );
    try {
      await DeliveryRepository.instance.updateDelivery(updated);
      if (_delivery!.hasOrderId) {
        await DeliveryRepository.instance.updateKeyConductor(updated.orderId!, updated.conductorId, updated.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entrega actualizada.'),
          backgroundColor: AppTheme.entregadoColor,
        ),
      );
      context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_delivery == null && _loadError == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Editar entrega')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null && _delivery == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Editar entrega'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        ),
        body: Center(child: Text(_loadError!)),
      );
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar entrega manual'),
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
              _delivery!.sourceLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
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
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar cambios'),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
