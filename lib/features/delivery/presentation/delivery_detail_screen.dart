import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/data/user_repository.dart';
import '../../../../core/debug_delivery_log.dart';
import '../../../../core/utils/driver_location.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../data/delivery_repository.dart';
import '../domain/delivery.dart';
import '../domain/delivery_state.dart';
import 'driver_delivery_ui.dart';
import 'manual_label_pdf.dart';
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
          return Theme(
            data: DriverDeliveryUi.overlayTheme(Theme.of(context)),
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Detalle de entrega'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
              ),
              body: const Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final delivery = snapshot.data;
        if (delivery == null) {
          return Theme(
            data: DriverDeliveryUi.overlayTheme(Theme.of(context)),
            child: Scaffold(
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
            ),
          );
        }

        final isPendiente = delivery.estado == DeliveryState.pendiente;
        return Theme(
          data: DriverDeliveryUi.overlayTheme(Theme.of(context)),
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                delivery.detailHeaderPrimaryTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                          final pos = await tryCaptureDriverLocation();
                          // 1) Guardar siempre estado/motivo/fecha en Firestore.
                          final updatedBase = delivery.copyWith(
                          estado: DeliveryState.noEntregado,
                          motivoNoEntrega: result.motivo.trim(),

                          fechaNoEntrega: fechaNoEntrega,
                          cierreLatitud: pos?.lat,
                          cierreLongitud: pos?.lng,
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
                      const SizedBox(height: 16),
                      _DetailContentSection(delivery: delivery),
                      if (delivery.hasFirma) ...[
                        const SizedBox(height: 16),
                        _FirmaCard(delivery: delivery),
                      ],
                      const SizedBox(height: 16),
                      _TechnicalFooter(deliveryId: delivery.id),
                    ],
                  ),
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

/// Encabezado: nº pedido/documento como título, estado secundario, acciones de cierre.
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: DriverDeliveryUi.surface,
        borderRadius: BorderRadius.circular(DriverDeliveryUi.radiusLg),
        border: Border.all(color: DriverDeliveryUi.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            delivery.detailHeaderPrimaryTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: DriverDeliveryUi.textPrimary,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          if (delivery.detailHeaderSubtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              delivery.detailHeaderSubtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: DriverDeliveryUi.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _EstadoChipCompact(estado: delivery.estado),
              if (delivery.hasNoConductor)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: DriverDeliveryUi.neutralButtonBg,
                    borderRadius:
                        BorderRadius.circular(DriverDeliveryUi.radiusSm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_off_outlined,
                          size: 16, color: DriverDeliveryUi.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'Sin conductor',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: DriverDeliveryUi.neutralButtonFg,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Center(child: _AdminManualActions(delivery: delivery, compact: true)),
          if (delivery.estado == DeliveryState.noEntregado) ...[
            const SizedBox(height: 20),
            _PrimaryDeliveredButton(onPressed: onMarcarEntregado),
          ] else if (isPendiente) ...[
            const SizedBox(height: 20),
            _PrimaryDeliveredButton(onPressed: onMarcarEntregado),
            const SizedBox(height: 10),
            _DangerNotDeliveredButton(onPressed: onNoEntregado),
          ],
        ],
      ),
    );
  }
}

