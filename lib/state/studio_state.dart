import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../data/scenes.dart';

enum WallMode { single, theme }

enum LoopStyle { once, loop, bounce }

enum PreviewSide { lock, home }

const _greyPalette = [
  Color(0xFFB8B4C8),
  Color(0xFF9792AE),
  Color(0xFF77728F),
  Color(0xFF58536F),
  Color(0xFF3A3650),
];

/// App-wide state for the create flow. One shared instance keeps the
/// prototype simple; swap for Provider/Riverpod when the app grows.
///
/// The current source is [media]: a sample scene or a real gallery asset.
/// For a real video this class also owns the [VideoPlayerController], the
/// timeline strip frames, the key-frame still and the sampled colours.
class StudioState extends ChangeNotifier {
  static const double minSpan = 0.5;
  static const double _maxLoop = 3.0;
  static const int stripCount = 12;

  // navigation
  int tab = 0;

  // flow
  WallMode mode = WallMode.single;
  bool pickVideo = true;
  MediaItem media = const MediaItem('Coastline Dusk', '0:14', 0);
  String themeName = 'Coastline Dusk';

  // real media
  VideoPlayerController? video;
  bool videoReady = false;
  bool mediaError = false;
  Uint8List? keyStill; // JPEG of the key frame (real videos)
  List<Uint8List?> strip = const []; // timeline frames (real videos)
  List<Color> palette = scenes[0].palette; // 5 colours sampled from the still
  String? _videoPath;
  int _loadToken = 0;
  bool _holding = false;

  // motion editor (seconds)
  double sourceLen = 12.0;
  double start = 2.10;
  double end = 5.10;
  double key = 3.42;
  double playhead = 2.10;
  int _dir = 1;
  bool playing = true;
  LoopStyle loop = LoopStyle.loop;

  // theme builder
  double blur = 24;
  double dim = 32;
  double tint = 68;
  int tintIdx = 0;

  // preview + guide
  PreviewSide side = PreviewSide.lock;
  bool dimPreview = false;
  bool saved = false;
  final Set<String> doneSteps = {};

  /// Debug switch so you can test the iOS and Android flows on one device.
  bool? platformOverrideIOS;

  bool get isIOS =>
      platformOverrideIOS ?? (defaultTargetPlatform == TargetPlatform.iOS);
  Scene get scene => scenes[media.sceneIndex % scenes.length];
  double get span => end - start;
  double get maxSpan => math.min(_maxLoop, sourceLen);
  double get minSpanEff => math.min(minSpan, sourceLen);
  int get exportFiles => mode == WallMode.theme ? 2 : 1;

  // ---- navigation / flow
  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  void setMode(WallMode m) {
    mode = m;
    notifyListeners();
  }

  void openPicker({required bool video}) {
    pickVideo = video;
    notifyListeners();
  }

  void setPlatformOverride(bool? ios) {
    platformOverrideIOS = ios;
    notifyListeners();
  }

  /// Sample scene helper used by Recents and "Kyoto Rain".
  void loadScene(int index, {String? name, bool video = true}) {
    loadMedia(MediaItem(
      name ?? scenes[index % scenes.length].name,
      video ? '0:12' : '',
      index,
    ));
  }

  /// Makes [m] the current source and starts loading whatever it needs.
  void loadMedia(MediaItem m) {
    final token = ++_loadToken;
    _disposeVideo();
    media = m;
    themeName = m.name;
    tintIdx = 0;
    saved = false;
    playing = true;
    _dir = 1;
    _holding = false;
    keyStill = null;
    strip = const [];
    mediaError = false;

    final a = m.asset;
    if (a == null) {
      sourceLen = 12;
      start = 2.10;
      end = 5.10;
      key = 3.42;
      palette = scenes[m.sceneIndex % scenes.length].palette;
    } else {
      sourceLen = m.isVideo ? math.max(m.seconds, 0.5) : _maxLoop;
      start = 0;
      end = math.min(_maxLoop, sourceLen);
      key = (start + end) / 2;
      palette = _greyPalette;
    }
    playhead = start;
    notifyListeners();
    if (a != null) unawaited(_loadReal(m, token));
  }

