import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../state/studio_state.dart';
import '../widgets/mocks.dart' show kMockW;

/// Rendered wallpaper files for the current theme.
class ExportFiles {
  const ExportFiles({required this.lockPath, required this.homePath, this.videoPath});

  final String lockPath;
  final String homePath;
  final String? videoPath;
}

/// Bakes the current theme (key frame, framing, blur, dim, tint) into PNG files
/// at the phone's real screen size. Pure Dart, no native code.
class Exporter {
  static Size _screen() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    var s = views.isEmpty ? const Size(1080, 2400) : views.first.physicalSize;
    if (s.width <= 0 || s.height <= 0) s = const Size(1080, 2400);
    // Keep memory sane on very large screens.
    final longest = math.max(s.width, s.height);
    if (longest > 2800) s = s * (2800 / longest);
    return Size(s.width.roundToDouble(), s.height.roundToDouble());
  }

  static Future<ExportFiles> render(StudioState s) async {
    final size = _screen();
    final src = await _loadSource(s, size);
    try {
      final dir = await Directory.systemTemp.createTemp('lws_');
      final lock = await _draw(s, src, size, home: false, file: File('${dir.path}/lock.png'));
      final home = await _draw(s, src, size, home: true, file: File('${dir.path}/home.png'));
      return ExportFiles(
        lockPath: lock.path,
        homePath: home.path,
        videoPath: s.media.isVideo ? s.videoPath : null,
      );
    } finally {
      src?.dispose();
    }
  }

  static Future<ui.Image?> _loadSource(StudioState s, Size size) async {
    final a = s.media.asset;
    if (a == null) return null; // sample scene: drawn as gradients
    Uint8List? bytes = s.media.isVideo ? s.keyStill : null;
    bytes ??= await a.thumbnailDataWithSize(ThumbnailSize(size.width.round(), size.height.round()));
    if (bytes == null) return null;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  static Future<File> _draw(
    StudioState s,
    ui.Image? img,
    Size size, {
    required bool home,
    required File file,
  }) async {
    final w = size.width, h = size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, rect);

    c.save();
    c.clipRect(rect);
    if (home) {
      final sigma = s.blur * 0.3 * w / kMockW;
      c.saveLayer(rect, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp));
      c.translate(w / 2, h / 2);
      c.scale(1.15);
      c.translate(-w / 2, -h / 2);
    }
    // framing: zoom about the centre, then pan within the free slack
    c.translate(w / 2 + s.panX * (s.zoom - 1) / 2 * w, h / 2 + s.panY * (s.zoom - 1) / 2 * h);
    c.scale(s.zoom);
    c.translate(-w / 2, -h / 2);

    if (img != null) {
      final iw = img.width.toDouble(), ih = img.height.toDouble();
      final k = math.max(w / iw, h / ih); // cover
      final sw = w / k, sh = h / k;
      final srcRect = Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh);
      c.drawImageRect(img, srcRect, rect, Paint()..filterQuality = FilterQuality.high);
    } else {
      _drawScene(c, s, rect);
    }
    if (home) c.restore(); // blur layer
    c.restore();

    if (home) {
      c.drawRect(rect, Paint()..color = Colors.black.withValues(alpha: s.dim / 100 * 0.8));
      c.drawRect(
        rect,
        Paint()..color = s.palette[s.tintIdx].withValues(alpha: s.tint / 100 * 0.55),
      );
    }

    final pic = rec.endRecording();
    final out = await pic.toImage(w.round(), h.round());
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    pic.dispose();
    if (data == null) throw StateError('Could not encode image');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file;
  }

  static void _drawScene(Canvas c, StudioState s, Rect r) {
    final sc = s.scene;
    c.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, sc.sky, const [0, 0.5, 1]),
    );
    c.drawCircle(
      Offset(r.width * 0.7, r.height * 0.42),
      r.width * 0.16,
      Paint()..color = sc.sun.withValues(alpha: 0.9),
    );
    final sea = Rect.fromLTWH(0, r.height * 0.62, r.width, r.height * 0.38);
    c.drawRect(
      sea,
      Paint()..shader = ui.Gradient.linear(sea.topCenter, sea.bottomCenter, sc.sea),
    );
  }
}
