// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void removeHtmlSplashOverlay() {
  html.document.getElementById('splash')?.remove();
  html.document.getElementById('splash-branding')?.remove();
  html.document.body?.style.background = 'transparent';
}
