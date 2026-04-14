/// Datos de una actualización disponible (Android, Firestore `config/android_update`).
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersionCode,
    required this.latestVersionCode,
    required this.apkUrl,
    this.minVersionCode,
    this.releaseNotes,
  });

  final int currentVersionCode;
  final int latestVersionCode;
  final int? minVersionCode;
  final String apkUrl;
  final String? releaseNotes;

  bool get isForced =>
      minVersionCode != null && currentVersionCode < minVersionCode!;
}
