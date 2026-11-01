import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// One picture in a depth wallpaper. [d] = how far it moves when the phone tilts (0 far, 1 near).
/// [cover] = fills the screen; otherwise it is placed at ([x], [y]) with width [w] (screen widths).
/// [f] = slow floating motion of its own.
class DepthLayer {
  DepthLayer({
    required this.path,
    required this.name,
    this.d = 0.3,
    this.cover = true,
    this.w = 1.0,
    this.x = 0.5,
    this.y = 0.5,
    this.f = 0.0,
    this.k = 0.0,
  });

  String path;
  String name;
  double d;
  bool cover;
  double w;
  double x;
  double y;
  double f;
  double k; // >0: fixed zoom for a full-screen layer (photo layers share it so they stay aligned)

  Map<String, dynamic> toJson() =>
      {'p': path, 'n': name, 'd': d, 'c': cover, 'w': w, 'x': x, 'y': y, 'f': f, 'k': k};

  static DepthLayer fromJson(Map<String, dynamic> j) => DepthLayer(
        path: j['p'] as String,
        name: (j['n'] as String?) ?? 'Layer',
        d: (j['d'] as num?)?.toDouble() ?? 0.3,
        cover: (j['c'] as bool?) ?? true,
        w: (j['w'] as num?)?.toDouble() ?? 1.0,
        x: (j['x'] as num?)?.toDouble() ?? 0.5,
        y: (j['y'] as num?)?.toDouble() ?? 0.5,
        f: (j['f'] as num?)?.toDouble() ?? 0.0,
        k: (j['k'] as num?)?.toDouble() ?? 0.0,
      );
}

class DepthProject {
  DepthProject({List<DepthLayer>? layers, this.invert = false, this.sens = 1.0}) : layers = layers ?? [];

  final List<DepthLayer> layers; // back to front
  bool invert;
  double sens;

  Map<String, dynamic> toJson() =>
      {'inv': invert, 'sens': sens, 'layers': [for (final l in layers) l.toJson()]};
}

/// Saves the depth wallpaper and hands it to the native live wallpaper service (Android).
class DepthService {
  static const _ch = MethodChannel('lws/depth');

