import 'dart:math';
import 'package:flutter/material.dart';

/// Loader “pez en órbita” (misma idea que `fish-loader.html` en web).
class FishLoader extends StatefulWidget {
  const FishLoader({super.key});

  @override
  State<FishLoader> createState() => _FishLoaderState();
}

class _FishLoaderState extends State<FishLoader> with TickerProviderStateMixin {
  late final AnimationController _orbit =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();
  late final AnimationController _wag =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 400))..repeat(reverse: true);
  late final AnimationController _dot =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  late final AnimationController _glow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
  late final AnimationController _chip =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  late final AnimationController _bits =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();

  @override
  void dispose() {
    _orbit.dispose();
    _wag.dispose();
    _dot.dispose();
    _glow.dispose();
    _chip.dispose();
    _bits.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 160,
          height: 160,
          child: AnimatedBuilder(
            animation: Listenable.merge([_orbit, _wag, _bits, _chip]),
            builder: (_, __) => CustomPaint(
              painter: _FishOrbitPainter(
                orbit: _orbit.value,
                wag: _wag.value,
                bits: _bits.value,
                chip: _chip.value,
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        AnimatedBuilder(
          animation: _glow,
          builder: (_, __) {
            final blur = 8.0 + _glow.value * 10;
            return Text(
              'INSUMOS ACUARIO',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                color: Colors.white,
                shadows: [
                  Shadow(color: const Color(0xFF00E5FF), blurRadius: blur),
                  Shadow(color: const Color(0x6600E5FF), blurRadius: blur * 2),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'INSUMOS Y TECNOLOGÍA',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 4.5,
            color: Color(0x8000DCFF),
          ),
        ),
        const SizedBox(height: 20),
        AnimatedBuilder(
          animation: _dot,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final t = (_dot.value - i * 0.2).clamp(0.0, 1.0);
              final scale = t < 0.4
                  ? 0.4 + (t / 0.4) * 0.7
                  : 1.1 - ((t - 0.4) / 0.6) * 0.7;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Transform.scale(
                  scale: scale.clamp(0.4, 1.1),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF00E5FF),
                      boxShadow: [BoxShadow(color: Color(0xFF00E5FF), blurRadius: 6)],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _FishOrbitPainter extends CustomPainter {
  final double orbit, wag, bits, chip;
  const _FishOrbitPainter({
    required this.orbit,
    required this.wag,
    required this.bits,
    required this.chip,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 14;

    _grid(canvas, size);
    _track(canvas, c, r);
    _chips(canvas, size);
    _floatingBits(canvas, c, r);
    _fish(canvas, c, r);
  }

  void _grid(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF00C8FF).withOpacity(0.04)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 16) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 16) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  void _track(Canvas canvas, Offset c, double r) {
    final dash = Paint()
      ..color = const Color(0xFF00DCE5).withOpacity(0.18)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const n = 28;
    const step = 2 * pi / n;
    for (int i = 0; i < n; i += 2) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        i * step,
        step * 0.6,
        false,
        dash,
      );
    }

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r + 4),
      orbit * 2 * pi - 0.4,
      0.4,
      false,
      Paint()
        ..color = const Color(0xFF00DCE5).withOpacity(0.55)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  void _chips(Canvas canvas, Size size) {
    final op = 0.3 + chip * 0.7;
    final border = Paint()
      ..color = const Color(0xFF00DCE5).withOpacity(op * 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = const Color(0xFF00DCE5).withOpacity(op * 0.8);
    final glow = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(op * 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    for (final pos in [
      Offset(20, 20),
      Offset(size.width - 20, 20),
      Offset(20, size.height - 20),
      Offset(size.width - 20, size.height - 20),
    ]) {
      final rr = RRect.fromRectAndRadius(
        Rect.fromCenter(center: pos, width: 9, height: 9),
        const Radius.circular(1.5),
      );
      if (op > 0.5) canvas.drawRRect(rr, glow);
      canvas.drawRRect(rr, border);
      canvas.drawCircle(pos, 1.5, dot);
    }
  }

  void _floatingBits(Canvas canvas, Offset c, double r) {
    const cfg = [
      (text: '1', da: 0.00, delay: 0.0),
      (text: '0', da: 0.18, delay: 0.4),
      (text: '1', da: -0.18, delay: 0.8),
      (text: '0', da: 0.35, delay: 1.2),
    ];

    for (final b in cfg) {
      final t = ((bits - b.delay / 2.0) % 1.0).clamp(0.0, 1.0);
      if (t < 0.05) continue;
      final op = t < 0.2 ? t / 0.2 * 0.8 : (1 - t) * 0.8;
      final angle = -pi / 2 + b.da;
      final pos = Offset(
        c.dx + (r - 8) * cos(angle),
        c.dy + (r - 8) * sin(angle) - t * 36,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: b.text,
          style: TextStyle(
            color: const Color(0xFF00DCE5).withOpacity(op),
            fontSize: 10,
            shadows: [Shadow(color: const Color(0xFF00E5FF).withOpacity(op), blurRadius: 6)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _fish(Canvas canvas, Offset c, double r) {
    final angle = orbit * 2 * pi - pi / 2;
    final pos = Offset(c.dx + r * cos(angle), c.dy + r * sin(angle));

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle + pi / 2);
    _drawFishShape(canvas);
    canvas.restore();
  }

  void _drawFishShape(Canvas canvas) {
    final wagAngle = (wag - 0.5) * (pi / 2.5);
    canvas.save();
    canvas.translate(-12, 0);
    canvas.rotate(wagAngle);
    final tail = Path()
      ..moveTo(0, 0)
      ..lineTo(-14, -11)
      ..lineTo(-14, 11)
      ..close();
    canvas.drawPath(
      tail,
      Paint()
        ..color = const Color(0xFF00E5FF).withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(tail, Paint()..color = const Color(0xFF00B8D9));
    canvas.restore();

    canvas.drawOval(
      const Rect.fromLTWH(-12, -11, 30, 22),
      Paint()
        ..color = const Color(0xFF00E5FF).withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    const bodyRect = Rect.fromLTWH(-12, -11, 30, 22);
    canvas.drawOval(
      bodyRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF00E5FF), Color(0xFF0077B6)],
        ).createShader(bodyRect),
    );

    canvas.drawOval(
      const Rect.fromLTWH(-5, 3, 16, 5),
      Paint()..color = Colors.white.withOpacity(0.2),
    );

    final circuit = Paint()
      ..color = Colors.white.withOpacity(0.45)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(-4, -3), const Offset(6, -3), circuit);
    canvas.drawLine(const Offset(-4, -3), const Offset(-4, 1), circuit);
    canvas.drawLine(const Offset(2, -3), const Offset(2, 1), circuit);

    canvas.drawPath(
      Path()
        ..moveTo(0, -11)
        ..lineTo(4, -19)
        ..lineTo(10, -11)
        ..close(),
      Paint()..color = const Color(0xFF00B8D9),
    );

    canvas.drawCircle(
      const Offset(12, -4),
      4,
      Paint()..color = const Color(0xFF050D1A),
    );
    canvas.drawCircle(
      const Offset(12, -4),
      4,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(const Offset(13, -5), 1.3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_FishOrbitPainter o) =>
      o.orbit != orbit || o.wag != wag || o.bits != bits || o.chip != chip;
}