  Future<void> _loadReal(MediaItem m, int token) async {
    final a = m.asset!;
    try {
      if (!m.isVideo) {
        final bytes = await a.thumbnailDataWithSize(const ThumbnailSize(96, 96));
        await _applyPalette(bytes, token);
        return;
      }
      final file = await a.file;
      if (token != _loadToken) return;
      if (file == null) {
        mediaError = true;
        notifyListeners();
        return;
      }
      _videoPath = file.path;
      final c = VideoPlayerController.file(file);
      await c.initialize();
      if (token != _loadToken) {
        await c.dispose();
        return;
      }
      await c.setVolume(0);
      await c.setLooping(false);
      final len = c.value.duration.inMilliseconds / 1000.0;
      if (len > 0.1 && (len - sourceLen).abs() > 0.05) {
        sourceLen = len;
        start = 0;
        end = math.min(_maxLoop, len);
        key = (start + end) / 2;
        playhead = start;
      }
      video = c;
      videoReady = true;
      strip = List<Uint8List?>.filled(stripCount, null);
      await c.seekTo(Duration(milliseconds: (playhead * 1000).round()));
      if (playing) await c.play();
      notifyListeners();
      unawaited(_buildStrip(token));
      unawaited(refreshKeyStill(token));
    } catch (_) {
      if (token == _loadToken) {
        mediaError = true;
        notifyListeners();
      }
    }
  }

