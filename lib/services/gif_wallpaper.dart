import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter_wallpaper_plus/flutter_wallpaper_plus.dart' as fwp;
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'wallpaper_service.dart';

/// Turns a GIF into an mp4 that keeps the GIF's own frame timing, then sets
/// that mp4 as the looping live wallpaper.
class GifWallpaper {
  static (int, int) screenSize() {
    var w = 1080, h = 2400;
    try {
      final v = WidgetsBinding.instance.platformDispatcher.views.first;
      final s = v.physicalSize;
      if (s.width > 0 && s.height > 0) {
        w = s.width.round();
        h = s.height.round();
      }
    } catch (_) {}
    if (w > 720) {
      h = (h * 720 / w).round();
      w = 720;
    }
    return (w - w % 2, h - h % 2);
  }

  /// [fit] false = fill the screen (crop); true = whole GIF centred over a
  /// blurred copy of itself. Returns the mp4 path or null.
  static Future<String?> convert(String gifPath, {required bool fit}) async {
    final (w, h) = screenSize();
    // Blur is cheap: shrink the background first, blur it small, scale back up.
    final filter = fit
        ? '[0:v]split[a][b];'
            '[a]scale=${w ~/ 8}:${h ~/ 8}:force_original_aspect_ratio=increase,crop=${w ~/ 8}:${h ~/ 8},'
            'boxblur=3:1,scale=$w:$h[bg];'
            '[b]scale=$w:$h:force_original_aspect_ratio=decrease[fg];'
            '[bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1,format=yuv420p[o]'
        : '[0:v]scale=$w:$h:force_original_aspect_ratio=increase,crop=$w:$h,'
            'setsar=1,format=yuv420p[o]';
    final base = await getApplicationSupportDirectory();
    final dir = await Directory('${base.path}/wallpaper').create(recursive: true);
    final out = '${dir.path}/gifwall_${DateTime.now().millisecondsSinceEpoch}.mp4';
    // -ignore_loop 0 reads the GIF once; the wallpaper player loops the mp4.
    // -vsync vfr keeps each frame's real delay (no speed change).
    final args = <String>[
      '-y',
      '-ignore_loop', '0',
      '-i', gifPath,
      '-filter_complex', filter,
      '-map', '[o]',
      '-an',
      '-fps_mode', 'vfr',
      '-c:v', 'libx264',
      '-preset', 'ultrafast',
      '-tune', 'fastdecode',
      '-crf', '25',
      '-pix_fmt', 'yuv420p',
      '-movflags', '+faststart',
      out,
    ];
    try {
      final session = await FFmpegKit.executeWithArguments(args);
      final code = await session.getReturnCode();
      if (ReturnCode.isSuccess(code) && await File(out).exists() && await File(out).length() > 0) {
        return out;
      }
    } catch (_) {}
    return null;
  }

  /// Sets [mp4] as the looping live wallpaper (Both, falling back to Home).
  static Future<ApplyResult> apply(String mp4) async {
    try {
      var r = await fwp.FlutterWallpaperPlus.setVideoWallpaper(
        source: fwp.WallpaperSource.file(mp4),
        target: fwp.WallpaperTarget.both,
        enableAudio: false,
        loop: true,
        goToHome: false,
      );
      var note = '';
      if (!r.success) {
        r = await fwp.FlutterWallpaperPlus.setVideoWallpaper(
          source: fwp.WallpaperSource.file(mp4),
          target: fwp.WallpaperTarget.home,
          enableAudio: false,
          loop: true,
          goToHome: false,
        );
        note = ' (this phone allows live video on Home only)';
      }
      return r.success
          ? ApplyResult(true, 'Confirm in the system screen to start it$note.')
          : ApplyResult(false, WallpaperService.explain(r));
    } catch (e) {
      return ApplyResult(false, 'Could not set wallpaper: $e');
    }
  }
}
