import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/data/user_repository.dart';
import '../../../../core/debug_delivery_log.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../data/delivery_repository.dart';
import '../domain/delivery.dart';
import '../domain/delivery_state.dart';
import 'no_entregado_dialog.dart';

class DeliveryDetailScreen extends StatelessWidget {
  const DeliveryDetailScreen({super.key, required this.deliveryId});

  final String deliveryId;

  // Visor para imágenes en base64 (Firestore).

  static void _showFullScreenBytes(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(24),
              child: Icon(Icons.broken_image, size: 48),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Delivery?>(
      future: DeliveryRepository.instance.getDeliveryById(deliveryId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Detalle de entrega'),
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
              title: const Text('Detalle de entrega'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No se encontró la entrega con id: $deliveryId',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final isPendiente = delivery.estado == DeliveryState.pendiente;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Detalle de entrega'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DetailHeaderCard(
                      delivery: delivery,
                      isPendiente: isPendiente,
                      onMarcarEntregado: () =>
                          context.push(AppRoutes.confirmarEntregaPath(delivery.id)),
                      onNoEntregado: () async {
                        final result = await showNoEntregadoDialog(context);
                        if (result == null || result.motivo.trim().isEmpty) return;

                        try {
                          final fechaNoEntrega = DateTime.now();
                          // 1) Guardar siempre estado/motivo/fecha en Firestore.
                          final updatedBase = delivery.copyWith(
                          estado: DeliveryState.noEntregado,
                          motivoNoEntrega: result.motivo.trim(),

                          fechaNoEntrega: fechaNoEntrega,
                          );
                          await DeliveryRepository.instance.updateDelivery(updatedBase);

                          // 2) Subir fotos (opcional) y persistir solo evidencia.
                          if (result.fotos.isNotEmpty) {
                            try {
                              final uid = AuthService.instance.currentUser?.uid ?? '';
                              await DeliveryRepository.instance.replaceNoEntregadoEvidences(
                                deliveryId: delivery.id,
                                fotos: result.fotos
                                    .map((p) => (file: p.file, type: p.type))
                                    .toList(),
                                createdAt: DateTime.now(),
                                uploadedBy: uid,
                              );
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Se guardó el estado, pero no se pudieron guardar las fotos de evidencia.',
                                    ),
                                    backgroundColor: Theme.of(context).colorScheme.error,
                                  ),
                                );
                              }
                            }
                          }

                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Entrega marcada como NO ENTREGADA.')),
                        );
                        context.pop();
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('No se pudo guardar la entrega.'),
                              backgroundColor: Theme.of(context).colorScheme.error,
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _DetailContentSection(delivery: delivery),
                    if (delivery.hasFirma) ...[
                      const SizedBox(height: 12),
                      _FirmaCard(delivery: delivery),
                    ],
                    const SizedBox(height: 12),
                    _TechnicalFooter(deliveryId: delivery.id),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _formatDate(DateTime d) {
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

/// Breakpoint para layout de 2 columnas (web/tablet).
const double _kDetailBreakpoint = 720;

/// Header: estado, origen, documento y barra de acciones.
class _DetailHeaderCard extends StatelessWidget {
  const _DetailHeaderCard({
    required this.delivery,
    required this.isPendiente,
    required this.onMarcarEntregado,
    required this.onNoEntregado,
  });

  final Delivery delivery;
  final bool isPendiente;
  final VoidCallback onMarcarEntregado;
  final VoidCallback onNoEntregado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                _EstadoChipLarge(estado: delivery.estado),
                Chip(
                  avatar: Icon(
                    delivery.isManual
                        ? Icons.edit_document
                        : Icons.shopping_bag_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(
                    delivery.isManual
                        ? 'Carga manual · ${delivery.sourceLabel}'
                        : 'Pedido web',
                  ),
                ),
                if (delivery.hasNoConductor)
                  const Chip(
                    avatar: Icon(Icons.person_off_outlined, size: 18),
                    label: Text('Sin conductor'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (delivery.hasOrderId || (delivery.isManual && delivery.sourceNumber != null))
              Text(
                delivery.hasOrderId
                    ? 'ID pedido: ${delivery.orderId}'
                    : '${delivery.sourceLabel} ${delivery.sourceNumber ?? ''}'.trim(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _DetailActions(delivery: delivery, compact: true),
                _AdminManualActions(delivery: delivery, compact: true),
                if (delivery.estado == DeliveryState.noEntregado)
                  FilledButton.icon(
                    onPressed: onMarcarEntregado,
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: const Text('Marcar como entregado'),
                  )
                else if (isPendiente) ...[
                  FilledButton.icon(
                    onPressed: onMarcarEntregado,
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: const Text('Marcar como entregado'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: onNoEntregado,
                    icon: const Icon(Icons.cancel_outlined, size: 20),
                    label: const Text('No entregado'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip de estado más grande y visible.
class _EstadoChipLarge extends StatelessWidget {
  const _EstadoChipLarge({required this.estado});

  final DeliveryState estado;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColorFor(estado),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.colorFor(estado).withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppTheme.iconFor(estado), color: AppTheme.colorFor(estado), size: 22),
          const SizedBox(width: 8),
          Text(
            estado.label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: AppTheme.colorFor(estado),
            ),
          ),
        ],
      ),
    );
  }
}

/// Contenido principal: 2 columnas en web, 1 en móvil.
class _DetailContentSection extends StatelessWidget {
  const _DetailContentSection({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= _kDetailBreakpoint;
        if (useTwoColumns) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DetailCard(
                      title: 'Datos del pedido',
                      children: _buildPedidoRows(context),
                    ),
                    const SizedBox(height: 12),
                    _DetailCard(
                      title: 'Contacto y dirección',
                      children: _buildContactoRows(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DetailCard(
                      title: 'Datos de entrega',
                      children: _buildEntregaRows(context),
                    ),
                    const SizedBox(height: 12),
                    _DetailCard(
                      title: 'Quien recibió',
                      children: _buildRecibioRows(context),
                    ),
                    if (_buildNoEntregadoContent(context).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _DetailCard(
                        title: 'No entregado',
                        children: _buildNoEntregadoContent(context),
                      ),
                    ],
                    if (_buildHistorialContent(context).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _DetailCard(
                        title: 'Historial (previamente no entregado)',
                        subdued: true,
                        children: _buildHistorialContent(context),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DetailCard(
              title: 'Datos del pedido',
              children: _buildPedidoRows(context),
            ),
            const SizedBox(height: 12),
            _DetailCard(
              title: 'Contacto y dirección',
              children: _buildContactoRows(context),
            ),
            const SizedBox(height: 12),
            _DetailCard(
              title: 'Datos de entrega',
              children: _buildEntregaRows(context),
            ),
            const SizedBox(height: 12),
            _DetailCard(
              title: 'Quien recibió',
              children: _buildRecibioRows(context),
            ),
            if (_buildNoEntregadoContent(context).isNotEmpty) ...[
              const SizedBox(height: 12),
              _DetailCard(
                title: 'No entregado',
                children: _buildNoEntregadoContent(context),
              ),
            ],
            if (_buildHistorialContent(context).isNotEmpty) ...[
              const SizedBox(height: 12),
              _DetailCard(
                title: 'Historial (previamente no entregado)',
                subdued: true,
                children: _buildHistorialContent(context),
              ),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _buildPedidoRows(BuildContext context) {
    final list = <Widget>[];
    if (delivery.isManual) {
      list.add(_DetailRow(label: 'Tipo de documento', value: delivery.sourceLabel));
      if (delivery.sourceNumber != null && delivery.sourceNumber!.isNotEmpty) {
        list.add(_DetailRow(
            label: 'Número de documento', value: delivery.sourceNumber!));
      }
    }
    if (delivery.hasOrderId) {
      list.add(_DetailRow(label: 'ID pedido', value: delivery.orderId!));
    }
    list.add(_DetailRow(label: 'Nombre', value: delivery.nombre));
    list.add(_DetailRow(label: 'Observaciones', value: delivery.observaciones));
    return list;
  }

  List<Widget> _buildContactoRows(BuildContext context) {
    final list = <Widget>[
      _DetailRow(label: 'Teléfono', value: delivery.telefono),
      _DetailRow(label: 'DNI', value: delivery.dni),
      _DetailRow(label: 'Dirección', value: delivery.direccion),
    ];
    if (delivery.codigoPostal != null && delivery.codigoPostal!.isNotEmpty) {
      list.add(_DetailRow(label: 'Código postal', value: delivery.codigoPostal!));
    }
    if (delivery.localidad != null && delivery.localidad!.isNotEmpty) {
      list.add(_DetailRow(label: 'Localidad', value: delivery.localidad!));
    }
    if (delivery.provincia != null && delivery.provincia!.isNotEmpty) {
      list.add(_DetailRow(label: 'Provincia', value: delivery.provincia!));
    }
    if (delivery.direccionCompleta != null &&
        delivery.direccionCompleta!.trim().isNotEmpty) {
      list.add(_DetailRow(
          label: 'Dirección completa', value: delivery.direccionCompleta!));
    }
    return list;
  }

  List<Widget> _buildEntregaRows(BuildContext context) {
    final list = <Widget>[
      _ConductorRow(conductorId: delivery.conductorId),
      _DetailRow(
          label: 'Fecha escaneo',
          value: DeliveryDetailScreen._formatDate(delivery.fechaEscaneo)),
    ];
    if (delivery.fechaEntrega != null) {
      list.add(_DetailRow(
          label: 'Fecha entrega',
          value: DeliveryDetailScreen._formatDate(delivery.fechaEntrega!)));
    }
    return list;
  }

  List<Widget> _buildRecibioRows(BuildContext context) {
    final list = <Widget>[];
    if (delivery.nombreRecibe != null && delivery.nombreRecibe!.trim().isNotEmpty) {
      list.add(_DetailRow(label: 'Recibió', value: delivery.nombreRecibe!));
    }
    if (delivery.dniRecibe != null && delivery.dniRecibe!.trim().isNotEmpty) {
      list.add(_DetailRow(label: 'DNI', value: delivery.dniRecibe!));
    }
    if (delivery.relacionRecibe != null &&
        delivery.relacionRecibe!.trim().isNotEmpty) {
      list.add(_DetailRow(label: 'Relación', value: delivery.relacionRecibe!));
    }
    if (list.isEmpty) {
      list.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          '—',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ));
    }
    return list;
  }

  List<Widget> _buildNoEntregadoContent(BuildContext context) {
    if (!delivery.isNoEntregado) return [];
    final list = <Widget>[
      _DetailRow(
          label: 'Motivo', value: delivery.motivoNoEntrega ?? '—'),
    ];
    if (delivery.fechaNoEntrega != null) {
      list.add(_DetailRow(
          label: 'Fecha',
          value: DeliveryDetailScreen._formatDate(delivery.fechaNoEntrega!)));
    }
    list.add(const SizedBox(height: 12));
    list.add(Text(
      'Evidencia',
      style: Theme.of(context).textTheme.titleSmall,
    ));
    list.add(const SizedBox(height: 8));
    list.add(_EvidenceGalleryFirestore(deliveryId: delivery.id, thumbSize: 100));
    return list;
  }

  List<Widget> _buildHistorialContent(BuildContext context) {
    if (delivery.estado != DeliveryState.entregado ||
        delivery.motivoNoEntrega == null ||
        delivery.motivoNoEntrega!.trim().isEmpty) {
      return [];
    }
    final list = <Widget>[
      _DetailRow(
          label: 'Motivo anterior',
          value: delivery.motivoNoEntrega!.trim()),
    ];
    if (delivery.fechaNoEntrega != null) {
      list.add(_DetailRow(
          label: 'Fecha anterior',
          value: DeliveryDetailScreen._formatDate(delivery.fechaNoEntrega!)));
    }
    list.add(const SizedBox(height: 8));
    list.add(_EvidenceGalleryFirestore(deliveryId: delivery.id, thumbSize: 80));
    return list;
  }
}

class _EvidenceGalleryFirestore extends StatelessWidget {
  const _EvidenceGalleryFirestore({
    required this.deliveryId,
    required this.thumbSize,
  });

  final String deliveryId;
  final double thumbSize;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DeliveryRepository.instance.getNoEntregadoEvidences(deliveryId),
      builder: (context, snapshot) {
        final list = snapshot.data ?? const [];
        if (list.isEmpty && snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 32,
            child: Align(
              alignment: Alignment.centerLeft,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (list.isEmpty) {
          return Text(
            'Sin evidencia adjunta',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: list.map((e) {
            final b64 = (e['imageBase64'] ?? '').toString().trim();
            Uint8List? bytes;
            try {
              if (b64.isNotEmpty) bytes = base64Decode(b64);
            } catch (_) {
              bytes = null;
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: bytes == null
                    ? null
                    : () => DeliveryDetailScreen._showFullScreenBytes(context, bytes!),
                child: bytes == null
                    ? SizedBox(
                        width: thumbSize,
                        height: thumbSize,
                        child: const Icon(Icons.broken_image),
                      )
                    : Image.memory(
                        bytes,
                        width: thumbSize,
                        height: thumbSize,
                        fit: BoxFit.cover,
                      ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

/// Card con título y lista de filas (reutilizable).
class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.title,
    required this.children,
    this.subdued = false,
  });

  final String title;
  final List<Widget> children;
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: subdued
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Bloque firma del receptor, ancho cómodo.
class _FirmaCard extends StatelessWidget {
  const _FirmaCard({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (delivery.firmaBase64 == null || delivery.firmaBase64!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.draw_outlined,
                    color: theme.colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Firma del receptor',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420, maxHeight: 160),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.35),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      base64Decode(delivery.firmaBase64!),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            if (delivery.fechaFirma != null) ...[
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Fecha: ${DeliveryDetailScreen._formatDate(delivery.fechaFirma!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pie con datos técnicos (poco prominente).
class _TechnicalFooter extends StatelessWidget {
  const _TechnicalFooter({required this.deliveryId});

  final String deliveryId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        'ID documento: $deliveryId',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _AdminManualActions extends StatefulWidget {
  const _AdminManualActions({required this.delivery, this.compact = false});

  final Delivery delivery;
  final bool compact;

  @override
  State<_AdminManualActions> createState() => _AdminManualActionsState();
}

class _AdminManualActionsState extends State<_AdminManualActions> {
  late Future<bool> _isAdminFuture;

  @override
  void initState() {
    super.initState();
    _isAdminFuture = _loadIsAdmin();
  }

  Future<bool> _loadIsAdmin() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return false;
    return UserRepository.instance.isAdmin(user.uid);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.delivery.isManual) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: _isAdminFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data != true) return const SizedBox.shrink();
        final row = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => context.push(AppRoutes.editarEntregaPath(widget.delivery.id)),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar'),
            ),
            const SizedBox(width: 12),
            if (widget.delivery.estado == DeliveryState.pendiente)
              FilledButton.tonalIcon(
                onPressed: () => _showQrDialog(context),
                icon: const Icon(Icons.qr_code_2_outlined),
                label: const Text('Generar QR'),
              ),
          ],
        );
        if (widget.compact) return row;
        return Padding(padding: const EdgeInsets.only(bottom: 16), child: row);
      },
    );
  }

  void _showQrDialog(BuildContext context) {
    final json = widget.delivery.toQrJson();
    deliveryDebugLog(
      'delivery_detail_screen._showQrDialog',
      'QR JSON generated for manual delivery',
      data: {
        'orderId': json['orderId'],
        'sourceType': json['sourceType'],
        'sourceNumber': json['sourceNumber'],
        'createdManually': json['createdManually'],
        'fullJson': json,
      },
    );
    final data = jsonEncode(json);
    const qrSize = 220.0;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QR de entrega'),
        content: SizedBox(
          width: qrSize + 40,
          height: qrSize + 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: qrSize,
                height: qrSize,
                child: QrImageView(
                  data: data,
                  version: QrVersions.auto,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${widget.delivery.sourceLabel} ${widget.delivery.sourceNumber ?? ''}'.trim(),
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _DetailActions extends StatelessWidget {
  const _DetailActions({required this.delivery, this.compact = false});

  final Delivery delivery;
  final bool compact;

  static String _addressString(Delivery d) {
    if (d.direccionCompleta != null && d.direccionCompleta!.trim().isNotEmpty) {
      return d.direccionCompleta!.trim();
    }
    final parts = <String>[d.direccion.trim()];
    if (d.localidad != null && d.localidad!.trim().isNotEmpty) {
      parts.add(d.localidad!.trim());
    }
    if (d.provincia != null && d.provincia!.trim().isNotEmpty) {
      parts.add(d.provincia!.trim());
    }
    if (d.codigoPostal != null && d.codigoPostal!.trim().isNotEmpty) {
      parts.add(d.codigoPostal!.trim());
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final hasAddress = delivery.direccion.trim().isNotEmpty;
    final hasPhone = delivery.telefono.trim().isNotEmpty;
    if (!hasAddress && !hasPhone) return const SizedBox.shrink();

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
          if (hasAddress)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                onPressed: () => _openMaps(context),
                icon: const Icon(Icons.map_outlined, size: 20),
                label: const Text('Maps'),
              ),
            ),
          if (hasPhone)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                onPressed: () => _call(context),
                icon: const Icon(Icons.phone_outlined, size: 20),
                label: const Text('Llamar'),
              ),
            ),
          if (hasAddress)
            FilledButton.tonalIcon(
              onPressed: () => _copyAddress(context),
              icon: const Icon(Icons.copy, size: 20),
              label: const Text('Copiar dirección'),
            ),
      ],
    );
    if (compact) return row;
    return Padding(padding: const EdgeInsets.only(bottom: 24), child: row);
  }

  Future<void> _openMaps(BuildContext context) async {
    final address = _addressString(delivery);
    if (address.isEmpty) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Se abrió Maps')),
          );
        }
      } else {
        if (context.mounted) {
          final theme = Theme.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No se pudo abrir Maps'),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        final theme = Theme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error al abrir Maps'),
            backgroundColor: theme.colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _call(BuildContext context) async {
    final tel = delivery.telefono.trim();
    if (tel.isEmpty) return;
    final uri = Uri.parse('tel:$tel');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Se abrió el marcador')),
          );
        }
      } else {
        if (context.mounted) {
          final theme = Theme.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No se pudo realizar la llamada'),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        final theme = Theme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error al abrir el marcador'),
            backgroundColor: theme.colorScheme.error,
          ),
        );
      }
    }
  }

  void _copyAddress(BuildContext context) {
    final address = _addressString(delivery);
    if (address.isEmpty) return;
    Clipboard.setData(ClipboardData(text: address));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dirección copiada al portapapeles')),
    );
  }
}

/// Muestra el conductor por usuario legible o uid; fallback si no hay dato.
class _ConductorRow extends StatelessWidget {
  const _ConductorRow({required this.conductorId});

  final String conductorId;

  static String _labelForUser(AppUser? user) {
    if (user == null) return '';
    final short = AuthService.shortDisplayName(user.email);
    if (short.isNotEmpty) return short;
    final uid = user.uid;
    if (uid.length <= 8) return 'Conductor ($uid)';
    return 'Conductor (…${uid.substring(uid.length - 6)})';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: UserRepository.instance.getProfile(conductorId),
      builder: (context, snapshot) {
        final label = snapshot.hasData
            ? _labelForUser(snapshot.data)
            : (snapshot.connectionState == ConnectionState.waiting
                ? '…'
                : conductorId.length >= 6
                    ? 'Conductor (…${conductorId.substring(conductorId.length - 6)})'
                    : 'Conductor ($conductorId)');
        return _DetailRow(label: 'Conductor', value: label);
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
