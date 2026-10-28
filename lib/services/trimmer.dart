import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

import '../state/studio_state.dart';

/// Cuts the chosen range out of the source video, crops it to the phone's
/// screen shape with the user's zoom/pan, and (for Bounce) appends the reversed
/// clip. Runs FFmpeg through a Flutter package: no custom native code.
class Trimmer {
  /// Returns the new mp4 path, or null when FFmpeg failed.
  static Future<String?> render(StudioState s,
      {required int width, required int height, bool themed = false, String prefix = 'live'}) async {
    final src = s.videoPath;
    if (src == null) return null;
    // Even dimensions, capped so encoding stays quick.
    var w = width, h = height;
    const maxW = 1080;
    if (w > maxW) {
      h = (h * maxW / w).round();
      w = maxW;
    }
    w -= w % 2;
    h -= h % 2;

    final z = s.zoom.clamp(1.0, 4.0);
    final cw = w / z, ch = h / z;
    final x = w * (z - 1) / (2 * z) * (1 - s.panX);
    final y = h * (z - 1) / (2 * z) * (1 - s.panY);

    var look = '';
    if (themed) {
      // Same look as the Home still: blur, zoom 1.15, dim, tint.
      final sigma = (s.blur * 0.3 * w / 222).clamp(0.0, 200.0);
      final dim = (s.dim / 100 * 0.8).toStringAsFixed(3);
      final tint = (s.tint / 100 * 0.55).toStringAsFixed(3);
      final c = s.palette[s.tintIdx];
      final hex = ((c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round())
          .toRadixString(16)
          .padLeft(6, '0');
      look = (sigma > 0.1 ? ',gblur=sigma=${sigma.toStringAsFixed(2)}' : '') +
          ',scale=${(w * 1.15).round()}:${(h * 1.15).round()},crop=$w:$h'
              ',drawbox=x=0:y=0:w=iw:h=ih:color=black@$dim:t=fill'
              ',drawbox=x=0:y=0:w=iw:h=ih:color=0x$hex@$tint:t=fill';
    }
    final base = 'scale=$w:$h:force_original_aspect_ratio=increase,'
        'crop=$w:$h,crop=${cw.toStringAsFixed(2)}:${ch.toStringAsFixed(2)}:'
        '${x.toStringAsFixed(2)}:${y.toStringAsFixed(2)},scale=$w:$h,setsar=1,fps=30$look';
    final bounce = s.loop == LoopStyle.bounce;
    // App storage (not cache): the system keeps playing this file as the wallpaper.
    final base0 = await getApplicationSupportDirectory();
    final dir = await Directory('${base0.path}/wallpaper').create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final out = '${dir.path}/${prefix}_$stamp.mp4';

    final args = <String>[
      '-y',
      '-ss', s.start.toStringAsFixed(3),
      '-t', s.span.toStringAsFixed(3),
      '-i', src,
      '-an',
      if (bounce) ...[
        '-filter_complex',
        '[0:v]$base[v];[v]split[a][b];[b]reverse[r];[a][r]concat=n=2:v=1:a=0[o]',
        '-map', '[o]',
      ] else ...['-vf', base],
      '-c:v', 'libx264',
      '-preset', 'veryfast',
      '-crf', '23',
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
}
