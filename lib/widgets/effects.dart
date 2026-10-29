import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Full-picture effects drawn over the GIF (like the effects in video editors).
enum FxEffect { none, fire, thunder, sparkle, snow, rain, hearts, confetti }

const kFxLabels = ['None', 'Fire', 'Thunder', 'Sparkle', 'Snow', 'Rain', 'Hearts', 'Confetti'];

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

void _flame(Canvas c, _Pt pt, double w, double h, double sway) {
  Path shape(double sw, double sh) {
    final base = pt.p;
    final a = base - pt.tan * (sw / 2);
    final b = base + pt.tan * (sw / 2);
    final lean = pt.tan * (sway * sh * 0.12);
    final tip = base + pt.nor * sh + pt.tan * (sway * sh * 0.22);
    final cl = base - pt.tan * (sw * 0.75) + pt.nor * (sh * 0.5) + lean;
    final cr = base + pt.tan * (sw * 0.75) + pt.nor * (sh * 0.5) + lean;
    return Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(cl.dx, cl.dy, tip.dx, tip.dy)
      ..quadraticBezierTo(cr.dx, cr.dy, b.dx, b.dy)
      ..close();
  }

  c.drawPath(
    shape(w, h),
    Paint()
      ..color = const Color(0xCCFF3B00)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
  );
  c.drawPath(shape(w * 0.7, h * 0.72), Paint()..color = const Color(0xDDFF9500));
  c.drawPath(shape(w * 0.4, h * 0.45), Paint()..color = const Color(0xEEFFE066));
}

void _flames(Canvas c, List<_Pt> pts, double t, double w, double h, int seed) {
  for (var j = 0; j < pts.length; j++) {
    final k = 1 + (_r(j, seed + 1) * 3).floor();
    final flick = 0.5 + 0.5 * math.sin(_tau * (k * t + _r(j, seed + 2)));
    final hh = h * (0.55 + 0.6 * flick) * (0.8 + 0.4 * _r(j, seed + 3));
    final sway = math.sin(_tau * (t + _r(j, seed + 4)));
    _flame(c, pts[j], w, hh, sway);
  }
}

/// Flames licking outwards from the edge of a shape.
void paintFireEdge(Canvas c, Path shape, Size size, double t) {
  final minD = math.min(size.width, size.height);
  final pts = _edgePoints(shape, (minD / 9).round().clamp(26, 90));
  if (pts.isEmpty) return;
  final w = minD * 0.09;
  _flames(c, pts, t, w, minD * 0.12, 3);
}

void _fireScreen(Canvas c, Size s, double t) {
  final glow = Rect.fromLTWH(0, s.height * 0.7, s.width, s.height * 0.3);
  c.drawRect(
    glow,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Color(0x66FF5A00), Color(0x00FF5A00)],
      ).createShader(glow),
  );
  const n = 18;
  final pts = [
    for (var i = 0; i < n; i++)
      _Pt(Offset((i + 0.5) * s.width / n, s.height + 2), const Offset(1, 0), const Offset(0, -1)),
  ];
  _flames(c, pts, t, s.width / n * 2.1, s.height * 0.2, 9);
  for (var i = 0; i < 18; i++) {
    final u = _frac(_r(i, 41) + t);
    final x = s.width * _r(i, 42) + math.sin(_tau * (t + _r(i, 43))) * s.width * 0.02;
    final y = s.height * (1 - u * 0.75);
    final a = (1 - u).clamp(0.0, 1.0);
    c.drawCircle(
      Offset(x, y),
      s.width * (0.004 + 0.006 * _r(i, 44)),
      Paint()..color = Color.fromRGBO(255, 170, 40, a),
    );
  }
}

// ------------------------------------------------------------- thunder

void _bolt(Canvas c, Offset from, Offset dir, double len, int seed, double width) {
  final perp = Offset(-dir.dy, dir.dx);
  final path = Path()..moveTo(from.dx, from.dy);
  const segs = 7;
  for (var s = 1; s <= segs; s++) {
    final jitter = (_r(s, seed) - 0.5) * len * 0.3 * (s == segs ? 0.4 : 1.0);
    final p = from + dir * (len * s / segs) + perp * jitter;
    path.lineTo(p.dx, p.dy);
  }
  c.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 3
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0x8838BDF8)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 1.5),
  );
  c.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white,
  );
}

/// Crackling electricity around the edge of a shape.
void paintThunderEdge(Canvas c, Path shape, Size size, double t) {
  final minD = math.min(size.width, size.height);
  final step = (t * 20).floor();
  final fl = 0.35 + 0.65 * _r(step, 11);
  c.drawPath(
    shape,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = minD * 0.02
      ..color = const Color(0xFF38BDF8).withOpacity(fl * 0.8)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, minD * 0.015),
  );
  c.drawPath(
    shape,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = minD * 0.006
      ..color = Colors.white.withOpacity(0.5 + 0.5 * fl),
  );
  final pts = _edgePoints(shape, 40);
  if (pts.isEmpty) return;
  for (var j = 0; j < 10; j++) {
    if (_r(j + step * 13, 5) < 0.4) continue;
    final idx = (_r(j + step * 7, 6) * pts.length).floor().clamp(0, pts.length - 1);
    _bolt(c, pts[idx].p, pts[idx].nor, minD * (0.07 + 0.08 * _r(j + step, 7)), j * 31 + step, minD * 0.006);
  }
}

