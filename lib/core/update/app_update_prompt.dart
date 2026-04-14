import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../prefs_keys.dart';
import 'app_update_info.dart';
import 'app_update_service.dart';

/// Comprueba actualización en Android (Firestore) y muestra un diálogo si aplica.
class AppUpdatePrompt {
  AppUpdatePrompt._();

  static bool _sessionChecked = false;

  static Future<void> maybeShow(BuildContext context) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_sessionChecked) return;
    _sessionChecked = true;

    final info = await appUpdateCheck();
    if (info == null || !context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: !info.isForced,
      builder: (ctx) => _UpdateDialog(info: info),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});

  final AppUpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double? _progress;

  Future<void> _onLater() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      PrefsKeys.dismissedAppUpdateVersionCode,
      widget.info.latestVersionCode,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _onDownload() async {
    setState(() {
      _downloading = true;
      _progress = null;
    });
    try {
      await appUpdateDownloadAndInstall(
        widget.info.apkUrl,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            if (p >= 0 && p <= 1) {
              _progress = p;
            } else {
              _progress = null;
            }
          });
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      debugPrint('app update: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final notes = info.releaseNotes?.trim();

    return PopScope(
      canPop: !info.isForced,
      child: AlertDialog(
        title: const Text('Nueva versión disponible'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Versión instalada: ${info.currentVersionCode}\n'
                'Última publicada: ${info.latestVersionCode}',
              ),
              if (notes != null && notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(notes),
              ],
              if (_downloading) ...[
                const SizedBox(height: 16),
                if (_progress != null)
                  LinearProgressIndicator(value: _progress)
                else
                  const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
        actions: [
          if (!info.isForced && !_downloading)
            TextButton(
              onPressed: _onLater,
              child: const Text('Más tarde'),
            ),
          FilledButton(
            onPressed: _downloading ? null : _onDownload,
            child: Text(info.isForced ? 'Descargar e instalar' : 'Actualizar'),
          ),
        ],
      ),
    );
  }
}
