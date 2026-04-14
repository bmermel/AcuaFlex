import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Oculta la barra de navegación del sistema (abajo) en Android.
/// El usuario puede deslizar desde abajo para mostrarla de forma temporal.
/// En iOS/web no se modifica (evita efectos raros con el indicador de inicio).
void applyHideBottomSystemNavigationBar() {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.android) return;
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );
}