void _thunderScreen(Canvas c, Size s, double t) {
  const starts = [0.10, 0.52];
  for (var f = 0; f < starts.length; f++) {
    var u = t - starts[f];
    if (u < 0) u += 1;
    if (u >= 0.12) continue;
    final inten = 1 - u / 0.12;
    c.drawRect(
      Offset.zero & s,
      Paint()..color = Colors.white.withOpacity(0.3 * inten),
    );
    final step = (u * 40).floor();
    final x0 = s.width * (0.2 + 0.6 * _r(f, 21));
    final d = Offset(0.25 * (_r(f, 22) - 0.5), 1);
    final dir = d / d.distance;
    final len = s.height * 0.75;
    final w = s.width * 0.012;
    _bolt(c, Offset(x0, 0), dir, len, f * 17 + step, w);
    final mid = Offset(x0, 0) + dir * (len * 0.45);
    final d2 = Offset(dir.dx + 0.7 * (f.isEven ? 1 : -1), dir.dy);
    _bolt(c, mid, d2 / d2.distance, len * 0.35, f * 29 + step, w * 0.7);
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

void _sparkleScreen(Canvas c, Size s, double t) {
  final minD = math.min(s.width, s.height);
  for (var i = 0; i < 28; i++) {
    final pos = Offset(s.width * _r(i, 51), s.height * _r(i, 52));
    final r = minD * (0.02 + 0.035 * _r(i, 53)) * _twinkle(i, t, 54);
    if (r > 0.5) _star(c, pos, r);
  }
}

// ----------------------------------------------------- falling particles

void _snow(Canvas c, Size s, double t) {
  final sc = math.min(s.width, s.height) / 360;
  for (var i = 0; i < 70; i++) {
    final k = 1 + i % 2;
    final y = _frac(_r(i, 1) + t * k) * (s.height + 20) - 10;
    final x = s.width * _r(i, 2) + math.sin(_tau * (t * k + _r(i, 3))) * s.width * 0.02;
    c.drawCircle(
      Offset(x, y),
      (1.2 + 2.6 * _r(i, 4)) * sc,
      Paint()..color = Colors.white.withOpacity(0.55 + 0.4 * _r(i, 5)),
    );
  }
}

void _rain(Canvas c, Size s, double t) {
  final sc = math.min(s.width, s.height) / 360;
  final p = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6 * sc
    ..strokeCap = StrokeCap.round
    ..color = const Color(0xAADCE9FF);
  for (var i = 0; i < 90; i++) {
    final k = 3 + i % 3;
    final y = _frac(_r(i, 1) + t * k) * (s.height + 40) - 20;
    final x = s.width * _r(i, 2);
    final len = s.height * 0.05 * (0.6 + 0.8 * _r(i, 3));
    c.drawLine(Offset(x, y), Offset(x - len * 0.12, y - len), p);
  }
}

void _hearts(Canvas c, Size s, double t) {
  final minD = math.min(s.width, s.height);
  const colors = [Color(0xFFFF4D8D), Color(0xFFFF7AB2), Color(0xFFFF2D55), Color(0xFFFFB3D1)];
  for (var i = 0; i < 14; i++) {
    final u = _frac(_r(i, 1) + t);
    final y = s.height * (1.1 - 1.25 * u);
    final x = s.width * _r(i, 2) + math.sin(_tau * (t * 2 + _r(i, 3))) * s.width * 0.03;
    final size = minD * (0.04 + 0.05 * _r(i, 4));
    final a = (math.min(1.0, u * 6) * math.min(1.0, (1 - u) * 3)).clamp(0.0, 1.0);
    c.drawPath(
      heartPathIn(Rect.fromCenter(center: Offset(x, y), width: size, height: size)),
      Paint()..color = colors[i % colors.length].withOpacity(0.9 * a),
    );
  }
}

void _confetti(Canvas c, Size s, double t) {
  final sc = math.min(s.width, s.height) / 360;
  const colors = [
    Color(0xFFFF3B30), Color(0xFFFFCC00), Color(0xFF34C759),
    Color(0xFF00C7FF), Color(0xFF5856FF), Color(0xFFFF2D95),
  ];
  for (var i = 0; i < 40; i++) {
    final k = 1 + i % 2;
    final y = _frac(_r(i, 1) + t * k) * (s.height + 30) - 15;
    final x = s.width * _r(i, 2) + math.sin(_tau * (t * k + _r(i, 3))) * s.width * 0.03;
    final w = (4 + 5 * _r(i, 4)) * sc;
    c.save();
    c.translate(x, y);
    c.rotate(_tau * (t * (1 + i % 3) + _r(i, 5)));
    c.drawRect(Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.5),
        Paint()..color = colors[i % colors.length]);
    c.restore();
  }
}

/// Draws [fx] over the whole picture. [t] is the loop position, 0..1.
void paintFx(Canvas c, Size s, FxEffect fx, double t) {
  switch (fx) {
    case FxEffect.none:
      break;
    case FxEffect.fire:
      _fireScreen(c, s, t);
    case FxEffect.thunder:
      _thunderScreen(c, s, t);
    case FxEffect.sparkle:
      _sparkleScreen(c, s, t);
    case FxEffect.snow:
      _snow(c, s, t);
    case FxEffect.rain:
      _rain(c, s, t);
    case FxEffect.hearts:
      _hearts(c, s, t);
    case FxEffect.confetti:
      _confetti(c, s, t);
  }
}
