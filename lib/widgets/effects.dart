import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Effect played over the picture while one clip changes into the next.
enum TransFx { none, fire, lightning, sparkle, hearts, confetti }

const double _tau = math.pi * 2;

/// Repeatable pseudo-random number in 0..1 for (i, salt).
double _r(int i, int salt) {
  final x = math.sin(i * 127.1 + salt * 311.7) * 43758.5453;
  return x - x.floorToDouble();
}

double _frac(double x) => x - x.floorToDouble();

class _Pt {
  const _Pt(this.p, this.tan, this.nor);
  final Offset p; // point on the edge
  final Offset tan; // unit direction along the edge
  final Offset nor; // unit direction pointing away from the shape
}

/// About [n] points spread along [path], each with an outward direction.
List<_Pt> _edgePoints(Path path, int n) {
  final metrics = path.computeMetrics().toList();
  var total = 0.0;
  for (final m in metrics) {
    total += m.length;
  }
  final out = <_Pt>[];
  if (total <= 0) return out;
  for (final m in metrics) {
    final count = math.max(1, (n * m.length / total).round());
    for (var j = 0; j < count; j++) {
      final tg = m.getTangentForOffset((j + 0.5) * m.length / count);
      if (tg == null) continue;
      var nor = Offset(tg.vector.dy, -tg.vector.dx);
      if (path.contains(tg.position + nor * 4)) nor = -nor;
      out.add(_Pt(tg.position, tg.vector, nor));
    }
  }
  return out;
}

Path heartPathIn(Rect box) {
  final x = box.left, y = box.top, k = box.width;
  Offset pt(double a, double b) => Offset(x + k * a, y + k * b);
  final p0 = pt(0.5, 0.92);
  final a1 = pt(0.0, 0.58), a2 = pt(0.02, 0.12), a3 = pt(0.28, 0.12);
  final b1 = pt(0.42, 0.12), b2 = pt(0.5, 0.22), b3 = pt(0.5, 0.30);
  final c1 = pt(0.5, 0.22), c2 = pt(0.58, 0.12), c3 = pt(0.72, 0.12);
  final d1 = pt(0.98, 0.12), d2 = pt(1.0, 0.58);
  return Path()
    ..moveTo(p0.dx, p0.dy)
    ..cubicTo(a1.dx, a1.dy, a2.dx, a2.dy, a3.dx, a3.dy)
    ..cubicTo(b1.dx, b1.dy, b2.dx, b2.dy, b3.dx, b3.dy)
    ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, c3.dx, c3.dy)
    ..cubicTo(d1.dx, d1.dy, d2.dx, d2.dy, p0.dx, p0.dy)
    ..close();
}

// ---------------------------------------------------------------- fire

/// One flame: a tapering tongue growing from [b] along the unit direction [ax].
Path _tonguePath(Offset b, Offset ax, double w, double h, double lean, double wob) {
  final px = -ax.dy, py = ax.dx;
  final tip = Offset(b.dx + ax.dx * h + px * lean * h * 0.35, b.dy + ax.dy * h + py * lean * h * 0.35);
  final mx = b.dx + ax.dx * h * 0.45 + px * (lean * h * 0.12 + wob * h * 0.10);
  final my = b.dy + ax.dy * h * 0.45 + py * (lean * h * 0.12 + wob * h * 0.10);
  return Path()
    ..moveTo(b.dx - px * w / 2, b.dy - py * w / 2)
    ..cubicTo(b.dx - px * w * 0.62 + ax.dx * h * 0.18, b.dy - py * w * 0.62 + ax.dy * h * 0.18,
        mx - px * w * 0.34, my - py * w * 0.34, tip.dx, tip.dy)
    ..cubicTo(mx + px * w * 0.34, my + py * w * 0.34, b.dx + px * w * 0.62 + ax.dx * h * 0.18,
        b.dy + py * w * 0.62 + ax.dy * h * 0.18, b.dx + px * w / 2, b.dy + py * w / 2)
    ..close();
}

