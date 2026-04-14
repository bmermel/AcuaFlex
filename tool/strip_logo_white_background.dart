// Ejecutar desde la raíz del proyecto:
//   dart run tool/strip_logo_white_background.dart
// Lee assets/images/logo_acuaflex_src.png y escribe assets/images/logo_acuaflex.png
// (fondo blanco / gris muy claro → transparente).

import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final root = Directory.current.path;
  final src = File('$root/assets/images/logo_acuaflex_src.png');
  if (!src.existsSync()) {
    stderr.writeln('No existe ${src.path}');
    exit(1);
  }
  final raw = src.readAsBytesSync();
  final image = img.decodeImage(raw);
  if (image == null) {
    stderr.writeln('No se pudo decodificar la imagen');
    exit(1);
  }

  const threshold = 238; // píxeles más claros → transparentes

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      if (r >= threshold && g >= threshold && b >= threshold) {
        image.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0));
      }
    }
  }

  final out = File('$root/assets/images/logo_acuaflex.png');
  out.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('OK → ${out.path}');
}
