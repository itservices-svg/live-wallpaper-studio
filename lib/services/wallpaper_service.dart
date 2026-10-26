import 'package:flutter/services.dart';

enum WallpaperTarget { lock, home, both }

/// Bridge to the native side.
///
/// Prototype behaviour: when no native handler is registered yet
/// (MissingPluginException) every call succeeds, so the UI flow can be tested.
/// See README for what to implement on each platform.
class WallpaperService {
  static const MethodChannel _ch = MethodChannel('live_wallpaper_studio/native');

  /// iOS: write the Live Photo (video + still) and the Home still to Photos.
  static Future<bool> saveLivePhotoPair({
    required String name,
    required double startSec,
    required double endSec,
    required double keyFrameSec,
  }) =>
      _call('saveLivePhotoPair', {
        'name': name,
        'start': startSec,
        'end': endSec,
        'keyFrame': keyFrameSec,
      });

  /// Android: open the system live-wallpaper chooser for this theme
  /// (WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER) or apply a still.
  static Future<bool> setLiveWallpaper({
    required String name,
    required WallpaperTarget target,
  }) =>
      _call('setLiveWallpaper', {'name': name, 'target': target.name});

  static Future<bool> _call(String method, Map<String, Object?> args) async {
    try {
      final ok = await _ch.invokeMethod<bool>(method, args);
      return ok ?? false;
    } on MissingPluginException {
      return true; // prototype mode
    } on PlatformException {
      return false;
    }
  }
}
