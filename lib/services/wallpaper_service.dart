import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_wallpaper_plus/flutter_wallpaper_plus.dart' as fwp;
import 'package:photo_manager/photo_manager.dart';

import 'exporter.dart';

/// What the user can apply. [live] is the system video-wallpaper flow.
enum ApplyTarget { lock, home, both, live, liveLock, liveHome }

class ApplyResult {
  const ApplyResult(this.ok, this.message);
  final bool ok;
  final String message;
}

/// Sets wallpapers through the flutter_wallpaper_plus package (Android) and
/// saves to the photo library on iOS, where apps cannot set wallpapers.
class WallpaperService {
  static const MethodChannel _native = MethodChannel('live_wallpaper_studio/native');

  /// Opens Android's "set live wallpaper" screen for this app's own Lock or Home
  /// video service. [which] is 'lock' or 'home'.
  static Future<bool> openLive(String which) async {
    try {
      return (await _native.invokeMethod<bool>('openLive', {'which': which})) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<ApplyResult> applyAndroid(ApplyTarget t, ExportFiles f) async {
    try {
      switch (t) {
        case ApplyTarget.lock:
          return _image(f.lockPath, fwp.WallpaperTarget.lock, 'Lock screen updated');
        case ApplyTarget.home:
          return _image(f.homePath, fwp.WallpaperTarget.home, 'Home screen updated');
        case ApplyTarget.both:
          final lock = await _image(f.lockPath, fwp.WallpaperTarget.lock, '');
          if (!lock.ok) return lock;
          final home = await _image(f.homePath, fwp.WallpaperTarget.home, '');
          if (!home.ok) return home;
          return const ApplyResult(true, 'Lock + Home updated');
        case ApplyTarget.liveLock:
        case ApplyTarget.liveHome:
          return const ApplyResult(false, 'Handled by the preview screen.');
        case ApplyTarget.live:
          final v = f.videoPath;
          if (v == null) return const ApplyResult(false, 'Live wallpaper needs a video.');
          const themed = false;
          // Plain live: target "both" lets Android's own chooser apply it to Home and Lock.
          var r = await fwp.FlutterWallpaperPlus.setVideoWallpaper(
            source: fwp.WallpaperSource.file(v),
            target: themed ? fwp.WallpaperTarget.home : fwp.WallpaperTarget.both,
            enableAudio: false,
            loop: true,
            goToHome: false,
          );
          var note = '';
          if (!r.success && !themed) {
            // Some phones only allow live video on Home.
            r = await fwp.FlutterWallpaperPlus.setVideoWallpaper(
              source: fwp.WallpaperSource.file(v),
              target: fwp.WallpaperTarget.home,
              enableAudio: false,
              loop: true,
              goToHome: false,
            );
            note = ' (this phone allows live video on Home only)';
          }
          final cut = f.trimmed ? '' : ' Trim failed, whole clip used.';
          return r.success
              ? ApplyResult(true, 'Confirm in the system screen to start it$note.$cut')
              : ApplyResult(false, _explain(r));
      }
    } catch (e) {
      return ApplyResult(false, 'Could not set wallpaper: $e');
    }
  }

  static Future<ApplyResult> _image(String path, fwp.WallpaperTarget target, String okMsg) async {
    final r = await fwp.FlutterWallpaperPlus.setImageWallpaper(
      source: fwp.WallpaperSource.file(path),
      target: target,
    );
    return r.success ? ApplyResult(true, okMsg) : ApplyResult(false, _explain(r));
  }

  static String _explain(fwp.WallpaperResult r) {
    switch (r.errorCode) {
      case fwp.WallpaperErrorCode.permissionDenied:
        return 'Permission denied. Allow wallpaper/media access and try again.';
      case fwp.WallpaperErrorCode.manufacturerRestriction:
        return 'This phone restricts setting this screen from apps. Try Home only, or set it from Gallery.';
      case fwp.WallpaperErrorCode.unsupported:
        return 'This option is not supported on your phone.';
      default:
        return r.message.isEmpty ? 'Could not set wallpaper.' : r.message;
    }
  }

  /// iOS: write the stills (and the clip for videos) to Photos.
  static Future<ApplyResult> saveToPhotos(ExportFiles f, {required String name}) async {
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.hasAccess) return const ApplyResult(false, 'Allow Photos access to save.');
      final v = f.videoPath;
      if (v != null) {
        await PhotoManager.editor.saveVideo(File(v), title: '$name.mov');
      }
      await PhotoManager.editor.saveImageWithPath(f.lockPath, title: '$name Lock.png');
      await PhotoManager.editor.saveImageWithPath(f.homePath, title: '$name Home.png');
      return const ApplyResult(true, 'Saved to Photos');
    } catch (e) {
      return ApplyResult(false, 'Could not save: $e');
    }
  }

  /// Saves a GIF into the phone's gallery (Pictures), so it shows in Photos/Downloads apps.
  static Future<ApplyResult> saveGif(String path, {required String name}) async {
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.hasAccess) return const ApplyResult(false, 'Allow Photos access to save the GIF.');
      final safe = name.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
      final entity = await PhotoManager.editor.saveImageWithPath(
        path,
        title: '${safe.isEmpty ? 'loop' : safe}.gif',
      );
      return ApplyResult(true, 'GIF saved to your gallery (${entity.title ?? 'gif'})');
    } catch (e) {
      return ApplyResult(false, 'Could not save the GIF: $e');
    }
  }
}
