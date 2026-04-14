// Ejecutar desde la raíz del proyecto:
//   dart run tool/strip_logo_black_background.dart
// Lee assets/images/logo_acuaflex.png y lo sobrescribe: el fondo negro
// conectado a los bordes pasa a transparente (flood-fill desde el borde).

import 'dart:collection';
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final root = Directory.current.path;
  final path = '$root/assets/images/logo_acuaflex.png';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('No existe $path');
    exit(1);
  }
  final decoded = img.decodeImage(file.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('No se pudo decodificar la imagen');
    exit(1);
  }
  final img.Image image = decoded.numChannels < 4
      ? decoded.convert(numChannels: 4, alpha: 255)
      : decoded;

  final w = image.width;
  final h = image.height;
  final bg = image.getPixel(0, 0);
  const tolerance = 45; // suma |ΔR|+|ΔG|+|ΔB| para considerar "mismo fondo"

  bool similar(img.Pixel a, img.Pixel b) {
    final d = (a.r.toInt() - b.r.toInt()).abs() +
        (a.g.toInt() - b.g.toInt()).abs() +
        (a.b.toInt() - b.b.toInt()).abs();
    return d <= tolerance;
  }

  final removed = List.generate(h, (_) => List<bool>.filled(w, false));
  final q = Queue<(int, int)>();

  void tryAdd(int x, int y) {
    if (x < 0 || x >= w || y < 0 || y >= h) return;
    if (removed[y][x]) return;
    if (!similar(image.getPixel(x, y), bg)) return;
    removed[y][x] = true;
    q.add((x, y));
  }

  for (var x = 0; x < w; x++) {
    tryAdd(x, 0);
    tryAdd(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    tryAdd(0, y);
    tryAdd(w - 1, y);
  }

  while (q.isNotEmpty) {
    final (x, y) = q.removeFirst();
    image.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0));
    tryAdd(x - 1, y);
    tryAdd(x + 1, y);
    tryAdd(x, y - 1);
    tryAdd(x, y + 1);
  }

  file.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('OK → $path (fondo negro desde bordes → transparente)');
}
