import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'effects.dart';
export 'effects.dart' show TransFx, TransFxPainter, fireFrontY;

enum FrameShape { none, circle, round, heart, star, hexagon }

/// Border animation. One loop lasts [kFrameLoopSeconds].
enum FrameAnim { none, spin, rainbow, pulse, fire, thunder, sparkle }

const kFrameAnimLabels = ['Still', 'Spin', 'Rainbow', 'Pulse', 'Fire', 'Thunder', 'Sparkle'];
const double kFrameLoopSeconds = 2.0;

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
    this.anim = FrameAnim.none,
  });

  final FrameShape shape;
  final double pad; // free space around the shape, as a fraction of the size
  final int border; // index into kFrameBorders
  final int bg; // index into kFrameBgs
  final ui.Image? art; // picture drawn around the shape instead of a plain colour
  final FrameAnim anim;

  bool get active => shape != FrameShape.none;

  /// bg < 0 and no picture: nothing is drawn around the shape (transparent GIF).
  bool get transparent => art == null && bg < 0;

  /// Whether a border is drawn (an animated border always has one).
  bool get hasBorder => kFrameBorders[border.clamp(0, kFrameBorders.length - 1)].color != null || anim != FrameAnim.none;

  bool get animated => active && hasBorder && anim != FrameAnim.none;

  /// Something is drawn over the video.
  bool get needsOverlay => active;

  /// The same look without any movement.
  FrameStyle still() =>
      FrameStyle(shape: shape, pad: pad, border: border, bg: bg, art: art);
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
      return heartPathIn(box);
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
  /// [clock] drives the live preview animation; [phase] (0..1) is used for exported frames.
  const FramePainter(this.style, {this.clock, this.phase = 0}) : super(repaint: clock);

  final FrameStyle style;
  final Animation<double>? clock;
  final double phase;

  double get _t => clock?.value ?? phase;

  /// White inside the shape, black outside: the alpha mask for a transparent GIF.
  static void paintMask(Canvas canvas, Size size, FrameStyle style) {
    final full = Offset.zero & size;
    canvas.drawRect(full, Paint()..color = const Color(0xFF000000));
    canvas.drawPath(framePath(style.shape, size, style.pad),
        Paint()..color = const Color(0xFFFFFFFF)..isAntiAlias = true);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (style.active) _paintFrame(canvas, size);
  }

  void _paintFrame(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final shape = framePath(style.shape, size, style.pad);

    if (!style.transparent) {
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
    }

    if (!style.hasBorder) return;
    final b = kFrameBorders[style.border.clamp(0, kFrameBorders.length - 1)];
    final color = b.color ?? Colors.white;
    final baseW = math.min(size.width, size.height) * 0.03;
    final ang = 2 * math.pi * _t;
    var width = baseW;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    List<Color> tones() => b.gold
        ? const [Color(0xFFF9E27D), Color(0xFFB8860B), Color(0xFFF9E27D), Color(0xFF8A6508)]
        : [color, color, color];

    switch (style.anim) {
      case FrameAnim.none:
        if (b.gold) {
          paint.shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF9E27D), Color(0xFFB8860B), Color(0xFFF9E27D), Color(0xFF8A6508)],
          ).createShader(full);
        } else {
          paint.color = color;
        }
      case FrameAnim.spin:
        final base = b.gold ? const Color(0xFFD4AF37) : color;
        paint.shader = SweepGradient(
          transform: GradientRotation(ang),
          colors: [base, Colors.white, base, base.withOpacity(0.25), base],
          stops: const [0.0, 0.12, 0.3, 0.7, 1.0],
        ).createShader(full);
      case FrameAnim.rainbow:
        paint.shader = SweepGradient(
          transform: GradientRotation(ang),
          colors: const [
            Color(0xFFFF3B30),
            Color(0xFFFF9500),
            Color(0xFFFFE600),
            Color(0xFF34C759),
            Color(0xFF00C7FF),
            Color(0xFF5856FF),
            Color(0xFFFF2D95),
            Color(0xFFFF3B30),
          ],
        ).createShader(full);
      case FrameAnim.fire:
        paintFireEdge(canvas, shape, size, _t);
        width = baseW * 0.7;
        paint.color = const Color(0xFFFF6A00);
      case FrameAnim.thunder:
        paintThunderEdge(canvas, shape, size, _t);
        return;
      case FrameAnim.sparkle:
        width = baseW * 0.5;
        paint.color = const Color(0xFFFFD86B);
      case FrameAnim.pulse:
        final k = 0.5 + 0.5 * math.sin(ang);
        width = baseW * (0.6 + 0.9 * k);
        final glow = Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = width * 2.2
          ..color = (b.gold ? const Color(0xFFD4AF37) : color).withOpacity(0.25 + 0.4 * k)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, baseW * 1.2);
        canvas.drawPath(shape, glow);
        if (b.gold) {
          paint.shader = LinearGradient(colors: tones()).createShader(full);
        } else {
          paint.color = color;
        }
    }
    paint.strokeWidth = width;
    canvas.drawPath(shape, paint);
    if (style.anim == FrameAnim.sparkle) paintSparkleEdge(canvas, shape, size, _t);
  }

  @override
  bool shouldRepaint(FramePainter old) =>
      old.style.shape != style.shape ||
      old.style.pad != style.pad ||
      old.style.border != style.border ||
      old.style.bg != style.bg ||
      old.style.art != style.art ||
      old.style.anim != style.anim ||
      old.phase != phase;
}

/// Clips a child to the frame shape (used when the area around the shape is transparent).
class FrameClipper extends CustomClipper<Path> {
  const FrameClipper(this.shape, this.pad);

  final FrameShape shape;
  final double pad;

  @override
  Path getClip(Size size) => framePath(shape, size, pad);

  @override
  bool shouldReclip(FrameClipper old) => old.shape != shape || old.pad != pad;
}