Paint _grad(Offset from, Offset to, List<Color> colors, List<double> stops, {double blur = 0, BlendMode? mode}) {
  final p = Paint()..shader = ui.Gradient.linear(from, to, colors, stops);
  if (blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
  if (mode != null) p.blendMode = mode;
  return p;
}

/// A soft halo plus three glowing layers (red, orange, yellow).
void _paintFlame(Canvas c, Offset b, Offset ax, double w, double h, double lean, double wob, double halo, double soft) {
  c.drawPath(
    _tonguePath(b, ax, w * 1.25, h * 1.05, lean, wob),
    _grad(b, b + ax * h, const [Color(0xBFFF4600), Color(0x00FF2800)], const [0, 1], blur: halo),
  );
  c.drawPath(
    _tonguePath(b, ax, w, h, lean, wob),
    _grad(b, b + ax * h, const [Color(0xF2EB3C00), Color(0xD9FF5F00), Color(0x00FF8200)], const [0, 0.55, 1], blur: soft),
  );
  c.drawPath(
    _tonguePath(b, ax, w * 0.68, h * 0.78, lean, wob),
    _grad(b, b + ax * (h * 0.78), const [Color(0xFAFF8700), Color(0xE0FFAF19), Color(0x00FFCD3C)], const [0, 0.6, 1], blur: soft),
  );
  c.drawPath(
    _tonguePath(b, ax, w * 0.38, h * 0.5, lean, wob),
    _grad(b, b + ax * (h * 0.5), const [Color(0xF2FFEB78), Color(0x99FFD750), Color(0x00FFF08C)], const [0, 0.7, 1],
        blur: soft, mode: BlendMode.plus),
  );
}

/// Flames growing up and out of the edge of a shape (the inside stays clear).
void paintFireEdge(Canvas c, Path shape, Size size, double t) {
  final minD = math.min(size.width, size.height);
  c.drawPath(
    shape,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = minD * 0.018
      ..color = const Color(0xE6FF780A)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, minD * 0.03),
  );
  final outside = Path.combine(
    PathOperation.difference,
    Path()..addRect((Offset.zero & size).inflate(minD)),
    shape,
  );
  final pts = _edgePoints(shape, 30);
  if (pts.isEmpty) return;
  final order = List<int>.generate(pts.length, (i) => i)
    ..sort((a, b) => pts[b].nor.dy.compareTo(pts[a].nor.dy)); // bottom flames first
  c.save();
  c.clipPath(outside);
  for (final j in order) {
    final nor = pts[j].nor;
    final up = ((-nor.dy + 0.35) / 1.35).clamp(0.0, 1.0).toDouble();
    final a0 = Offset(nor.dx * 0.9, nor.dy * 0.9 - up);
    final ax = a0 / a0.distance;
    final k = 1 + (_r(j, 1) * 2).floor();
    final f1 = 0.5 + 0.5 * math.sin(_tau * (k * t + _r(j, 2)));
    final f2 = 0.5 + 0.5 * math.sin(_tau * ((k + 1) * t + _r(j, 5)));
    final h = minD * 0.3 * (0.3 + 0.7 * up) * (0.6 + 0.4 * f1) * (0.8 + 0.35 * _r(j, 3)) * (0.9 + 0.2 * f2);
    final lean = math.sin(_tau * (t + _r(j, 4))) * 0.8 + nor.dx * 0.3;
    final wob = math.sin(_tau * (2 * t + _r(j, 6)));
    final w = minD * 0.115 * (0.85 + 0.35 * _r(j, 8));
    _paintFlame(c, pts[j].p, ax, w, h, lean, wob, minD * 0.013, minD * 0.0022);
  }
  c.restore();
  // Embers drifting up.
  for (var i = 0; i < 30; i++) {
    final u = _frac(_r(i, 41) + t);
    final pt = pts[(_r(i, 42) * pts.length).floor().clamp(0, pts.length - 1)];
    final upf = math.max(0.2, -pt.nor.dy + 0.5);
    final pos = pt.p +
        pt.nor * (minD * 0.02 + u * minD * 0.05) +
        Offset(math.sin(_tau * (t * 2 + _r(i, 43))) * minD * 0.02, -u * minD * 0.3 * upf);
    final alpha = math.max(0.0, 1 - u) * 0.95;
    c.drawCircle(
      pos,
      minD * (0.003 + 0.0045 * _r(i, 45)) * (1 - u * 0.6),
      Paint()..color = Color.fromRGBO(255, 160 + (70 * _r(i, 44)).floor(), 60, alpha),
    );
  }
}

// ------------------------------------------------------------- thunder

void _bolt(Canvas c, Offset from, Offset dir, double len, int seed, double w, int branches) {
  final perp = Offset(-dir.dy, dir.dx);
  const segs = 9;
  final pts = <Offset>[from];
  for (var k = 1; k <= segs; k++) {
    final j = (_r(k, seed) - 0.5) * len * 0.22 * (k == segs ? 0.3 : 1.0);
    pts.add(from + dir * (len * k / segs) + perp * j);
  }
  final path = Path()..moveTo(from.dx, from.dy);
  for (final q in pts.skip(1)) {
    path.lineTo(q.dx, q.dy);
  }
  Paint stroke(double width, Color color, {double blur = 0}) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    if (blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    return p;
  }

  c.drawPath(path, stroke(w * 5, const Color(0x8C50AAFF), blur: w * 2));
  c.drawPath(path, stroke(w * 2, const Color(0xE6BEE1FF)));
  c.drawPath(path, stroke(w, Colors.white));
  if (branches > 0) {
    for (var b = 0; b < 2; b++) {
      final q = pts[2 + (_r(b, seed + 3) * 4).floor()];
      final ang = 0.6 * (b == 0 ? 1 : -1) + (_r(b, seed + 5) - 0.5) * 0.4;
      final nd = Offset(dir.dx * math.cos(ang) - dir.dy * math.sin(ang), dir.dx * math.sin(ang) + dir.dy * math.cos(ang));
      _bolt(c, q, nd, len * 0.38, seed + 11 + b, w * 0.7, branches - 1);
    }
  }
}

