import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/widgets/adaptive_button_row.dart';
import 'package:image_picker/image_picker.dart';

/// Resultado del diálogo "No entregado": motivo y hasta 2 fotos (XFile).
class NoEntregadoPhoto {
  const NoEntregadoPhoto({required this.file, required this.type});
  final XFile file;
  /// Ej: call_screenshot / door_photo
  final String type;
}

class NoEntregadoResult {
  const NoEntregadoResult({
    required this.motivo,
    this.fotos = const [],
  });
  final String motivo;
  final List<NoEntregadoPhoto> fotos;
}

/// Diálogo para marcar una entrega como no entregada: motivo obligatorio y hasta 2 fotos opcionales.
/// Retorna [NoEntregadoResult] al confirmar, o null si cancela.
Future<NoEntregadoResult?> showNoEntregadoDialog(BuildContext context) async {
  return showDialog<NoEntregadoResult>(
    context: context,
    builder: (ctx) => const _NoEntregadoDialog(),
  );
}

class _NoEntregadoDialog extends StatefulWidget {
  const _NoEntregadoDialog();

  @override
  State<_NoEntregadoDialog> createState() => _NoEntregadoDialogState();
}

class _NoEntregadoDialogState extends State<_NoEntregadoDialog> {
  static const motivos = <String>[
    'Cliente ausente',
    'Dirección incorrecta',
    'Rechazó el pedido',
    'No respondió',
    'Otro',
  ];

  String? _motivoSeleccionado;
  String? _motivoOtro;
  final List<NoEntregadoPhoto> _fotos = [];
  final ImagePicker _picker = ImagePicker();
  final bool _loading = false;

  Future<void> _pickImage(ImageSource source) async {
    if (_fotos.length >= 2) return;
    final xfile = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (xfile == null || !mounted) return;
    setState(() {
      if (_fotos.length < 2) {
        _fotos.add(
          NoEntregadoPhoto(
            file: xfile,
            type: source == ImageSource.gallery ? 'call_screenshot' : 'door_photo',
          ),
        );
      }
    });
  }

  void _removePhoto(int index) {
    setState(() => _fotos.removeAt(index));
  }

  void _confirm() {
    if (_motivoSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná un motivo.')),
      );
      return;
    }
    if (_motivoSeleccionado == 'Otro') {
      final v = (_motivoOtro ?? '').trim();
      if (v.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresá el motivo para "Otro".')),
        );
        return;
      }
      Navigator.of(context).pop(NoEntregadoResult(motivo: v, fotos: List.from(_fotos)));
      return;
    }
    Navigator.of(context).pop(NoEntregadoResult(motivo: _motivoSeleccionado!, fotos: List.from(_fotos)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('No entregado'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Seleccioná un motivo (obligatorio):'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: motivos.map((m) {
                  final selected = _motivoSeleccionado == m;
                  return ChoiceChip(
                    label: Text(m),
                    selected: selected,
                    onSelected: (sel) {
                      if (sel) setState(() => _motivoSeleccionado = m);
                    },
                  );
                }).toList(),
              ),
              if (_motivoSeleccionado == 'Otro') ...[
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Motivo (otro)',
                    hintText: 'Ingresá el motivo',
                  ),
                  onChanged: (v) => setState(() => _motivoOtro = v),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Evidencia (opcional, hasta 2 fotos)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              AdaptiveButtonRow(
                spacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _fotos.length >= 2 ? null : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined, size: 20),
                    label: const Text('Cámara'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _fotos.length >= 2 ? null : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, size: 20),
                    label: const Text('Galería'),
                  ),
                ],
              ),
              if (_fotos.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(_fotos.length, (i) {
                    final xfile = _fotos[i].file;
                    return Padding(
                      padding: EdgeInsets.only(right: i < _fotos.length - 1 ? 8 : 0),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 80,
                              height: 80,
                              child: _PreviewImage(xfile: xfile),
                            ),
                          ),
                          Positioned(
                            bottom: -6,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                                ),
                                child: Text(
                                  _fotos[i].type == 'call_screenshot'
                                      ? 'Llamada'
                                      : (_fotos[i].type == 'door_photo' ? 'Puerta' : _fotos[i].type),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: IconButton.filled(
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(4),
                                minimumSize: const Size(28, 28),
                                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                                foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                              ),
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => _removePhoto(i),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ? null : _confirm,
          child: const Text('Guardar no entregado'),
        ),
      ],
    );
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.xfile});

  final XFile xfile;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: xfile.readAsBytes(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
          );
        }
        return const ColoredBox(
          color: Colors.grey,
          child: Center(child: Icon(Icons.image)),
        );
      },
    );
  }
}
