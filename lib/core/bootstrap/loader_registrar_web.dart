// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

void registerLoaderViewIfWeb() {
  ui_web.platformViewRegistry.registerViewFactory(
    'acua-css-loader',
    (int viewId) {
      final source =
          html.document.querySelector('#splash .acua-loader-stack');
      if (source != null) {
        return source.clone(true) as html.DivElement;
      }
      final fallback = html.DivElement()..className = 'acua-loader-stack';
      fallback.text = 'Cargando…';
      return fallback;
    },
  );
}
