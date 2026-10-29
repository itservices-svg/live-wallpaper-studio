import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum FrameShape { none, circle, round, heart, star, hexagon }

const kFrameShapeLabels = ['None', 'Circle', 'Round', 'Heart', 'Star', 'Hexagon'];

class FrameBorder {
  const FrameBorder(this.label, this.color, {this.gold = false});
  final String label;
  final Color? color; // null = no border
  final bool gold;
}

const kFrameBorders = <FrameBorder>[
  FrameBorder('None', null),
  FrameBorder('White', Color(0xFFFFFFFF)),
  FrameBorder('Black', Color(0xFF111111)),
  FrameBorder('Gold', Color(0xFFD4AF37), gold: true),
  FrameBorder('Pink', Color(0xFFFF4FA3)),
  FrameBorder('Cyan', Color(0xFF22D3EE)),
  FrameBorder('Lime', Color(0xFF84CC16)),
  FrameBorder('Red', Color(0xFFEF4444)),
];

const kFrameBgs = <Color>[
  Color(0xFF000000),
  Color(0xFFFFFFFF),
  Color(0xFF1B1830),
  Color(0xFF5236D9),
  Color(0xFFC4267F),
  Color(0xFFD4AF37),
  Color(0xFF0F766E),
];

/// How the framed GIF looks: a shape the video shows through, a border, and what is around it.
class FrameStyle {
  const FrameStyle({
    this.shape = FrameShape.none,
    this.pad = 0.12,
    this.border = 0,
    this.bg = 0,
    this.art,
  });

  final FrameShape shape;
  final double pad; // free space around the shape, as a fraction of the size
  final int border; // index into kFrameBorders
  final int bg; // index into kFrameBgs
  final ui.Image? art; // picture drawn around the shape instead of a plain colour

  bool get active => shape != FrameShape.none;
}

Path framePath(FrameShape s, Size size, double pad) {
  final w = size.width, h = size.height;
  final side = math.min(w, h) * (1 - 2 * pad);
  final c = Offset(w / 2, h / 2);
  final box = Rect.fromCenter(center: c, width: side, height: side);
  switch (s) {
    case FrameShape.none:
      return Path()..addRect(Offset.zero & size);
    case FrameShape.circle:
      return Path()..addOval(box);
    case FrameShape.round:
      final r = Rect.fromCenter(center: c, width: w * (1 - 2 * pad), height: h * (1 - 2 * pad));
      return Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(side * 0.18)));
    case FrameShape.heart:
      final x = box.left, y = box.top, k = box.width;
      Offset pt(double a, double b) => Offset(x + k * a, y + k * b);
      return Path()
        ..moveTo(pt(0.5, 0.92).dx, pt(0.5, 0.92).dy)
        ..cubicTo(pt(0.0, 0.58).dx, pt(0.0, 0.58).dy, pt(0.02, 0.12).dx, pt(0.02, 0.12).dy,
            pt(0.28, 0.12).dx, pt(0.28, 0.12).dy)
        ..cubicTo(pt(0.42, 0.12).dx, pt(0.42, 0.12).dy, pt(0.5, 0.22).dx, pt(0.5, 0.22).dy,
            pt(0.5, 0.30).dx, pt(0.5, 0.30).dy)
        ..cubicTo(pt(0.5, 0.22).dx, pt(0.5, 0.22).dy, pt(0.58, 0.12).dx, pt(0.58, 0.12).dy,
            pt(0.72, 0.12).dx, pt(0.72, 0.12).dy)
        ..cubicTo(pt(0.98, 0.12).dx, pt(0.98, 0.12).dy, pt(1.0, 0.58).dx, pt(1.0, 0.58).dy,
            pt(0.5, 0.92).dx, pt(0.5, 0.92).dy)
        ..close();
    case FrameShape.star:
      final p = Path();
      final outer = side / 2, inner = side * 0.21;
      for (var i = 0; i < 10; i++) {
        final r = i.isEven ? outer : inner;
        final a = -math.pi / 2 + i * math.pi / 5;
        final o = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
        if (i == 0) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      return p..close();
    case FrameShape.hexagon:
      final p = Path();
      final r = side / 2;
      for (var i = 0; i < 6; i++) {
        final a = -math.pi / 2 + i * math.pi / 3;
        final o = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
        if (i == 0) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      return p..close();
  }
}

/// Paints everything around the shape (colour or picture) plus the border. The inside is left
/// empty, so the video behind it shows through. Used for the live preview and for the export.
class FramePainter extends CustomPainter {
  const FramePainter(this.style);

  final FrameStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    if (!style.active) return;
    final full = Offset.zero & size;
    final shape = framePath(style.shape, size, style.pad);
    final outside = Path.combine(PathOperation.difference, Path()..addRect(full), shape);

    canvas.save();
    canvas.clipPath(outside);
    final art = style.art;
    if (art != null) {
      final iw = art.width.toDouble(), ih = art.height.toDouble();
      final scale = math.max(size.width / iw, size.height / ih);
      final sw = size.width / scale, sh = size.height / scale;
      canvas.drawImageRect(
        art,
        Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh),
        full,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      canvas.drawRect(full, Paint()..color = kFrameBgs[style.bg.clamp(0, kFrameBgs.length - 1)]);
    }
    canvas.restore();

    final b = kFrameBorders[style.border.clamp(0, kFrameBorders.length - 1)];
    if (b.color != null) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.min(size.width, size.height) * 0.03
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      if (b.gold) {
        paint.shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF9E27D), Color(0xFFB8860B), Color(0xFFF9E27D), Color(0xFF8A6508)],
        ).createShader(full);
      } else {
        paint.color = b.color!;
      }
      canvas.drawPath(shape, paint);
    }
  }

  @override
  bool shouldRepaint(FramePainter old) =>
      old.style.shape != style.shape ||
      old.style.pad != style.pad ||
      old.style.border != style.border ||
      old.style.bg != style.bg ||
      old.style.art != style.art;
}
