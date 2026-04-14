import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/widgets/adaptive_button_row.dart';
import 'package:flutter_signature_pad/flutter_signature_pad.dart';

/// Pantalla full-screen para capturar una firma.
/// Retorna un String base64 (PNG) por Navigator.pop cuando el usuario confirma.
class FirmaEntregaScreen extends StatefulWidget {
  const FirmaEntregaScreen({super.key});

  @override
  State<FirmaEntregaScreen> createState() => _FirmaEntregaScreenState();
}

class _FirmaEntregaScreenState extends State<FirmaEntregaScreen> {
  final _signKey = GlobalKey<SignatureState>();
  bool _hasSignature = false;

  Future<void> _confirmar() async {
    final sign = _signKey.currentState;
    if (sign == null) return;
    if (!sign.hasPoints) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todavía no hay firma.')),
      );
      return;
    }

    final image = await sign.getData();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return;
    final bytes = data.buffer.asUint8List();
    final base64Png = base64Encode(bytes);
    if (!mounted) return;
    Navigator.of(context).pop(base64Png);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firmar'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Center(
                child: Signature(
                  key: _signKey,
                  color: Colors.black,
                  strokeWidth: 3.0,
                  onSign: () {
                    final sign = _signKey.currentState;
                    final has = sign?.hasPoints ?? false;
                    if (mounted) setState(() => _hasSignature = has);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: AdaptiveButtonRow(
              spacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    final sign = _signKey.currentState;
                    sign?.clear();
                    if (mounted) setState(() => _hasSignature = false);
                  },
                  icon: const Icon(Icons.clear_outlined),
                  label: const Text(
                    'Limpiar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _hasSignature ? _confirmar : null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text(
                    'Confirmar firma',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancelar'),
            ),
          ),
        ],
      ),
    );
  }
}

