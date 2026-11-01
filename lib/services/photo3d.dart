import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'depth_service.dart';

/// Cuts one photo into depth layers from a hand-made mask: 0 = far (stays as background),
/// 1 = middle, 2 = near (for example a tree in front). The part hidden behind a nearer layer
/// is filled in from its surroundings, so nothing opens up when the layers slide.
class Photo3d {
  static Future<ui.Image> fromRgba(Uint8List px, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  static Future<ui.Image> _render(int w, int h, void Function(Canvas) fn) {
    final rec = ui.PictureRecorder();
    fn(Canvas(rec));
    return rec.endRecording().toImage(w, h);
  }

  /// Min (erode) or max (dilate) filter with a square window of radius [r] on a 0/255 mask.
  static Uint8List morph(Uint8List src, int w, int h, int r, bool erode) {
    final tmp = Uint8List(w * h);
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var v = erode ? 255 : 0;
        for (var k = math.max(0, x - r); k <= math.min(w - 1, x + r); k++) {
          final s = src[y * w + k];
          if (erode ? s < v : s > v) v = s;
        }
        tmp[y * w + x] = v;
      }
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var v = erode ? 255 : 0;
        for (var k = math.max(0, y - r); k <= math.min(h - 1, y + r); k++) {
          final s = tmp[k * w + x];
          if (erode ? s < v : s > v) v = s;
        }
        out[y * w + x] = v;
      }
    }
    return out;
  }

  /// 3x3 box blur, twice: soft edges.
  static Uint8List soft(Uint8List a, int w, int h) {
    var src = a;
    for (var pass = 0; pass < 2; pass++) {
      final out = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var sum = 0, n = 0;
          for (var dy = -1; dy <= 1; dy++) {
            final yy = y + dy;
            if (yy < 0 || yy >= h) continue;
            for (var dx = -1; dx <= 1; dx++) {
              final xx = x + dx;
              if (xx < 0 || xx >= w) continue;
              sum += src[yy * w + xx];
              n++;
            }
          }
          out[y * w + x] = sum ~/ n;
        }
      }
      src = out;
    }
    return src;
  }

  static Uint8List _alphaPixels(Uint8List a) {
    final px = Uint8List(a.length * 4);
    for (var i = 0; i < a.length; i++) {
      px[i * 4] = 255;
      px[i * 4 + 1] = 255;
      px[i * 4 + 2] = 255;
      px[i * 4 + 3] = a[i];
    }
    return px;
  }

  /// Fills the pixels where [valid] is 0 with colours spread in from the valid ones.
  /// [rgba] is w*h*4; returns a new rgba buffer, fully opaque.
  static Uint8List fill(Uint8List rgba, Uint8List valid, int w, int h) {
    final n = w * h;
    final r = Float32List(n), g = Float32List(n), b = Float32List(n);
    final v = Uint8List(n);
    var left = 0;
    var sr = 0.0, sg = 0.0, sb = 0.0, cnt = 0;
    for (var i = 0; i < n; i++) {
      r[i] = rgba[i * 4].toDouble();
      g[i] = rgba[i * 4 + 1].toDouble();
      b[i] = rgba[i * 4 + 2].toDouble();
      if (valid[i] > 127) {
        v[i] = 1;
        sr += r[i];
        sg += g[i];
        sb += b[i];
        cnt++;
      } else {
        left++;
      }
    }
    if (cnt == 0) {
      sr = sg = sb = 20;
      cnt = 1;
    }
    final iw = w + 1;
    final ir = Float64List(iw * (h + 1)),
        ig = Float64List(iw * (h + 1)),
        ib = Float64List(iw * (h + 1)),
        ic = Float64List(iw * (h + 1));
    for (var rad = 2; left > 0 && rad <= 512; rad *= 2) {
      for (var y = 0; y < h; y++) {
        var rr = 0.0, gg = 0.0, bb = 0.0, cc = 0.0;
        for (var x = 0; x < w; x++) {
          final i = y * w + x;
          if (v[i] == 1) {
            rr += r[i];
            gg += g[i];
            bb += b[i];
            cc += 1;
          }
          final o = (y + 1) * iw + x + 1;
          ir[o] = ir[o - iw] + rr;
          ig[o] = ig[o - iw] + gg;
          ib[o] = ib[o - iw] + bb;
          ic[o] = ic[o - iw] + cc;
        }
      }
      final fresh = <int>[];
      for (var y = 0; y < h; y++) {
        final y0 = math.max(0, y - rad), y1 = math.min(h, y + rad + 1);
        for (var x = 0; x < w; x++) {
          final i = y * w + x;
          if (v[i] == 1) continue;
          final x0 = math.max(0, x - rad), x1 = math.min(w, x + rad + 1);
          double box(Float64List a) => a[y1 * iw + x1] - a[y0 * iw + x1] - a[y1 * iw + x0] + a[y0 * iw + x0];
          final c = box(ic);
          if (c > 0) {
            r[i] = box(ir) / c;
            g[i] = box(ig) / c;
            b[i] = box(ib) / c;
            fresh.add(i);
          }
        }
      }
      for (final i in fresh) {
        v[i] = 1;
      }
      left -= fresh.length;
    }
    final out = Uint8List(n * 4);
    for (var i = 0; i < n; i++) {
      final ok = v[i] == 1;
      out[i * 4] = ok ? r[i].round().clamp(0, 255).toInt() : (sr / cnt).round();
      out[i * 4 + 1] = ok ? g[i].round().clamp(0, 255).toInt() : (sg / cnt).round();
      out[i * 4 + 2] = ok ? b[i].round().clamp(0, 255).toInt() : (sb / cnt).round();
      out[i * 4 + 3] = 255;
    }
    return out;
  }

  /// Builds the layers (back to front). [cls] is the mask, [mw] x [mh] values 0 / 1 / 2.
  /// Returns null if nothing is selected.
  static Future<List<DepthLayer>?> build(String photoPath, Uint8List cls, int mw, int mh) async {
    var maxCls = 0;
    final present = <int>{0};
    for (final c in cls) {
      if (c > 0) present.add(c);
      if (c > maxCls) maxCls = c;
    }
    if (maxCls == 0) return null;
    final levels = present.toList()..sort();

    final codec = await ui.instantiateImageCodec(await File(photoPath).readAsBytes());
    final photo = (await codec.getNextFrame()).image;
    final pw = photo.width, ph = photo.height;
    final sc = math.min(1.0, 1600 / math.max(pw, ph));
    final ow = (pw * sc).round(), oh = (ph * sc).round();
    final srcP = Rect.fromLTWH(0, 0, pw.toDouble(), ph.toDouble());
    final dst = Rect.fromLTWH(0, 0, ow.toDouble(), oh.toDouble());

    final small = await _render(mw, mh, (c) {
      c.drawImageRect(photo, srcP, Rect.fromLTWH(0, 0, mw.toDouble(), mh.toDouble()),
          Paint()..filterQuality = FilterQuality.medium);
    });
    final smallPx = (await small.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
    small.dispose();

    final dir = await DepthService.dir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final out = <DepthLayer>[];
    final hq = Paint()..filterQuality = FilterQuality.high;
    final blend = Paint()
      ..filterQuality = FilterQuality.high
      ..blendMode = BlendMode.dstIn;

    double depthFor(int level) {
      if (level == 0) return 0.12;
      if (levels.length == 2) return 0.75;
      return level == 1 ? 0.4 : 0.8;
    }

    for (final level in levels) {
      final hole = level < maxCls;
      ui.Image? fillImg, validImg, alphaImg;
      if (hole) {
        final valid = Uint8List(cls.length);
        for (var i = 0; i < cls.length; i++) {
          valid[i] = cls[i] <= level ? 255 : 0;
        }
        final eroded = morph(valid, mw, mh, 2, true);
        fillImg = await fromRgba(fill(smallPx, eroded, mw, mh), mw, mh);
        validImg = await fromRgba(_alphaPixels(soft(morph(valid, mw, mh, 1, true), mw, mh)), mw, mh);
      }
      if (level > 0) {
        final a = Uint8List(cls.length);
        for (var i = 0; i < cls.length; i++) {
          a[i] = cls[i] >= level ? 255 : 0;
        }
        alphaImg = await fromRgba(_alphaPixels(soft(morph(a, mw, mh, 1, true), mw, mh)), mw, mh);
      }
      Rect srcOf(ui.Image i) => Rect.fromLTWH(0, 0, i.width.toDouble(), i.height.toDouble());
      final img = await _render(ow, oh, (c) {
        c.saveLayer(dst, Paint());
        if (fillImg != null) c.drawImageRect(fillImg, srcOf(fillImg), dst, hq);
        c.saveLayer(dst, Paint());
        c.drawImageRect(photo, srcP, dst, hq);
        if (validImg != null) c.drawImageRect(validImg, srcOf(validImg), dst, blend);
        c.restore();
        if (alphaImg != null) c.drawImageRect(alphaImg, srcOf(alphaImg), dst, blend);
        c.restore();
      });
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      fillImg?.dispose();
      validImg?.dispose();
      alphaImg?.dispose();
      final path = '${dir.path}/p3d_${stamp}_$level.png';
      await File(path).writeAsBytes(data!.buffer.asUint8List(), flush: true);
      out.add(DepthLayer(
        path: path,
        name: level == 0 ? 'Far' : (level == 1 ? 'Middle' : 'Near'),
        d: depthFor(level),
        cover: true,
      ));
    }
    photo.dispose();
    final k = 1 + 0.2 * out.map((l) => l.d).reduce(math.max);
    for (final l in out) {
      l.k = k;
    }
    return out;
  }
}