  void _disposeVideo() {
    final old = video;
    video = null;
    videoReady = false;
    _videoPath = null;
    if (old != null) {
      notifyListeners();
      // Dispose after the frame so no widget paints a disposed controller.
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  Future<void> _buildStrip(int token) async {
    final path = _videoPath;
    if (path == null) return;
    for (var i = 0; i < stripCount; i++) {
      if (token != _loadToken) return;
      try {
        final b = await vt.VideoThumbnail.thumbnailData(
          video: path,
          imageFormat: vt.ImageFormat.JPEG,
          timeMs: ((i + 0.5) / stripCount * sourceLen * 1000).round(),
          maxHeight: 120,
          quality: 60,
        );
        if (token != _loadToken) return;
        strip[i] = b;
        notifyListeners();
      } catch (_) {}
    }
  }

  /// Renders the key frame at full size. Used for the Home still and the
  /// resting Lock screen, and re-samples the palette from it.
  Future<void> refreshKeyStill([int? token]) async {
    final t = token ?? _loadToken;
    final path = _videoPath;
    if (path == null) return;
    try {
      final b = await vt.VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: vt.ImageFormat.JPEG,
        timeMs: (key * 1000).round(),
        maxHeight: 1280,
        quality: 85,
      );
      if (t != _loadToken || b == null) return;
      keyStill = b;
      notifyListeners();
      await _applyPalette(b, t);
    } catch (_) {}
  }

  Future<void> _applyPalette(Uint8List? bytes, int token) async {
    if (bytes == null) return;
    final colors = await _sample(bytes);
    if (colors == null || token != _loadToken) return;
    palette = colors;
    notifyListeners();
  }

  /// Averages five horizontal bands (top to bottom) of the image.
  Future<List<Color>?> _sample(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = img.width;
      final h = img.height;
      img.dispose();
      codec.dispose();
      if (data == null || w == 0 || h == 0) return null;
      const bands = 5;
      final out = <Color>[];
      for (var b = 0; b < bands; b++) {
        final y0 = (h * b / bands).floor();
        final y1 = math.max(y0 + 1, (h * (b + 1) / bands).floor());
        var r = 0, g = 0, bl = 0, n = 0;
        for (var y = y0; y < y1 && y < h; y++) {
          for (var x = 0; x < w; x++) {
            final i = (y * w + x) * 4;
            r += data.getUint8(i);
            g += data.getUint8(i + 1);
            bl += data.getUint8(i + 2);
            n++;
          }
        }
        out.add(Color.fromARGB(255, r ~/ n, g ~/ n, bl ~/ n));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  // ---- video helpers
  void _seekTo(double t) {
    final v = video;
    if (!videoReady || v == null) return;
    v.seekTo(Duration(milliseconds: (t * 1000).round()));
  }

  void _syncVideo() {
    final v = video;
    if (!videoReady || v == null) return;
    if (playing && _dir == 1) {
      v.play();
    } else {
      v.pause();
    }
  }

  // ---- motion editor
  void moveWindow(double dt) {
    final s = span;
    start = (start + dt).clamp(0.0, sourceLen - s).toDouble();
    end = start + s;
    _clampMarkers();
    notifyListeners();
  }

  void dragStart(double dt) {
    start = (start + dt)
        .clamp(math.max(0.0, end - maxSpan), end - minSpanEff)
        .toDouble();
    _clampMarkers();
    notifyListeners();
  }

  void dragEnd(double dt) {
    end = (end + dt)
        .clamp(start + minSpanEff, math.min(sourceLen, start + maxSpan))
        .toDouble();
    _clampMarkers();
    notifyListeners();
  }

  void _clampMarkers() {
    key = key.clamp(start, end).toDouble();
    final p = playhead.clamp(start, end).toDouble();
    if (p != playhead) {
      playhead = p;
      _seekTo(p);
    }
  }

  void setKeyAtPlayhead() {
    key = playhead.clamp(start, end).toDouble();
    notifyListeners();
    unawaited(refreshKeyStill());
  }

  void setPlaying(bool p) {
    playing = p;
    _syncVideo();
    notifyListeners();
  }

  void togglePlay() {
    playing = !playing;
    if (playing && loop == LoopStyle.once && playhead >= end) {
      playhead = start;
      _seekTo(start);
    }
    _syncVideo();
    notifyListeners();
  }

  void restart() {
    playhead = start;
    _dir = 1;
    playing = true;
    _seekTo(start);
    _syncVideo();
    notifyListeners();
  }

  void setLoop(LoopStyle l) {
    loop = l;
    _dir = 1;
    if (l != LoopStyle.once) playing = true;
    _syncVideo();
    notifyListeners();
  }

  /// Called every 50 ms by the Motion Editor while it is open.
  void tick(double dt) {
    if (!playing) return;
    final v = videoReady ? video : null; // non-null only when a real video is ready
    final useVideo = v != null && _dir == 1;
    if (useVideo) {
      playhead = math.max(start, v.value.position.inMilliseconds / 1000.0);
    } else {
      playhead += dt * _dir;
    }
    switch (loop) {
      case LoopStyle.once:
        if (playhead >= end) {
          playhead = end;
          playing = false;
          v?.pause();
        }
      case LoopStyle.loop:
        if (playhead >= end) {
          playhead = start;
          _seekTo(start);
          if (v != null && !v.value.isPlaying) v.play();
        }
      case LoopStyle.bounce:
        if (playhead >= end) {
          playhead = end;
          _dir = -1;
          v?.pause();
        } else if (_dir == -1 && playhead <= start) {
          playhead = start;
          _dir = 1;
          _seekTo(start);
          v?.play();
        } else if (_dir == -1) {
          _seekTo(playhead); // video_player cannot play backwards, so step it
        }
    }
    notifyListeners();
  }

  // ---- preview: press and hold plays the loop
  void holdStart() {
    _holding = true;
    playing = false;
    final v = video;
    if (videoReady && v != null) {
      _seekTo(start);
      v.play();
    }
  }

  void holdTick() {
    final v = video;
    if (!_holding || !videoReady || v == null) return;
    if (v.value.position.inMilliseconds / 1000.0 >= end) _seekTo(start);
  }

  void holdEnd() {
    if (!_holding) return;
    _holding = false;
    final v = video;
    if (videoReady && v != null) v.pause();
  }

  // ---- theme builder
  void setBlur(double v) {
    blur = v;
    notifyListeners();
  }

  void setDim(double v) {
    dim = v;
    notifyListeners();
  }

  void setTint(double v) {
    tint = v;
    notifyListeners();
  }

  void setTintIdx(int i) {
    tintIdx = i;
    notifyListeners();
  }

  void setThemeName(String v) {
    themeName = v.trim().isEmpty ? 'Untitled' : v;
  }

  void resetTheme() {
    blur = 24;
    dim = 32;
    tint = 68;
    tintIdx = 0;
    notifyListeners();
  }

  // ---- preview + guide
  void setSide(PreviewSide s) {
    side = s;
    notifyListeners();
  }

  void toggleDimPreview() {
    dimPreview = !dimPreview;
    notifyListeners();
  }

  void markSaved() {
    saved = true;
    notifyListeners();
  }

  void toggleStep(int i) {
    final k = '${isIOS ? 'ios' : 'and'}$i';
    if (!doneSteps.add(k)) doneSteps.remove(k);
    notifyListeners();
  }

  bool stepDone(int i) => doneSteps.contains('${isIOS ? 'ios' : 'and'}$i');
}

final StudioState studio = StudioState();
