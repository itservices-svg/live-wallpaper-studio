import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/scenes.dart';

/// Paints a [Scene] (sky, sun, sea, drifting waves). Set [animate] to loop
/// the waves; the loop is seamless because every layer uses a whole number
/// of cycles per loop.
class SceneView extends StatefulWidget {
  const SceneView({super.key, required this.scene, this.animate = false});

  final Scene scene;
  final bool animate;

  @override
  State<SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends State<SceneView> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 8));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SceneView old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.animate) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => SizedBox.expand(
          child: CustomPaint(painter: _ScenePainter(widget.scene, _c.value)),
        ),
      ),
    );
  }
}

class _Wave {
  const _Wave(this.top, this.amp, this.cycles, this.speed, this.useSky, this.opacity);
  final double top; // fraction of height
  final double amp; // fraction of height
  final int cycles;
  final int speed; // whole number, negative = reverse
  final bool useSky; // true: sea[0], false: sea[1]
  final double opacity;
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.t);

  final Scene scene;
  final double t;

  static const _waves = <_Wave>[
    _Wave(0.51, 0.012, 3, 1, true, 0.6),
    _Wave(0.58, 0.014, 4, -2, true, 0.85),
    _Wave(0.68, 0.018, 3, 3, false, 1.0),
    _Wave(0.80, 0.020, 2, -2, false, 0.7),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [scene.sky[0], scene.sky[1], scene.sky[2]],
          stops: const [0.0, 0.44, 0.6],
        ).createShader(rect),
    );

    final c = Offset(size.width / 2, size.height * 0.46);
    final r = size.width * 0.23;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [scene.sun.withOpacity(0.9), scene.sun.withOpacity(0)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    final seaRect = Rect.fromLTRB(0, size.height * 0.55, size.width, size.height);
    canvas.drawRect(
      seaRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [scene.sea[0], scene.sea[1]],
        ).createShader(seaRect),
    );

    for (final w in _waves) {
      final path = Path()..moveTo(0, size.height);
      final base = size.height * w.top;
      final amp = size.height * w.amp;
      for (double x = 0; x <= size.width + 4; x += 4) {
        final y = base +
            math.sin((x / size.width) * 2 * math.pi * w.cycles +
                    t * 2 * math.pi * w.speed) *
                amp;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
      final color = (w.useSky ? scene.sea[0] : scene.sea[1]).withOpacity(w.opacity);
      canvas.drawPath(path, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.t != t || old.scene != scene;
}