/// Crackling electricity along the edge of a shape.
void paintThunderEdge(Canvas c, Path shape, Size size, double t) {
  final minD = math.min(size.width, size.height);
  final step = (t * 20).floor();
  final fl = 0.45 + 0.55 * _r(step, 11);
  c.drawPath(
    shape,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = minD * 0.02
      ..color = const Color(0xFF50AAFF).withOpacity(0.9 * fl)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, minD * 0.025),
  );
  c.drawPath(
    shape,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = minD * 0.012
      ..color = const Color(0xFF96D2FF).withOpacity(0.6 + 0.4 * fl),
  );
  c.drawPath(
    shape,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = minD * 0.004
      ..color = Colors.white,
  );
  final pts = _edgePoints(shape, 60);
  if (pts.isEmpty) return;
  for (var j = 0; j < 7; j++) {
    if (_r(j + step * 13, 5) < 0.3) continue;
    final pt = pts[(_r(j + step * 7, 6) * pts.length).floor().clamp(0, pts.length - 1)];
    final ang = (_r(j + step * 3, 8) - 0.5) * 0.9;
    final dir = Offset(
      pt.nor.dx * math.cos(ang) - pt.nor.dy * math.sin(ang),
      pt.nor.dx * math.sin(ang) + pt.nor.dy * math.cos(ang),
    );
    _bolt(c, pt.p, dir, minD * (0.09 + 0.10 * _r(j + step, 7)), j * 31 + step, minD * 0.006, 1);
  }
}

// ------------------------------------------------------------ sparkles

void _star(Canvas c, Offset ctr, double r) {
  final path = Path();
  for (var i = 0; i < 8; i++) {
    final rad = i.isEven ? r : r * 0.22;
    final a = -math.pi / 2 + i * math.pi / 4;
    final p = Offset(ctr.dx + rad * math.cos(a), ctr.dy + rad * math.sin(a));
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  path.close();
  c.drawCircle(
    ctr,
    r * 0.9,
    Paint()
      ..color = const Color(0x55FFE9A0)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.6),
  );
  c.drawPath(path, Paint()..color = Colors.white);
}

double _twinkle(int i, double t, int salt) {
  final k = 1 + (_r(i, salt) * 2).floor();
  final v = math.max(0.0, math.sin(math.pi * _frac(t * k + _r(i, salt + 1))));
  return v * v;
}

/// Twinkling stars around the edge of a shape.
void paintSparkleEdge(Canvas c, Path shape, Size size, double t) {
  final minD = math.min(size.width, size.height);
  final pts = _edgePoints(shape, 70);
  if (pts.isEmpty) return;
  for (var i = 0; i < 24; i++) {
    final pt = pts[(_r(i, 3) * pts.length).floor().clamp(0, pts.length - 1)];
    final pos = pt.p + pt.nor * (minD * 0.03 * _r(i, 4));
    final r = minD * (0.02 + 0.03 * _r(i, 5)) * _twinkle(i, t, 6);
    if (r > 0.5) _star(c, pos, r);
  }
}

// --------------------------------------------------------- transitions

/// Where the edge of the fire wipe is for progress [p] (the new clip is revealed below it).
double fireFrontY(double height, double p) => height * (1 - p);