class _PrimaryDeliveredButton extends StatelessWidget {
  const _PrimaryDeliveredButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: DriverDeliveryUi.primarySuccess,
          foregroundColor: DriverDeliveryUi.onPrimarySuccess,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DriverDeliveryUi.radiusMd),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Marcar como entregado',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: DriverDeliveryUi.onPrimarySuccess,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DangerNotDeliveredButton extends StatelessWidget {
  const _DangerNotDeliveredButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          elevation: 0,
          backgroundColor: DriverDeliveryUi.surface,
          foregroundColor: DriverDeliveryUi.danger,
          side: const BorderSide(color: DriverDeliveryUi.danger, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DriverDeliveryUi.radiusMd),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cancel_outlined, size: 20),
            const SizedBox(width: 8),
            Text(
              'No entregado',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: DriverDeliveryUi.danger,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip de estado secundario (menor jerarquía que el nº de pedido/documento).
class _EstadoChipCompact extends StatelessWidget {
  const _EstadoChipCompact({required this.estado});

  final DeliveryState estado;

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    switch (estado) {
      case DeliveryState.pendiente:
        bg = DriverDeliveryUi.pendingBg;
        fg = DriverDeliveryUi.pendingFg;
        break;
      case DeliveryState.entregado:
        bg = DriverDeliveryUi.successMutedBg;
        fg = DriverDeliveryUi.successMutedFg;
        break;
      case DeliveryState.noEntregado:
        bg = DriverDeliveryUi.dangerMutedBg;
        fg = DriverDeliveryUi.dangerMutedFg;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DriverDeliveryUi.radiusSm),
        border: Border.all(color: fg.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppTheme.iconFor(estado), color: fg, size: 16),
          const SizedBox(width: 8),
          Text(
            estado.label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 0.1,
              color: fg,
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
                      title: 'Envío y contacto',
                      emphasize: true,
                      children: _buildContactoRows(context),
                    ),
                    const SizedBox(height: 12),
                    _DetailCard(
                      title: 'Datos del pedido',
                      children: _buildPedidoRows(context),
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
              title: 'Envío y contacto',
              emphasize: true,
              children: _buildContactoRows(context),
            ),
            const SizedBox(height: 12),
            _DetailCard(
              title: 'Datos del pedido',
              children: _buildPedidoRows(context),
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
    // ID pedido ya figura en el encabezado; no duplicar aquí.
    list.add(_DetailRow(label: 'Nombre', value: delivery.nombre));
    list.add(_DetailRow(label: 'Observaciones', value: delivery.observaciones));
    return list;
  }

  List<Widget> _buildContactoRows(BuildContext context) {
    final showQuick = delivery.hasAddressForMaps ||
        delivery.telefono.trim().isNotEmpty;
    final list = <Widget>[
      if (showQuick) ...[
        Text(
          'Acciones rápidas',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: DriverDeliveryUi.textSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
        ),
        const SizedBox(height: 10),
        _QuickActionsGroup(child: _DetailActions(delivery: delivery)),
        const SizedBox(height: 16),
      ],
    ];
    if (delivery.hasAddressForMaps) {
      list.add(_AddressHeroBlock(address: delivery.addressLineForMaps));
    } else {
      list.add(_DetailRow(label: 'Dirección', value: '—'));
    }
    list.addAll([
      _DetailRow(label: 'Teléfono', value: delivery.telefono),
      _DetailRow(label: 'DNI', value: delivery.dni),
    ]);
    if (delivery.codigoPostal != null && delivery.codigoPostal!.isNotEmpty) {
      list.add(_DetailRow(label: 'Código postal', value: delivery.codigoPostal!));
    }
    if (delivery.localidad != null && delivery.localidad!.isNotEmpty) {
      list.add(_DetailRow(
          label: 'Localidad / barrio', value: delivery.localidad!));
    }
    if (delivery.direccionCompleta != null &&
        delivery.direccionCompleta!.trim().isNotEmpty &&
        delivery.direccionCompleta!.trim() != delivery.direccion.trim()) {
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
    if (delivery.cierreLatitud != null && delivery.cierreLongitud != null) {
      list.add(_UbicacionCierreRow(
        lat: delivery.cierreLatitud!,
        lng: delivery.cierreLongitud!,
      ));
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
    this.emphasize = false,
  });

  final String title;
  final List<Widget> children;
  final bool subdued;

  /// Resalta el bloque (p. ej. envío y contacto para el conductor).
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: emphasize ? DriverDeliveryUi.background : null,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DriverDeliveryUi.radiusLg),
        side: BorderSide(
          color: emphasize
              ? DriverDeliveryUi.borderSubtle
              : DriverDeliveryUi.borderSubtle,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(emphasize ? 18 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  if (emphasize) ...[
                    Icon(
                      Icons.local_shipping_outlined,
                      size: 22,
                      color: DriverDeliveryUi.secondaryBlue,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: subdued
                            ? DriverDeliveryUi.textSecondary
                            : DriverDeliveryUi.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Dirección destacada con negrita (mismo cuerpo que el resto del detalle).
class _AddressHeroBlock extends StatelessWidget {
  const _AddressHeroBlock({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.place_outlined,
            size: 20,
            color: DriverDeliveryUi.secondaryBlue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              address,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
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
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DriverDeliveryUi.radiusLg),
        side: const BorderSide(color: DriverDeliveryUi.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.draw_outlined,
                    color: DriverDeliveryUi.secondaryBlue, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Firma del receptor',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: DriverDeliveryUi.textPrimary,
                    letterSpacing: -0.2,
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
                      color: DriverDeliveryUi.borderSubtle,
                    ),
                    borderRadius:
                        BorderRadius.circular(DriverDeliveryUi.radiusMd),
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
          color: DriverDeliveryUi.textSecondary.withValues(alpha: 0.85),
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
    _isAdminFuture.then((admin) {
      if (!mounted || !admin) return;
      _marcarAvisoRetiroCambioSiCorresponde();
    });
  }

  Future<void> _marcarAvisoRetiroCambioSiCorresponde() async {
    if (!widget.delivery.needsAdminAvisoRetiroCambio) return;
    try {
      await DeliveryRepository.instance.updateDelivery(
        widget.delivery.copyWith(adminAvisoRetiroCambioLeido: true),
      );
    } catch (_) {}
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
        final row = Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  context.push(AppRoutes.editarEntregaPath(widget.delivery.id)),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Editar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: DriverDeliveryUi.secondaryBlue,
                side: BorderSide(
                  color:
                      DriverDeliveryUi.secondaryBlue.withValues(alpha: 0.45),
                ),
              ),
            ),
            if (ManualLabelPdf.canPrintLabel(widget.delivery))
              FilledButton.icon(
                onPressed: () => _showQrDialog(context),
                icon: const Icon(Icons.qr_code_2_outlined, size: 18),
                label: const Text('QR y etiqueta'),
                style: FilledButton.styleFrom(
                  backgroundColor: DriverDeliveryUi.neutralButtonBg,
                  foregroundColor: DriverDeliveryUi.neutralButtonFg,
                ),
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
    const qrSize = 200.0;
    final d = widget.delivery;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QR y datos de etiqueta'),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: SizedBox(
                    width: qrSize,
                    height: qrSize,
                    child: QrImageView(
                      data: data,
                      version: QrVersions.auto,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Mismo contenido que en la etiqueta impresa (envío / documento / dirección).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                _LabelSummaryText(delivery: d),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton.icon(
            onPressed: () async {
              await ManualLabelPdf.printLabels([d]);
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimir etiqueta'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

/// Texto alineado a lo que lleva la etiqueta PDF (vista previa en el diálogo QR).
class _LabelSummaryText extends StatelessWidget {
  const _LabelSummaryText({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget row(String label, String value) {
      if (value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 108,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(child: Text(value.trim(), style: theme.textTheme.bodyMedium)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row('Documento', delivery.sourceLabel),
        if (delivery.sourceNumber != null &&
            delivery.sourceNumber!.trim().isNotEmpty)
          row('Nº', delivery.sourceNumber!),
        row('Nombre', delivery.nombre),
        row('Teléfono', delivery.telefono),
        row('DNI', delivery.dni),
        row('Dirección', delivery.direccion),
        if (delivery.localidad != null && delivery.localidad!.trim().isNotEmpty)
          row('Localidad / barrio', delivery.localidad!),
        if (delivery.codigoPostal != null &&
            delivery.codigoPostal!.trim().isNotEmpty)
          row('Código postal', delivery.codigoPostal!),
        if (delivery.direccionCompleta != null &&
            delivery.direccionCompleta!.trim().isNotEmpty &&
            delivery.direccionCompleta!.trim() != delivery.direccion.trim())
          row('Dirección completa', delivery.direccionCompleta!),
        if (delivery.observaciones.trim().isNotEmpty)
          row('Observaciones', delivery.observaciones),
        if (delivery.orderId != null && delivery.orderId!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'ID: ${Delivery.formatOrderIdForDisplay(delivery.orderId!)}',
              style: small,
            ),
          ),
      ],
    );
  }
}

/// Agrupa Maps / Llamar / Copiar con fondo neutro y borde suave.
class _QuickActionsGroup extends StatelessWidget {
  const _QuickActionsGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DriverDeliveryUi.background,
        borderRadius: BorderRadius.circular(DriverDeliveryUi.radiusMd),
        border: Border.all(color: DriverDeliveryUi.borderSubtle),
      ),
      child: child,
    );
  }
}

class _DetailActions extends StatelessWidget {
  const _DetailActions({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    final hasAddress = delivery.hasAddressForMaps;
    final hasPhone = delivery.telefono.trim().isNotEmpty;
    if (!hasAddress && !hasPhone) return const SizedBox.shrink();

    Widget mini({
      required VoidCallback onPressed,
      required IconData icon,
      required String label,
      required Color bg,
      required Color fg,
    }) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          minimumSize: const Size(0, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          backgroundColor: bg,
          foregroundColor: fg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DriverDeliveryUi.radiusSm),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final rowChildren = <Widget>[];
    if (hasAddress) {
      rowChildren.add(
        Expanded(
          child: mini(
            onPressed: () => _openMaps(context),
            icon: Icons.map_outlined,
            label: 'Maps',
            bg: DriverDeliveryUi.secondaryBlue,
            fg: Colors.white,
          ),
        ),
      );
    }
    if (hasPhone) {
      if (rowChildren.isNotEmpty) {
        rowChildren.add(const SizedBox(width: 8));
      }
      rowChildren.add(
        Expanded(
          child: mini(
            onPressed: () => _call(context),
            icon: Icons.phone_outlined,
            label: 'Llamar',
            bg: DriverDeliveryUi.secondaryDark,
            fg: Colors.white,
          ),
        ),
      );
    }
    if (hasAddress) {
      rowChildren.add(const SizedBox(width: 8));
      rowChildren.add(
        Expanded(
          child: mini(
            onPressed: () => _copyAddress(context),
            icon: Icons.copy_outlined,
            label: 'Copiar',
            bg: DriverDeliveryUi.neutralButtonBg,
            fg: DriverDeliveryUi.neutralButtonFg,
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: rowChildren,
    );
  }

  Future<void> _openMaps(BuildContext context) async {
    final address = delivery.addressLineForMaps;
    if (address.isEmpty) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
    );
    try {
      // No usar solo canLaunchUrl: en Android 11+ puede dar false aunque el enlace sea válido.
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!context.mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Se abrió Maps')),
        );
      } else {
        final theme = Theme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No se pudo abrir Maps'),
            backgroundColor: theme.colorScheme.error,
          ),
        );
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
      final ok = await launchUrl(uri);
      if (!context.mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Se abrió el marcador')),
        );
      } else {
        final theme = Theme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No se pudo realizar la llamada'),
            backgroundColor: theme.colorScheme.error,
          ),
        );
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
    final address = delivery.addressLineForMaps;
    if (address.isEmpty) return;
    Clipboard.setData(ClipboardData(text: address));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dirección copiada al portapapeles')),
    );
  }
}

/// Ubicación GPS del conductor al cerrar entrega (entregado / no entregado).
class _UbicacionCierreRow extends StatelessWidget {
  const _UbicacionCierreRow({required this.lat, required this.lng});

  final double lat;
  final double lng;

  @override
  Widget build(BuildContext context) {
    final coord =
        '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ubicación al cierre (conductor)',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          SelectableText(coord, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () async {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Abrir en mapa'),
          ),
        ],
      ),
    );
  }
}

/// Muestra el conductor por usuario legible o uid; fallback si no hay dato.
class _ConductorRow extends StatelessWidget {
  const _ConductorRow({required this.conductorId});

  final String conductorId;

  @override
  Widget build(BuildContext context) {
    if (conductorId.trim().isEmpty) {
      return const _DetailRow(label: 'Conductor', value: 'Sin asignar');
    }
    return FutureBuilder<AppUser?>(
      future: UserRepository.instance.getProfile(conductorId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _DetailRow(label: 'Conductor', value: '…');
        }
        if (snapshot.hasData && snapshot.data != null) {
          return _DetailRow(
            label: 'Conductor',
            value: UserRepository.driverDisplayLabel(snapshot.data!),
          );
        }
        return _DetailRow(
          label: 'Conductor',
          value: UserRepository.uidFallbackLabel(conductorId),
        );
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
                  color: DriverDeliveryUi.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: DriverDeliveryUi.textPrimary,
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}
