import 'dart:io' show File, Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../prefs_keys.dart';
import 'app_update_info.dart';

Future<AppUpdateInfo?> appUpdateCheck() async {
  if (!Platform.isAndroid) return null;

  final pkg = await PackageInfo.fromPlatform();
  final current = int.tryParse(pkg.buildNumber) ?? 0;

  DocumentSnapshot<Map<String, dynamic>> snap;
  try {
    snap = await FirebaseFirestore.instance
        .collection('config')
        .doc('android_update')
        .get();
  } catch (_) {
    return null;
  }
  if (!snap.exists) return null;

  final data = snap.data();
  if (data == null) return null;

  final latest = data['latestVersionCode'];
  final url = data['apkUrl'];
  if (latest is! int || url is! String || url.trim().isEmpty) return null;

  if (current >= latest) return null;

  final minVc = data['minVersionCode'] is int ? data['minVersionCode'] as int : null;
  final forced = minVc != null && current < minVc;

  final prefs = await SharedPreferences.getInstance();
  final dismissed = prefs.getInt(PrefsKeys.dismissedAppUpdateVersionCode) ?? -1;
  if (!forced && dismissed == latest) return null;

  return AppUpdateInfo(
    currentVersionCode: current,
    latestVersionCode: latest,
    minVersionCode: minVc,
    apkUrl: url.trim(),
    releaseNotes: data['releaseNotes'] is String ? data['releaseNotes'] as String : null,
  );
}

Future<void> appUpdateDownloadAndInstall(
  String apkUrl, {
  void Function(double progress)? onProgress,
}) async {
  if (!Platform.isAndroid) return;

  final perm = await Permission.requestInstallPackages.request();
  if (!perm.isGranted) {
    throw StateError(
      'Se necesita permiso para instalar actualizaciones. Actívalo en Ajustes de la app.',
    );
  }

  final uri = Uri.tryParse(apkUrl);
  if (uri == null || !uri.hasScheme) {
    throw StateError('URL del APK no válida.');
  }

  final client = http.Client();
  try {
    final request = http.Request('GET', uri);
    final streamed = await client.send(request);
    if (streamed.statusCode != 200) {
      throw StateError('Error al descargar (código ${streamed.statusCode}).');
    }

    final total = streamed.contentLength;
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'acuaflex_update.apk'));
    onProgress?.call(-1);
    final sink = file.openWrite();
    var received = 0;

    await for (final chunk in streamed.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total != null && total > 0) {
        onProgress?.call(received / total);
      }
    }
    await sink.close();
    onProgress?.call(1);

    final result = await OpenFile.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      final msg = result.message;
      throw StateError(
        msg.isEmpty ? 'No se pudo abrir el instalador.' : msg,
      );
    }
  } finally {
    client.close();
  }
}