  static Future<Directory> dir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/depth').create(recursive: true);
  }

  static Future<DepthProject> load() async {
    try {
      final f = File('${(await dir()).path}/project.json');
      if (!await f.exists()) return DepthProject();
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final layers = <DepthLayer>[];
      for (final e in (j['layers'] as List)) {
        final l = DepthLayer.fromJson(e as Map<String, dynamic>);
        if (await File(l.path).exists()) layers.add(l);
      }
      return DepthProject(
        layers: layers,
        invert: (j['inv'] as bool?) ?? false,
        sens: (j['sens'] as num?)?.toDouble() ?? 1.0,
      );
    } catch (_) {
      return DepthProject();
    }
  }

  static Future<void> save(DepthProject p) async {
    final f = File('${(await dir()).path}/project.json');
    await f.writeAsString(jsonEncode(p.toJson()));
  }

  /// Copies a picture into the depth folder and returns the stored path.
  static Future<String> addFile(String src) async {
    final d = await dir();
    final ext = src.contains('.') ? src.split('.').last.toLowerCase() : 'jpg';
    final dest = '${d.path}/layer_${DateTime.now().microsecondsSinceEpoch}.${ext.length > 4 ? 'jpg' : ext}';
    await File(src).copy(dest);
    return dest;
  }

  /// Writes the wallpaper for the native service and opens Android's live wallpaper screen.
  static Future<String?> apply(DepthProject p) async {
    if (defaultTargetPlatform != TargetPlatform.android) return 'Depth wallpapers work on Android only.';
    if (p.layers.isEmpty) return 'Add at least one picture first.';
    try {
      await save(p);
      await _ch.invokeMethod('setConfig', jsonEncode(p.toJson()));
      await _ch.invokeMethod('openPicker');
      return null;
    } on PlatformException catch (e) {
      return 'Could not open the wallpaper screen: ${e.message}';
    } catch (e) {
      return 'Could not set it: $e';
    }
  }

  static Future<bool> isActive() async {
    try {
      return (await _ch.invokeMethod<bool>('isActive')) ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Built-in pictures drawn in code, so scenes work without any download.
class DepthArt {
  static Future<String> _png(String name, int w, int h, void Function(Canvas, Size) fn) async {
    final d = await DepthService.dir();
    final path = '${d.path}/$name.png';
    if (await File(path).exists()) return path;
    final rec = ui.PictureRecorder();
    fn(Canvas(rec), Size(w.toDouble(), h.toDouble()));
    final img = await rec.endRecording().toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    await File(path).writeAsBytes(data!.buffer.asUint8List(), flush: true);
    return path;
  }

  static Color _c(int r, int g, int b, double a) => Color.fromRGBO(r, g, b, a);

  static ui.Gradient _radial(Offset c, double r, List<Color> colors, List<double> stops,
      {Offset? focal, double fr = 0}) {
    return ui.Gradient.radial(c, r, colors, stops, TileMode.clamp, null, focal, fr);
  }

  static void _blob(Canvas c, double cx, double cy, double rad, int n, int seed, Color col, {double blur = 0}) {
    final rnd = math.Random(seed);
    final p = Path();
    for (var i = 0; i <= n; i++) {
      final a = i / n * math.pi * 2;
      final k = rad * (0.6 + rnd.nextDouble() * 0.6);
      final x = cx + math.cos(a) * k;
      final y = cy + math.sin(a) * k * 0.8;
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    final paint = Paint()..color = col;
    if (blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    c.drawPath(p, paint);
  }

  /// Deep space with a soft nebula and stars.
  static Future<String> stars() => _png('art_stars', 1080, 2160, (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF04050F));
        final neb = <(double, double, Color)>[
          (0.3, 0.25, _c(90, 60, 200, 0.35)),
          (0.75, 0.6, _c(200, 60, 150, 0.25)),
          (0.4, 0.85, _c(40, 110, 220, 0.3)),
        ];
        for (final n in neb) {
          c.drawRect(
            Offset.zero & s,
            Paint()
              ..shader = _radial(Offset(n.$1 * s.width, n.$2 * s.height), s.width * 0.9,
                  [n.$3, const Color(0x00000000)], [0, 1]),
          );
        }
        final rnd = math.Random(5);
        for (var i = 0; i < 520; i++) {
          final x = rnd.nextDouble() * s.width;
          final y = rnd.nextDouble() * s.height;
          final r = math.pow(rnd.nextDouble(), 3) * 4.4 + 0.8;
          c.drawCircle(Offset(x, y), r.toDouble(), Paint()..color = Colors.white.withValues(alpha: 0.4 + rnd.nextDouble() * 0.6));
          if (r > 3.6) {
            c.drawCircle(
              Offset(x, y),
              r * 5,
              Paint()
                ..shader = _radial(Offset(x, y), r * 5, [_c(200, 220, 255, 0.5), _c(200, 220, 255, 0)], [0, 1]),
            );
          }
        }
      });

  static Future<String> moon() => _png('art_moon', 1000, 1000, (c, s) {
        final S = s.width;
        final r = S * 0.33;
        final ctr = Offset(S / 2, S / 2);
        c.drawCircle(
          ctr,
          r * 1.5,
          Paint()..shader = _radial(ctr, r * 1.5, [_c(200, 210, 255, 0.35), _c(200, 210, 255, 0)], [r / (r * 1.5), 1]),
        );
        c.save();
        c.clipPath(Path()..addOval(Rect.fromCircle(center: ctr, radius: r)));
        final lit = Offset(ctr.dx - r * 0.35, ctr.dy - r * 0.35);
        c.drawRect(
          Offset.zero & s,
          Paint()
            ..shader = _radial(ctr, r * 1.05,
                [const Color(0xFFF4F1E8), const Color(0xFFC9C5BA), const Color(0xFF8D897F)], [0, 0.6, 1],
                focal: lit, fr: r * 0.1),
        );
        final rnd = math.Random(7);
        for (var i = 0; i < 7; i++) {
          _blob(c, ctr.dx + (rnd.nextDouble() - 0.5) * r * 1.2, ctr.dy + (rnd.nextDouble() - 0.5) * r * 1.2,
              r * (0.18 + rnd.nextDouble() * 0.22), 14, i + 3, _c(95, 92, 88, 0.45), blur: r * 0.05);
        }
        for (var i = 0; i < 38; i++) {
          final a = rnd.nextDouble() * 7;
          final dist = math.sqrt(rnd.nextDouble()) * r * 0.92;
          final p = Offset(ctr.dx + math.cos(a) * dist, ctr.dy + math.sin(a) * dist);
          final cr = r * (0.02 + rnd.nextDouble() * rnd.nextDouble() * 0.09);
          c.drawCircle(
            p,
            cr,
            Paint()
              ..shader = _radial(p, cr, [_c(70, 68, 64, 0.55), _c(90, 88, 82, 0.35), _c(255, 255, 255, 0.35)],
                  [0, 0.8, 1],
                  focal: Offset(p.dx + cr * 0.2, p.dy + cr * 0.2), fr: cr * 0.2),
          );
        }
        c.drawRect(
          Offset.zero & s,
          Paint()
            ..shader = _radial(Offset(ctr.dx - r * 0.2, ctr.dy - r * 0.2), r * 1.6,
                [_c(0, 0, 0, 0), _c(5, 8, 20, 0.15), _c(5, 8, 20, 0.8)], [0, 0.55, 1],
                focal: Offset(ctr.dx - r * 0.5, ctr.dy - r * 0.5), fr: r * 0.4),
        );
        c.restore();
      });

  static Future<String> earth() => _png('art_earth', 1000, 1000, (c, s) {
        final S = s.width;
        final r = S * 0.34;
        final ctr = Offset(S / 2, S / 2);
        c.drawCircle(
          ctr,
          r * 1.45,
          Paint()..shader = _radial(ctr, r * 1.45, [_c(90, 170, 255, 0.55), _c(90, 170, 255, 0)], [r / (r * 1.45), 1]),
        );
        c.save();
        c.clipPath(Path()..addOval(Rect.fromCircle(center: ctr, radius: r)));
        c.drawRect(
          Offset.zero & s,
          Paint()
            ..shader = _radial(ctr, r * 1.05,
                [const Color(0xFF2F7FD6), const Color(0xFF0F4A9E), const Color(0xFF08285E)], [0, 0.7, 1],
                focal: Offset(ctr.dx - r * 0.3, ctr.dy - r * 0.3), fr: r * 0.1),
        );
        final lands = <List<double>>[
          [-.3, -.2, .34],
          [.28, .12, .28],
          [-.05, .45, .22],
          [.1, -.5, .18],
          [-.55, .3, .14],
        ];
        for (var i = 0; i < lands.length; i++) {
          final l = lands[i];
          _blob(c, ctr.dx + l[0] * r, ctr.dy + l[1] * r, l[2] * r, 22, 20 + i, const Color(0xFF3F8F46));
          _blob(c, ctr.dx + l[0] * r + r * 0.03, ctr.dy + l[1] * r, l[2] * r * 0.6, 18, 40 + i,
              _c(176, 150, 84, 0.75));
        }
        final rnd = math.Random(11);
        for (var i = 0; i < 9; i++) {
          _blob(c, ctr.dx + (rnd.nextDouble() - 0.5) * r * 1.8, ctr.dy + (rnd.nextDouble() - 0.5) * r * 1.6,
              r * (0.12 + rnd.nextDouble() * 0.2), 16, 60 + i, _c(255, 255, 255, 0.55), blur: r * 0.05);
        }
        _blob(c, ctr.dx, ctr.dy - r * 0.98, r * 0.35, 14, 99, _c(240, 248, 255, 0.9), blur: r * 0.03);
        c.drawRect(
          Offset.zero & s,
          Paint()..shader = _radial(ctr, r, [_c(120, 190, 255, 0), _c(120, 190, 255, 0.55)], [0.7, 1]),
        );
        c.drawRect(
          Offset.zero & s,
          Paint()
            ..shader = _radial(Offset(ctr.dx - r * 0.2, ctr.dy - r * 0.2), r * 1.6,
                [_c(0, 0, 0, 0), _c(0, 5, 20, 0.2), _c(0, 5, 20, 0.85)], [0, 0.55, 1],
                focal: Offset(ctr.dx - r * 0.5, ctr.dy - r * 0.5), fr: r * 0.4),
        );
        c.restore();
      });

  /// A wooden window frame: the panes are see-through, so what is behind shows.
  static Future<String> window() => _png('art_window', 1080, 2160, (c, s) {
        final W = s.width, H = s.height;
        final m = W * 0.07, fw = W * 0.035;
        const cols = 2, rows = 3;
        final x0 = m, y0 = H * 0.1;
        final iw = W - 2 * m, ih = H * 0.8 - 2 * m;
        final pw = (iw - fw * (cols - 1)) / cols, ph = (ih - fw * (rows - 1)) / rows;
        final panes = <RRect>[];
        for (var i = 0; i < cols; i++) {
          for (var j = 0; j < rows; j++) {
            panes.add(RRect.fromRectAndRadius(
                Rect.fromLTWH(x0 + i * (pw + fw), y0 + j * (ph + fw), pw, ph), Radius.circular(W * 0.012)));
          }
        }
        final frame = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & s);
        for (final p in panes) {
          frame.addRRect(p);
        }
        c.drawPath(
          frame,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(W, 0),
                [const Color(0xFF2A1D14), const Color(0xFF4A3424), const Color(0xFF241811)], [0, 0.5, 1]),
        );
        final edge = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _c(255, 220, 170, 0.25);
        for (final p in panes) {
          c.drawRRect(p, edge);
        }
        // glass shine across the panes
        c.save();
        final clip = Path();
        for (final p in panes) {
          clip.addRRect(p);
        }
        c.clipPath(clip);
        final shine = Path()
          ..moveTo(W * 0.0, H * 0.1)
          ..lineTo(W * 0.45, H * 0.1)
          ..lineTo(W * 0.0, H * 0.55)
          ..close();
        c.drawPath(shine, Paint()..color = _c(255, 255, 255, 0.07));
        c.restore();
      });

  /// A glowing circuit board with a chip: a good "far" picture.
  static Future<String> board() => _png('art_board', 1080, 2160, (c, s) {
        final W = s.width, H = s.height;
        final u = W / 540;
        final rnd = math.Random(3);
        double r() => rnd.nextDouble();
        c.drawRect(
          Offset.zero & s,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(0, H),
                [const Color(0xFF0A1240), const Color(0xFF050A2A)]),
        );
        for (var i = 0; i < 90; i++) {
          var x = r() * W, y = r() * H;
          final p = Path()..moveTo(x, y);
          final n = 2 + (r() * 3).floor();
          for (var k = 0; k < n; k++) {
            if (r() < 0.5) {
              x += (r() - 0.5) * W * 0.35;
            } else {
              y += (r() - 0.5) * H * 0.2;
            }
            p.lineTo(x, y);
          }
          c.drawPath(
            p,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = W * (0.002 + r() * 0.004)
              ..color = _c(40 + (r() * 60).floor(), 120 + (r() * 100).floor(), 255, 0.25 + r() * 0.4),
          );
          c.drawCircle(Offset(x, y), W * 0.006, Paint()..color = _c(120, 220, 255, 0.8));
        }
        for (var i = 0; i < 46; i++) {
          final w = W * (0.03 + r() * 0.08), h = H * (0.012 + r() * 0.02);
          final x = r() * W, y = r() * H;
          final rc = Rect.fromLTWH(x, y, w, h);
          c.drawRect(rc, Paint()..color = _c(10 + (r() * 30).floor(), 30 + (r() * 40).floor(), 90 + (r() * 80).floor(), 0.9));
          c.drawRect(
              rc,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2 * u
                ..color = _c(100, 200, 255, 0.6));
          for (var q = 0; q < 6; q++) {
            final pn = Paint()..color = _c(180, 230, 255, 0.7);
            c.drawRect(Rect.fromLTWH(x + q * w / 6, y - 4 * u, w / 12, 4 * u), pn);
            c.drawRect(Rect.fromLTWH(x + q * w / 6, y + h, w / 12, 4 * u), pn);
          }
        }
        final ctr = Offset(W / 2, H / 2);
        final cw = W * 0.5;
        c.drawRect(
          Offset.zero & s,
          Paint()..shader = _radial(ctr, cw, [_c(60, 120, 255, 0.45), _c(60, 120, 255, 0)], [0, 1]),
        );
        final chip = Rect.fromLTWH(ctr.dx - cw / 2, ctr.dy - cw / 2, cw, cw);
        c.drawRect(chip, Paint()..color = const Color(0xFF2A2A46));
        c.drawRect(
            chip,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4 * u
              ..color = const Color(0xFF8AB4FF));
        final pin = Paint()..color = _c(150, 210, 255, 0.8);
        for (var q = 0; q < 28; q++) {
          final t = (q + 0.5) * cw / 28;
          c.drawRect(Rect.fromLTWH(chip.left + t, chip.top - 14 * u, 3 * u, 14 * u), pin);
          c.drawRect(Rect.fromLTWH(chip.left + t, chip.bottom, 3 * u, 14 * u), pin);
          c.drawRect(Rect.fromLTWH(chip.left - 14 * u, chip.top + t, 14 * u, 3 * u), pin);
          c.drawRect(Rect.fromLTWH(chip.right, chip.top + t, 14 * u, 3 * u), pin);
        }
        c.drawCircle(
            ctr,
            cw * 0.25,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = W * 0.012
              ..color = _c(20, 20, 30, 0.8));
      });

  /// Shattered glass with a see-through hole in the middle: a good "near" picture.
  static Future<String> glass() => _png('art_glass', 1080, 2160, (c, s) {
        final W = s.width, H = s.height;
        final u = W / 540;
        final rnd = math.Random(9);
        double r() => rnd.nextDouble();
        final cx = W / 2, cy = H * 0.5;
        const n = 22;
        final hole = Path();
        for (var i = 0; i < n; i++) {
          final a = i / n * math.pi * 2;
          final k = (0.26 + r() * 0.12) * W;
          final k2 = k * (1.05 + 0.25 * math.sin(a * 2));
          final x = cx + math.cos(a) * k, y = cy + math.sin(a) * k2 * 1.25;
          if (i == 0) {
            hole.moveTo(x, y);
          } else {
            hole.lineTo(x, y);
          }
        }
        hole.close();
        c.save();
        final clip = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & s)
          ..addPath(hole, Offset.zero);
        c.clipPath(clip);
        c.drawRect(
          Offset.zero & s,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(W, H),
                [_c(40, 90, 255, 0.55), _c(90, 160, 255, 0.35), _c(30, 70, 230, 0.6)], [0, 0.5, 1]),
        );
        for (var i = 0; i < 36; i++) {
          final a = r() * math.pi * 2, w = 0.1 + r() * 0.2;
          final p = Path()
            ..moveTo(cx, cy)
            ..lineTo(cx + math.cos(a) * W * 1.5, cy + math.sin(a) * W * 1.8)
            ..lineTo(cx + math.cos(a + w) * W * 1.5, cy + math.sin(a + w) * W * 1.8)
            ..close();
          c.drawPath(p, Paint()..color = r() < 0.5 ? _c(255, 255, 255, 0.06) : _c(0, 0, 40, 0.10));
        }
        for (var i = 0; i < 70; i++) {
          final a = r() * math.pi * 2;
          final rr = W * 0.2;
          var x = cx + math.cos(a) * rr, y = cy + math.sin(a) * rr * 1.2;
          final p = Path()..moveTo(x, y);
          final len = W * (0.2 + r() * 0.7);
          var aa = a;
          for (var k = 0; k < 8; k++) {
            aa += (r() - 0.5) * 0.35;
            final st = len / 8;
            x += math.cos(aa) * st;
            y += math.sin(aa) * st * 1.2;
            p.lineTo(x, y);
          }
          c.drawPath(
              p,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..strokeWidth = (1 + r() * 2.5) * u
                ..color = _c(190, 240, 255, 0.35 + r() * 0.5));
        }
        for (final m in [0.36, 0.5, 0.68, 0.9]) {
          final p = Path();
          const steps = 40;
          for (var i = 0; i <= steps; i++) {
            final a = i / steps * math.pi * 2;
            final rr = W * m * (0.94 + r() * 0.12);
            final x = cx + math.cos(a) * rr, y = cy + math.sin(a) * rr * 1.2;
            if (i == 0) {
              p.moveTo(x, y);
            } else {
              p.lineTo(x, y);
            }
          }
          c.drawPath(
              p,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5 * u
                ..color = _c(170, 230, 255, 0.4));
        }
        c.restore();
        c.drawPath(
            hole,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 14 * u
              ..color = _c(79, 208, 255, 0.8)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * u));
        c.drawPath(
            hole,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6 * u
              ..strokeJoin = StrokeJoin.round
              ..color = _c(200, 245, 255, 0.95));
      });

  // ---- overlay library: full-screen pictures drawn in code (designed on a 540 x 1080 canvas)

  static Future<String> _ov(String id, void Function(Canvas) fn) =>
      _png('ov_$id', 1080, 2160, (c, s) {
        c.scale(s.width / 540);
        fn(c);
      });

  static const double _w = 540, _h = 1080;

  static Paint _stroke(Color col, double w, {double blur = 0, StrokeCap cap = StrokeCap.round}) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = cap
      ..strokeJoin = StrokeJoin.round
      ..color = col;
    if (blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    return p;
  }

  /// A glass screen cracked from one corner.
  static Future<String> crackedScreen() => _ov('crack', (c) {
        final rnd = math.Random(21);
        double r() => rnd.nextDouble();
        final cx = _w * 0.78, cy = _h * 0.22;
        final rays = List<double>.generate(26, (_) => r() * math.pi * 2)..sort();
        for (final a in rays) {
          var x = cx, y = cy, aa = a;
          final len = _w * (0.5 + r() * 1.6);
          final p = Path()..moveTo(x, y);
          for (var k = 0; k < 14; k++) {
            aa += (r() - 0.5) * 0.12;
            x += math.cos(aa) * len / 14;
            y += math.sin(aa) * len / 14;
            p.lineTo(x, y);
          }
          final w = 1.3 + r() * 1.2;
          c.drawPath(p, _stroke(_c(150, 220, 255, 0.9), w + 2, blur: 3));
          c.drawPath(p, _stroke(_c(255, 255, 255, 0.75), w));
          c.save();
          c.translate(1, 1);
          c.drawPath(p, _stroke(_c(0, 0, 0, 0.25), 0.6));
          c.restore();
        }
        for (var ring = 1; ring <= 7; ring++) {
          final rad = ring * ring * 9 + 22.0;
          final p = Path();
          for (var i = 0; i < rays.length; i++) {
            final a = rays[i] + (r() - 0.5) * 0.03;
            final rr = rad * (0.85 + r() * 0.3);
            final x = cx + math.cos(a) * rr, y = cy + math.sin(a) * rr;
            if (i == 0) {
              p.moveTo(x, y);
            } else {
              p.lineTo(x, y);
            }
          }
          p.close();
          c.drawPath(p, _stroke(_c(255, 255, 255, 0.55 - ring * 0.05), 1.1));
        }
        c.drawCircle(Offset(cx, cy), 40,
            Paint()..shader = _radial(Offset(cx, cy), 40, [_c(255, 255, 255, 0.9), _c(255, 255, 255, 0)], [0, 1]));
        for (var i = 0; i < rays.length - 1; i++) {
          final a = rays[i], b = rays[i + 1];
          final p = Path()
            ..moveTo(cx, cy)
            ..lineTo(cx + math.cos(a) * _w * 2, cy + math.sin(a) * _w * 2)
            ..lineTo(cx + math.cos(b) * _w * 2, cy + math.sin(b) * _w * 2)
            ..close();
          c.drawPath(p, Paint()..color = r() < 0.5 ? _c(255, 255, 255, 0.05) : _c(120, 180, 255, 0.05));
        }
      });

  /// A metal ship window (porthole) with rivets.
  static Future<String> porthole() => _ov('porthole', (c) {
        const cx = _w / 2, cy = _h / 2;
        const r = _w * 0.36;
        c.save();
        c.clipPath(Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(const Rect.fromLTWH(0, 0, _w, _h))
          ..addOval(Rect.fromCircle(center: const Offset(cx, cy), radius: r)));
        c.drawRect(
          const Rect.fromLTWH(0, 0, _w, _h),
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, const Offset(_w, _h),
                [const Color(0xFF59606B), const Color(0xFF2E333B), const Color(0xFF4A515C)], [0, 0.5, 1]),
        );
        final rnd = math.Random(4);
        for (var i = 0; i < 900; i++) {
          c.drawRect(Rect.fromLTWH(rnd.nextDouble() * _w, rnd.nextDouble() * _h, 1 + rnd.nextDouble() * 2, 1),
              Paint()..color = _c(255, 255, 255, rnd.nextDouble() * 0.05));
        }
        c.restore();
        for (final (rad, w, col) in [
          (r + 6, 12.0, const Color(0xFF1D2026)),
          (r + 22, 8.0, const Color(0xFF8A919D)),
          (r + 40, 10.0, const Color(0xFF3A3F48)),
        ]) {
          c.drawCircle(const Offset(cx, cy), rad, _stroke(col, w));
        }
        c.drawCircle(
          const Offset(cx, cy),
          r + 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..shader = ui.Gradient.linear(const Offset(cx - r, cy - r), const Offset(cx + r, cy + r),
                [_c(255, 255, 255, 0.65), _c(255, 255, 255, 0), _c(0, 0, 0, 0.6)], [0, 0.5, 1]),
        );
        for (var i = 0; i < 16; i++) {
          final a = i / 16 * math.pi * 2;
          final p = Offset(cx + math.cos(a) * (r + 80), cy + math.sin(a) * (r + 80));
          c.drawCircle(
            p,
            9,
            Paint()
              ..shader = _radial(p, 9, [const Color(0xFFD9DDE4), const Color(0xFF444A54)], [0, 1],
                  focal: Offset(p.dx - 2, p.dy - 2), fr: 1),
          );
          c.drawCircle(p, 9, _stroke(_c(0, 0, 0, 0.5), 1));
        }
      });

  static void _leaf(Canvas c, double x, double y, double a, double sc, List<Color> col) {
    c.save();
    c.translate(x, y);
    c.rotate(a);
    c.scale(sc);
    final p = Path()
      ..moveTo(0, 0)
      ..cubicTo(14, -14, 40, -12, 60, 0)
      ..cubicTo(40, 12, 14, 14, 0, 0);
    c.drawPath(p, Paint()..shader = ui.Gradient.linear(const Offset(0, -14), const Offset(0, 14), col));
    c.drawPath(p, _stroke(_c(10, 50, 10, 0.55), 1));
    c.drawLine(const Offset(2, 0), const Offset(56, 0), _stroke(_c(200, 255, 180, 0.55), 1));
    final veins = Path();
    for (var i = 1; i < 5; i++) {
      veins
        ..moveTo(i * 11.0, 0)
        ..lineTo(i * 11.0 + 10, -8)
        ..moveTo(i * 11.0, 0)
        ..lineTo(i * 11.0 + 10, 8);
    }
    c.drawPath(veins, _stroke(_c(200, 255, 180, 0.3), 1));
    c.restore();
  }

  /// Leafy vines growing in from the edges, with a few small flowers.
  static Future<String> vines() => _ov('vines', (c) {
        final rnd = math.Random(8);
        double r() => rnd.nextDouble();
        const cols = [
          [Color(0xFF3F9B3A), Color(0xFF1D6A2A)],
          [Color(0xFF58B848), Color(0xFF2A7A30)],
          [Color(0xFF2F8A45), Color(0xFF14502A)],
        ];
        List<List<double>> vine(double x, double y, double a0, double len, int depth) {
          var px = x, py = y, a = a0;
          final path = Path()..moveTo(x, y);
          final pts = <List<double>>[];
          for (var i = 0; i < 30; i++) {
            a += (r() - 0.5) * 0.35;
            px += math.cos(a) * len / 30;
            py += math.sin(a) * len / 30;
            path.lineTo(px, py);
            pts.add([px, py, a]);
          }
          c.drawPath(path, _stroke(const Color(0xFF2C5A26), 5.0 - depth));
          for (var i = 0; i < pts.length; i += 2) {
            final side = i % 4 == 0 ? 1 : -1;
            _leaf(c, pts[i][0], pts[i][1], pts[i][2] + side * (0.7 + r() * 0.5),
                (0.55 + r() * 0.5) * (1 - depth * 0.1), cols[(r() * 3).floor()]);
          }
          return pts;
        }

        final starts = <List<double>>[
          [0, _h * 0.1, 0.5],
          [0, _h * 0.45, 0.3],
          [0, _h * 0.8, -0.3],
          [_w, _h * 0.2, math.pi - 0.5],
          [_w, _h * 0.62, math.pi + 0.3],
          [_w * 0.3, 0, 1.4],
          [_w * 0.8, 0, 1.7],
          [_w * 0.2, _h, -1.4],
          [_w * 0.7, _h, -1.7],
        ];
        for (final s in starts) {
          final pts = vine(s[0], s[1], s[2], _w * (0.7 + r() * 0.5), 0);
          if (r() < 0.7) vine(pts[12][0], pts[12][1], pts[12][2] + 0.9, _w * 0.35, 2);
        }
        for (var i = 0; i < 9; i++) {
          final x = r() < 0.5 ? r() * _w * 0.25 : _w - r() * _w * 0.25;
          final y = r() * _h;
          if (r() < 0.4) continue;
          for (var k = 0; k < 6; k++) {
            c.save();
            c.translate(x, y);
            c.rotate(k / 6 * 6.28);
            final pet = Rect.fromCenter(center: const Offset(9, 0), width: 18, height: 10);
            c.drawOval(pet, Paint()..color = const Color(0xFFFFD7E6));
            c.drawOval(pet, _stroke(const Color(0xFFE58AA8), 0.8));
            c.restore();
          }
          c.drawCircle(Offset(x, y), 4, Paint()..color = const Color(0xFFF4C542));
        }
      });

  /// Paper with a torn hole.
  static Future<String> tornPaper() => _ov('torn', (c) {
        final rnd = math.Random(31);
        double r() => rnd.nextDouble();
        const cx = _w / 2, cy = _h * 0.5;
        final hole = Path();
        const n = 90;
        for (var i = 0; i < n; i++) {
          final a = i / n * 6.283;
          final rad = _w *
              (0.3 + 0.05 * math.sin(a * 3) + 0.04 * math.sin(a * 7 + 1)) *
              (1 + (r() - 0.5) * 0.14);
          final x = cx + math.cos(a) * rad, y = cy + math.sin(a) * rad * 1.35;
          if (i == 0) {
            hole.moveTo(x, y);
          } else {
            hole.lineTo(x, y);
          }
        }
        hole.close();
        final outside = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(const Rect.fromLTWH(0, 0, _w, _h))
          ..addPath(hole, Offset.zero);
        c.save();
        c.clipPath(outside);
        c.drawRect(
          const Rect.fromLTWH(0, 0, _w, _h),
          Paint()
            ..shader = ui.Gradient.linear(
                Offset.zero, const Offset(_w, _h), [const Color(0xFFEFE3C8), const Color(0xFFD8C7A2)]),
        );
        for (var i = 0; i < 5000; i++) {
          final dark = r() < 0.5;
          c.drawRect(Rect.fromLTWH(r() * _w, r() * _h, 1 + r() * 3, 1 + r() * 3),
              Paint()..color = dark ? _c(120, 90, 50, r() * 0.07) : _c(255, 255, 255, r() * 0.07));
        }
        c.drawPath(hole, _stroke(_c(0, 0, 0, 0.6), 14, blur: 10));
        c.restore();
        c.drawPath(hole, _stroke(_c(255, 250, 235, 0.95), 7));
      });

  /// Frost and ice crystals creeping in from the edges.
  static Future<String> frost() => _ov('frost', (c) {
        final rnd = math.Random(51);
        double r() => rnd.nextDouble();
        const m = _w * 0.22;
        final white = _c(235, 248, 255, 0.88);
        final none = _c(235, 248, 255, 0);
        void band(Offset a, Offset b, Rect rc) {
          c.drawRect(rc, Paint()..shader = ui.Gradient.linear(a, b, [white, none]));
        }

        band(Offset.zero, const Offset(m, 0), const Rect.fromLTWH(0, 0, m, _h));
        band(const Offset(_w, 0), const Offset(_w - m, 0), const Rect.fromLTWH(_w - m, 0, m, _h));
        band(Offset.zero, const Offset(0, m), const Rect.fromLTWH(0, 0, _w, m));
        band(const Offset(0, _h), const Offset(0, _h - m), const Rect.fromLTWH(0, _h - m, _w, m));
        void crystal(double x, double y, double a, double len, int d) {
          if (d > 3 || len < 5) return;
          final x2 = x + math.cos(a) * len, y2 = y + math.sin(a) * len;
          c.drawLine(Offset(x, y), Offset(x2, y2),
              _stroke(_c(255, 255, 255, 0.85 - d * 0.15), math.max(0.6, 2.2 - d * 0.6)));
          for (final sd in [-1, 1]) {
            crystal(x + (x2 - x) * 0.45, y + (y2 - y) * 0.45, a + sd * 1.05, len * 0.5, d + 1);
            crystal(x + (x2 - x) * 0.8, y + (y2 - y) * 0.8, a + sd * 0.9, len * 0.38, d + 1);
          }
          crystal(x2, y2, a + (r() - 0.5) * 0.3, len * 0.4, d + 1);
        }

        for (var i = 0; i < 46; i++) {
          final side = (r() * 4).floor();
          double x, y, a;
          if (side == 0) {
            x = 0;
            y = r() * _h;
            a = (r() - 0.5) * 1.2;
          } else if (side == 1) {
            x = _w;
            y = r() * _h;
            a = math.pi + (r() - 0.5) * 1.2;
          } else if (side == 2) {
            x = r() * _w;
            y = 0;
            a = math.pi / 2 + (r() - 0.5) * 1.2;
          } else {
            x = r() * _w;
            y = _h;
            a = -math.pi / 2 + (r() - 0.5) * 1.2;
          }
          crystal(x, y, a, _w * (0.1 + r() * 0.14), 0);
        }
        for (var i = 0; i < 500; i++) {
          final x = r() * _w, y = r() * _h;
          final dEdge = [x, _w - x, y * 0.5, (_h - y) * 0.5].reduce(math.min);
          if (r() * m * 1.4 < dEdge) continue;
          c.drawCircle(Offset(x, y), 0.6 + r() * 1.8, Paint()..color = _c(255, 255, 255, 0.3 + r() * 0.5));
        }
      });

  /// Soft beams of light from the top-left corner.
  static Future<String> lightRays() => _ov('rays', (c) {
        final rnd = math.Random(61);
        double r() => rnd.nextDouble();
        const ox = _w * 0.15, oy = -_h * 0.05;
        for (var i = 0; i < 14; i++) {
          final a = 0.55 + r() * 0.9, w = 0.015 + r() * 0.05;
          final p = Path()
            ..moveTo(ox, oy)
            ..lineTo(ox + math.cos(a - w) * _h * 1.6, oy + math.sin(a - w) * _h * 1.6)
            ..lineTo(ox + math.cos(a + w) * _h * 1.6, oy + math.sin(a + w) * _h * 1.6)
            ..close();
          c.drawPath(
            p,
            Paint()
              ..blendMode = BlendMode.plus
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
              ..shader = ui.Gradient.linear(const Offset(ox, oy),
                  Offset(ox + math.cos(a) * _h, oy + math.sin(a) * _h),
                  [_c(255, 240, 200, 0.28 + r() * 0.2), _c(255, 240, 200, 0)]),
          );
        }
        c.drawRect(
          const Rect.fromLTWH(0, 0, _w, _h),
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = _radial(const Offset(ox, oy), _w * 0.6, [_c(255, 245, 215, 0.8), _c(255, 245, 215, 0)], [0, 1]),
        );
        for (var i = 0; i < 60; i++) {
          c.drawCircle(Offset(r() * _w, r() * _h * 0.8), 0.8 + r() * 2,
              Paint()..color = _c(255, 250, 230, r() * 0.6));
        }
      });

  /// Drifting fog along the bottom and the sides.
  static Future<String> smoke() => _ov('smoke', (c) {
        final rnd = math.Random(71);
        double r() => rnd.nextDouble();
        void puff(double x, double y, double rad, double a) {
          c.drawCircle(Offset(x, y), rad,
              Paint()..shader = _radial(Offset(x, y), rad, [_c(235, 238, 245, a), _c(235, 238, 245, 0)], [0, 1]));
        }

        for (var i = 0; i < 46; i++) {
          puff(r() * _w, _h * (0.55 + r() * 0.5), _w * (0.12 + r() * 0.22) * 1.6, 0.22 + r() * 0.2);
        }
        for (var i = 0; i < 20; i++) {
          puff(r() < 0.5 ? -_w * 0.05 : _w * 1.05, r() * _h, _w * (0.2 + r() * 0.2) * 1.5, 0.25);
        }
      });

  /// Soap bubbles with shiny highlights.
  static Future<String> bubbles() => _ov('bubbles', (c) {
        final rnd = math.Random(81);
        double r() => rnd.nextDouble();
        for (var i = 0; i < 46; i++) {
          final rad = 6 + r() * r() * 60;
          final p = Offset(r() * _w, r() * _h);
          c.drawCircle(
            p,
            rad,
            Paint()
              ..shader = _radial(p, rad, [_c(180, 230, 255, 0.02), _c(150, 215, 255, 0.16), _c(220, 245, 255, 0.65)],
                  [0.55, 0.85, 1]),
          );
          c.drawCircle(p, rad, _stroke(_c(255, 255, 255, 0.55), 1));
          final hp = Offset(p.dx - rad * 0.4, p.dy - rad * 0.45);
          c.save();
          c.translate(hp.dx, hp.dy);
          c.rotate(-0.6);
          c.drawOval(
            Rect.fromCenter(center: Offset.zero, width: rad * 0.6, height: rad * 0.36),
            Paint()..color = _c(255, 255, 255, 0.9),
          );
          c.restore();
          final lp = Offset(p.dx + rad * 0.4, p.dy + rad * 0.5);
          c.drawCircle(lp, rad * 0.3,
              Paint()..shader = _radial(lp, rad * 0.3, [_c(255, 200, 240, 0.35), _c(255, 200, 240, 0)], [0, 1]));
        }
      });

  /// Every full-screen picture of the library: back pictures first, then front overlays.
  static final List<ArtDef> catalog = [
    ArtDef('stars', 'Stars', false, stars),
    ArtDef('board', 'Circuit board', false, board),
    ArtDef('glass', 'Broken glass', true, glass),
    ArtDef('crack', 'Cracked screen', true, crackedScreen),
    ArtDef('window', 'Window', true, window),
    ArtDef('porthole', 'Porthole', true, porthole),
    ArtDef('vines', 'Vines', true, vines),
    ArtDef('torn', 'Torn paper', true, tornPaper),
    ArtDef('frost', 'Frost', true, frost),
    ArtDef('rays', 'Light rays', true, lightRays),
    ArtDef('smoke', 'Fog', true, smoke),
    ArtDef('bubbles', 'Bubbles', true, bubbles),
  ];
}

/// One picture of the built-in library. [front] = an overlay with see-through parts.
class ArtDef {
  const ArtDef(this.id, this.name, this.front, this.build);

  final String id;
  final String name;
  final bool front;
  final Future<String> Function() build;
}