/// Draws the effect of a transition over the picture. [p] goes 0..1 during the transition.
void paintTransFx(Canvas c, Size s, TransFx fx, double p) {
  final minD = math.min(s.width, s.height);
  switch (fx) {
    case TransFx.none:
      break;
    case TransFx.fire:
      final front = fireFrontY(s.height, p) + s.height * 0.012;
      final grow = math.min(1.0, math.min(p * 5, (1 - p) * 5));
      final band = Rect.fromLTWH(0, front - s.height * 0.08, s.width, s.height * 0.2);
      c.drawRect(
        band,
        Paint()
          ..shader = ui.Gradient.linear(band.topCenter, band.bottomCenter,
              const [Color(0x00FF5000), Color(0x8CFF6E00), Color(0x00781400)], const [0, 0.55, 1]),
      );
      const n = 13;
      final tt = p * 3;
      for (var j = 0; j < n; j++) {
        final f1 = 0.5 + 0.5 * math.sin(_tau * (2 * tt + _r(j, 2)));
        final h = s.height * 0.17 * (0.55 + 0.45 * f1) * (0.8 + 0.4 * _r(j, 3)) * grow;
        final lean = math.sin(_tau * (tt + _r(j, 4))) * 0.8;
        final w = s.width / n * 1.9 * (0.85 + 0.3 * _r(j, 8));
        final x = (j + 0.5) * s.width / n + math.sin(_tau * (p * 2 + _r(j, 9))) * minD * 0.015;
        if (h > 1) {
          _paintFlame(c, Offset(x, front), const Offset(0, -1), w, h, lean, math.sin(_tau * (p * 6 + _r(j, 6))),
              minD * 0.013, minD * 0.0022);
        }
      }
      for (var i = 0; i < 22; i++) {
        final u = _frac(_r(i, 41) + p * 2);
        final pos = Offset(s.width * _r(i, 42) + math.sin(_tau * (p * 3 + _r(i, 43))) * minD * 0.02,
            front - u * s.height * 0.3);
        c.drawCircle(pos, minD * (0.003 + 0.004 * _r(i, 45)) * (1 - u * 0.6),
            Paint()..color = Color.fromRGBO(255, 170, 50, math.max(0.0, 1 - u) * grow));
      }
    case TransFx.lightning:
      final flash = math.sin(math.pi * p);
      c.drawRect(Offset.zero & s, Paint()..color = Colors.white.withOpacity(0.25 * flash * flash));
      if (p > 0.18 && p < 0.82) {
        final step = (p * 14).floor();
        final x0 = s.width * (0.25 + 0.5 * _r(step, 21));
        final d = Offset(0.3 * (_r(step, 22) - 0.5), 1);
        _bolt(c, Offset(x0, -10), d / d.distance, s.height * 0.8, step * 17, s.width * 0.012, 2);
      }
    case TransFx.sparkle:
      final life = math.sin(math.pi * p);
      for (var i = 0; i < 30; i++) {
        final u = _frac(p * (1 + i % 2) + _r(i, 61));
        final v = math.sin(math.pi * u);
        final r = minD * (0.03 + 0.05 * _r(i, 62)) * v * v * life;
        if (r > 0.5) _star(c, Offset(s.width * _r(i, 63), s.height * _r(i, 64)), r);
      }
    case TransFx.hearts:
      const colors = [Color(0xFFFF4D8D), Color(0xFFFF7AB2), Color(0xFFFF2D55), Color(0xFFFFB3D1)];
      for (var i = 0; i < 16; i++) {
        final q = p * (0.8 + 0.5 * _r(i, 9)) + _r(i, 10) * 0.2;
        final pos = Offset(s.width * _r(i, 2) + math.sin(_tau * (q * 2 + _r(i, 3))) * s.width * 0.03,
            s.height * (1.1 - 1.3 * q));
        final size = minD * (0.05 + 0.07 * _r(i, 4));
        c.drawPath(
          heartPathIn(Rect.fromCenter(center: pos, width: size, height: size)),
          Paint()..color = colors[i % colors.length].withOpacity(0.9 * math.sin(math.pi * p)),
        );
      }
    case TransFx.confetti:
      const colors = [
        Color(0xFFFF3B30), Color(0xFFFFCC00), Color(0xFF34C759),
        Color(0xFF00C7FF), Color(0xFF5856FF), Color(0xFFFF2D95),
      ];
      final sc = minD / 360;
      for (var i = 0; i < 60; i++) {
        final q = p * (0.9 + 0.5 * _r(i, 1)) + _r(i, 7) * 0.25;
        final pos = Offset(s.width * _r(i, 2) + math.sin(_tau * (q * 2 + _r(i, 3))) * s.width * 0.03,
            s.height * (-0.1 + 1.3 * q));
        final w = (4 + 5 * _r(i, 4)) * sc;
        c.save();
        c.translate(pos.dx, pos.dy);
        c.rotate(_tau * (p * (1 + i % 3) * 2 + _r(i, 5)));
        c.drawRect(Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.5),
            Paint()..color = colors[i % colors.length].withOpacity(math.min(1.0, math.sin(math.pi * p) * 2)));
        c.restore();
      }
  }
}

/// Paints [fx] for the live preview and for exported frames.
class TransFxPainter extends CustomPainter {
  const TransFxPainter(this.fx, this.p);

  final TransFx fx;
  final double p;

  @override
  void paint(Canvas canvas, Size size) => paintTransFx(canvas, size, fx, p);

  @override
  bool shouldRepaint(TransFxPainter old) => old.fx != fx || old.p != p;
}
