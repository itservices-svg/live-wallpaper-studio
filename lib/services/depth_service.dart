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
  });

  String path;
  String name;
  double d;
  bool cover;
  double w;
  double x;
  double y;
  double f;

  Map<String, dynamic> toJson() => {'p': path, 'n': name, 'd': d, 'c': cover, 'w': w, 'x': x, 'y': y, 'f': f};

  static DepthLayer fromJson(Map<String, dynamic> j) => DepthLayer(
        path: j['p'] as String,
        name: (j['n'] as String?) ?? 'Layer',
        d: (j['d'] as num?)?.toDouble() ?? 0.3,
        cover: (j['c'] as bool?) ?? true,
        w: (j['w'] as num?)?.toDouble() ?? 1.0,
        x: (j['x'] as num?)?.toDouble() ?? 0.5,
        y: (j['y'] as num?)?.toDouble() ?? 0.5,
        f: (j['f'] as num?)?.toDouble() ?? 0.0,
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
}
