import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../data/scenes.dart';
import '../services/gif_art.dart';
import '../services/library_store.dart';
import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/effects.dart';
import '../widgets/frame_painter.dart';
import 'explore_screen.dart';
import 'pick_media_screen.dart';
import 'preview_screen.dart' show kGifPresets;

/// One video in the GIF, with the part of it that is used.
class _Clip {
  _Clip(this.path, this.name, this.length, this.size, this.assetId) {
    end = math.min(length, 4.0);
  }

  final String path;
  final String name;
  final double length; // seconds
  final Size size;
  final String? assetId; // gallery id, so the clip can be found again when editing
  int trans = 1; // transition into this clip from the previous one (index into _transitions)
  double start = 0;
  late double end;
  List<Uint8List?> strip = List<Uint8List?>.filled(8, null);

  double get span => end - start;
}

/// Transitions between two clips: label, the FFmpeg `xfade` name, and an effect drawn over the
/// picture while it plays. 'Cut' is a very short fade.
const _transitions = <(String, String, TransFx)>[
  ('Cut', 'fade', TransFx.none),
  ('Fade', 'fade', TransFx.none),
  ('Slide', 'slideleft', TransFx.none),
  ('Wipe', 'wipeleft', TransFx.none),
  ('Circle', 'circleopen', TransFx.none),
  ('Zoom', 'zoomin', TransFx.none),
  ('Dissolve', 'dissolve', TransFx.none),
  ('Pixelate', 'pixelize', TransFx.none),
  ('Radial', 'radial', TransFx.none),
  ('Black fade', 'fadeblack', TransFx.none),
  ('Fire', 'wipeup', TransFx.fire),
  ('Lightning', 'fadewhite', TransFx.lightning),
  ('Sparkle', 'fade', TransFx.sparkle),
  ('Hearts', 'fade', TransFx.hearts),
  ('Confetti', 'fade', TransFx.confetti),
];

class _RectClipper extends CustomClipper<Rect> {
  const _RectClipper(this.rect);
  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(_RectClipper old) => old.rect != rect;
}

class _CircleClipper extends CustomClipper<Path> {
  const _CircleClipper(this.p);
  final double p;

  @override
  Path getClip(Size size) {
    final r = p * math.sqrt(size.width * size.width + size.height * size.height) / 2;
    return Path()..addOval(Rect.fromCircle(center: size.center(Offset.zero), radius: r));
  }

  @override
  bool shouldReclip(_CircleClipper old) => old.p != p;
}

class _SweepClipper extends CustomClipper<Path> {
  const _SweepClipper(this.p);
  final double p;

  @override
  Path getClip(Size size) {
    final c = size.center(Offset.zero);
    final r = math.sqrt(size.width * size.width + size.height * size.height);
    return Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(c.dx, c.dy - r)
      ..arcTo(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * p, false)
      ..close();
  }

  @override
  bool shouldReclip(_SweepClipper old) => old.p != p;
}

const _shapes = <(String, double)>[
  ('Original', 0),
  ('1:1', 1),
  ('4:5', 4 / 5),
  ('9:16', 9 / 16),
  ('16:9', 16 / 9),
];

/// Make a GIF from one or more videos: pick the part of each, crop, size, and join.
class GifEditorScreen extends StatefulWidget {
  /// [project]: saved GIF project JSON to edit again; [replaceId]: the saved GIF it replaces.
  /// [initialClip] / [initialArt]: start with this video, or this picture around the frame.
  const GifEditorScreen({super.key, this.project, this.replaceId, this.initialClip, this.initialArt});

  final String? project;
  final String? replaceId;
  final MediaItem? initialClip;
  final String? initialArt;

  @override
  State<GifEditorScreen> createState() => _GifEditorScreenState();
}

class _GifEditorScreenState extends State<GifEditorScreen> with SingleTickerProviderStateMixin {
  final List<_Clip> _clips = [];
  int _sel = -1;
  VideoPlayerController? _ctrl;

  int _shape = 0;
  int _quality = 1;
  double _zoom = 1;
  double _panX = 0;
  double _panY = 0;
  bool _busy = false;
  bool _adding = false;

  late final AnimationController _clock;
  Timer? _ticker;
  final Stopwatch _sw = Stopwatch();
  double _posBase = 0; // playback position (seconds in the clip) when the stopwatch was reset
  VideoPlayerController? _next; // the following clip, ready for the transition
  int _nextIdx = -1;
  bool _inTrans = false;
  double _tp = 0; // transition progress 0..1
  int _preloadToken = 0;
  FrameAnim _anim = FrameAnim.none;
  double _transDur = 0.5;
  bool _playAll = true;
  bool _switching = false;

  FrameShape _fshape = FrameShape.none;
  double _pad = 0.12;
  int _border = 0;
  int _bg = 0;
  String? _artPath;
  ui.Image? _artImg;
  List<File> _arts = [];

  FrameStyle get _style =>
      FrameStyle(shape: _fshape, pad: _pad, border: _border, bg: _bg, art: _artImg, anim: _anim);

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
    _loadArts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _clock.dispose();
    _ticker?.cancel();
    _ctrl?.dispose();
    _next?.dispose();
    super.dispose();
  }

  _Clip? get _cur => (_sel >= 0 && _sel < _clips.length) ? _clips[_sel] : null;

  /// Length of the joined GIF: the clips minus the overlap of each transition.
  double get _totalSeconds {
    var t = _clips.fold<double>(0, (a, c) => a + c.span);
    for (var k = 0; k < _clips.length - 1; k++) {
      t -= _junction(k);
    }
    return math.max(t, 0.1);
  }

  /// Overlap (seconds) between clip [k] and clip [k + 1].
  double _junction(int k) {
    if (k < 0 || k + 1 >= _clips.length) return 0;
    if (_clips[k + 1].trans == 0) return 0.05;
    final limit = 0.45 * math.min(_clips[k].span, _clips[k + 1].span);
    return math.max(0.05, math.min(_transDur, limit));
  }

  double _aspect() {
    final f = _shapes[_shape].$2;
    if (f > 0) return f;
    final c = _cur ?? (_clips.isEmpty ? null : _clips.first);
    if (c == null || c.size.height == 0) return 9 / 16;
    return c.size.width / c.size.height;
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<void> _boot() async {
    final proj = widget.project;
    if (proj != null) {
      await _restore(proj);
      return;
    }
    if (widget.initialArt != null) {
      await _setArt(widget.initialArt);
      _fshape = FrameShape.round;
      _shape = 1;
      if (mounted) setState(() {});
      _loadArts();
    }
    final first = widget.initialClip;
    if (first != null) {
      await _addItem(first);
      return;
    }
    await _addClip(first: true);
  }

  Future<void> _loadArts() async {
    final list = await GifArt.list();
    if (mounted) setState(() => _arts = list);
  }

  Future<void> _setArt(String? path) async {
    if (path == null) {
      _artPath = null;
      _artImg = null;
      if (mounted) setState(() {});
      return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 720);
      final frame = await codec.getNextFrame();
      codec.dispose();
      _artImg = frame.image;
      _artPath = path;
    } catch (_) {
      _artImg = null;
      _artPath = null;
    }
    if (mounted) setState(() {});
  }

  /// Asks where a picture or video comes from. Returns 'gallery', 'explore' or null.
  Future<String?> _chooseSource({required String title, required String exploreLabel}) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text(title, style: AppText.h2),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('From gallery'),
                onTap: () => Navigator.pop(c, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.explore_outlined),
                title: Text(exploreLabel),
                onTap: () => Navigator.pop(c, 'explore'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _itemPath(MediaItem item) async {
    if (item.asset != null) return (await item.asset!.file)?.path;
    return item.file;
  }

  Future<void> _addClip({bool first = false}) async {
    if (_adding || _busy) return;
    _adding = true;
    try {
      final src = await _chooseSource(title: 'Add a video', exploreLabel: 'From Explore (free videos)');
      MediaItem? item;
      if (src == 'gallery') {
        studio.openPicker(video: true);
        if (!mounted) return;
        item = await Navigator.of(context).push<MediaItem>(
            MaterialPageRoute(builder: (_) => const PickMediaScreen(forGif: true)));
      } else if (src == 'explore') {
        if (!mounted) return;
        item = await Navigator.of(context).push<MediaItem>(MaterialPageRoute(
            builder: (_) => const ExploreScreen(allowed: [1], title: 'Pick a video')));
      }
      if (item == null) {
        if (first && _clips.isEmpty && mounted) Navigator.of(context).pop();
        return;
      }
      await _addItem(item);
    } finally {
      _adding = false;
    }
  }

  Future<void> _addItem(MediaItem item) async {
    final path = await _itemPath(item);
    if (path == null) {
      _toast('This clip is not available. Pick a video from your gallery.');
      return;
    }
    await _attach(path, item.name, item.asset?.id);
  }

  Future<void> _addArt() async {
    if (_adding || _busy) return;
    _adding = true;
    try {
      final src = await _chooseSource(
          title: 'Add a picture around the frame',
          exploreLabel: 'From Explore (vectors, frames, illustrations)');
      MediaItem? item;
      if (src == 'gallery') {
        studio.openPicker(video: false);
        if (!mounted) return;
        item = await Navigator.of(context).push<MediaItem>(
            MaterialPageRoute(builder: (_) => const PickMediaScreen(forGif: true, photos: true)));
      } else if (src == 'explore') {
        if (!mounted) return;
        item = await Navigator.of(context).push<MediaItem>(MaterialPageRoute(
            builder: (_) => const ExploreScreen(allowed: [2, 3, 4, 0], title: 'Pick a picture')));
      }
      if (item == null) return;
      final path = await _itemPath(item);
      if (path == null) {
        _toast('This picture is not available.');
        return;
      }
      final stored = await GifArt.add(path);
      await _setArt(stored);
      await _loadArts();
    } catch (e) {
      if (mounted) _toast('Could not add the picture: $e');
    } finally {
      _adding = false;
    }
  }

  /// Opens [path] as a new clip and makes it the one being edited.
  Future<void> _attach(String path, String name, String? assetId,
      {double? start, double? end, int? trans}) async {
    try {
      final c = VideoPlayerController.file(File(path));
      await c.initialize();
      final len = c.value.duration.inMilliseconds / 1000.0;
      final clip = _Clip(path, name, len, c.value.size, assetId);
      if (trans != null) clip.trans = trans.clamp(0, _transitions.length - 1).toInt();
      if (start != null) clip.start = start.clamp(0.0, len).toDouble();
      if (end != null) clip.end = end.clamp(clip.start, len).toDouble();
      await c.setVolume(0);
      if (!mounted) {
        await c.dispose();
        return;
      }
      final old = _ctrl;
      _ctrl = c;
      _clips.add(clip);
      _sel = _clips.length - 1;
      _startPlayback();
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
      unawaited(_loadStrip(clip));
    } catch (e) {
      if (mounted) _toast('Could not open that video: $e');
    }
  }

  Future<void> _restore(String json) async {
    try {
      final j = jsonDecode(json) as Map<String, dynamic>;
      int i(String k, int def, int max) => ((j[k] as num?)?.toInt() ?? def).clamp(0, max).toInt();
      double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
      _shape = i('crop', 0, _shapes.length - 1);
      _quality = i('q', 1, kGifPresets.length - 1);
      _zoom = d('z', 1).clamp(1.0, 3.0).toDouble();
      _panX = d('px', 0).clamp(-1.0, 1.0).toDouble();
      _panY = d('py', 0).clamp(-1.0, 1.0).toDouble();
      _fshape = FrameShape.values[i('f', 0, FrameShape.values.length - 1)];
      _pad = d('pad', 0.12).clamp(0.02, 0.3).toDouble();
      _border = i('b', 0, kFrameBorders.length - 1);
      _bg = ((j['bg'] as num?)?.toInt() ?? 0).clamp(-1, kFrameBgs.length - 1).toInt();
      _anim = FrameAnim.values[i('an', 0, FrameAnim.values.length - 1)];
      _transDur = d('td', 0.5).clamp(0.2, 1.2).toDouble();
      final art = j['art'] as String?;
      if (art != null && await File(art).exists()) await _setArt(art);
      if (mounted) setState(() {});

      var missing = 0;
      for (final c in (j['clips'] as List? ?? const [])) {
        final m = c as Map;
        final a = m['a'] as String?;
        String? path;
        if (a != null && a.isNotEmpty) {
          final ent = await AssetEntity.fromId(a);
          path = (await ent?.file)?.path;
        }
        path ??= m['p'] as String?;
        if (path == null || !await File(path).exists()) {
          missing++;
          continue;
        }
        await _attach(path, (m['n'] as String?) ?? 'Clip', a,
            start: (m['s'] as num?)?.toDouble(),
            end: (m['e'] as num?)?.toDouble(),
            trans: (m['t'] as num?)?.toInt());
      }
      if (!mounted) return;
      if (_clips.isEmpty) {
        _toast('The videos of this GIF are no longer available.');
        Navigator.of(context).pop();
        return;
      }
      if (missing > 0) _toast('$missing video(s) are no longer available and were skipped.');
      await _select(0);
    } catch (e) {
      if (mounted) {
        _toast('Could not open this GIF for editing.');
        Navigator.of(context).pop();
      }
    }
  }

  String _projectJson() => jsonEncode({
        'v': 1,
        'clips': [
          for (final c in _clips)
            {'a': c.assetId, 'p': c.path, 'n': c.name, 's': c.start, 'e': c.end, 't': c.trans},
        ],
        'crop': _shape,
        'q': _quality,
        'z': _zoom,
        'px': _panX,
        'py': _panY,
        'f': _fshape.index,
        'pad': _pad,
        'b': _border,
        'bg': _bg,
        'an': _anim.index,
        'td': _transDur,
        'art': _artPath,
      });

  Future<void> _select(int i) async {
    if (i == _sel || i < 0 || i >= _clips.length) return;
    final clip = _clips[i];
    final c = VideoPlayerController.file(File(clip.path));
    try {
      await c.initialize();
      await c.setVolume(0);
    } catch (_) {
      await c.dispose();
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    final old = _ctrl;
    _ctrl = c;
    _sel = i;
    _startPlayback();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    if (clip.strip.every((e) => e == null)) unawaited(_loadStrip(clip));
  }

  double _localPos() => _posBase + _sw.elapsedMilliseconds / 1000.0;

  /// Jumps the current clip to [sec] and restarts the playback clock.
  void _restartAt(double sec) {
    final c = _ctrl;
    if (c == null) return;
    c.seekTo(Duration(milliseconds: (sec * 1000).round()));
    _posBase = sec;
    _sw
      ..reset()
      ..start();
    if (!c.value.isPlaying) c.play();
  }

  void _startPlayback() {
    final c = _ctrl, clip = _cur;
    if (c == null || clip == null) return;
    _inTrans = false;
    _tp = 0;
    c.setLooping(false);
    _restartAt(clip.start);
    unawaited(_preloadNext(force: true));
  }

  /// Loads the clip that follows the current one, so a transition can start without a pause.
  Future<void> _preloadNext({bool force = false}) async {
    final n = _clips.length;
    final want = (_playAll && n > 1 && _sel >= 0 && _sel < n - 1) ? _sel + 1 : -1;
    if (!force && want == _nextIdx && _next != null) return;
    final token = ++_preloadToken;
    final old = _next;
    _next = null;
    _nextIdx = -1;
    _inTrans = false;
    _tp = 0;
    if (old != null) {
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    if (want < 0) return;
    final clip = _clips[want];
    final c = VideoPlayerController.file(File(clip.path));
    try {
      await c.initialize();
      await c.setVolume(0);
      await c.setLooping(false);
      await c.seekTo(Duration(milliseconds: (clip.start * 1000).round()));
    } catch (_) {
      await c.dispose();
      return;
    }
    if (!mounted || token != _preloadToken) {
      await c.dispose();
      return;
    }
    _next = c;
    _nextIdx = want;
  }

  /// Runs ~30 times a second: loops the clip, starts transitions and moves to the next clip.
  void _tick() {
    if (!mounted || _busy) return;
    final c = _ctrl, clip = _cur;
    if (c == null || clip == null || !c.value.isInitialized) return;
    final pos = _localPos();
    final n = _clips.length;
    final multi = _playAll && n > 1;

    if (multi && _sel < n - 1) {
      final t = _junction(_sel);
      final nx = _next;
      if (t > 0 && nx != null && _nextIdx == _sel + 1 && nx.value.isInitialized && pos >= clip.end - t) {
        if (!_inTrans) {
          _inTrans = true;
          nx.seekTo(Duration(milliseconds: (_clips[_nextIdx].start * 1000).round()));
          nx.play();
        }
        if (pos >= clip.end - 0.02) {
          _swapToNext();
        } else {
          setState(() => _tp = ((pos - (clip.end - t)) / t).clamp(0.0, 1.0).toDouble());
        }
        return;
      }
    }

    if (pos >= clip.end - 0.02) {
      if (multi) {
        // No smooth transition possible here (last clip, or the next one is not ready): cut.
        if (!_switching) {
          _switching = true;
          c.pause();
          unawaited(_advance());
        }
        return;
      }
      _restartAt(clip.start);
    } else if (!c.value.isPlaying && !_switching) {
      c.play();
    }
  }

  /// The transition is over: the next clip (already playing) becomes the current one.
  void _swapToNext() {
    final nx = _next;
    if (nx == null) return;
    final old = _ctrl;
    final idx = _nextIdx;
    final t = _junction(idx - 1);
    _ctrl = nx;
    _next = null;
    _nextIdx = -1;
    _sel = idx;
    _inTrans = false;
    _tp = 0;
    _posBase = _clips[idx].start + t;
    _sw
      ..reset()
      ..start();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    if (_clips[idx].strip.every((e) => e == null)) unawaited(_loadStrip(_clips[idx]));
    unawaited(_preloadNext());
  }

  Future<void> _advance() async {
    try {
      await _select((_sel + 1) % _clips.length);
    } finally {
      _switching = false;
    }
  }

  Future<void> _loadStrip(_Clip clip) async {
    for (var i = 0; i < clip.strip.length; i++) {
      if (!mounted) return;
      try {
        final b = await vt.VideoThumbnail.thumbnailData(
          video: clip.path,
          imageFormat: vt.ImageFormat.JPEG,
          timeMs: ((i + 0.5) / clip.strip.length * clip.length * 1000).round(),
          maxHeight: 120,
          quality: 60,
        );
        clip.strip[i] = b;
        if (mounted) setState(() {});
      } catch (_) {}
    }
  }

  Future<void> _remove(int i) async {
    if (_busy) return;
    final wasSel = i == _sel;
    _clips.removeAt(i);
    if (_clips.isEmpty) {
      final old = _ctrl;
      _ctrl = null;
      _sel = -1;
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
      unawaited(_preloadNext(force: true));
      return;
    }
    if (wasSel) {
      _sel = -1;
      await _select(math.min(i, _clips.length - 1));
    } else {
      if (i < _sel) _sel--;
      if (mounted) setState(() {});
      unawaited(_preloadNext(force: true));
    }
  }

  void _setRange(RangeValues v) {
    final clip = _cur;
    if (clip == null) return;
    var s = v.start, e = v.end;
    final minSpan = math.min(0.3, clip.length);
    if (e - s < minSpan) {
      if (s != clip.start) {
        s = e - minSpan;
      } else {
        e = s + minSpan;
      }
    }
    clip.start = s.clamp(0.0, clip.length).toDouble();
    clip.end = e.clamp(clip.start, clip.length).toDouble();
    final pos = _localPos();
    if (pos < clip.start || pos > clip.end) _restartAt(clip.start);
    setState(() {});
  }

  // ---- export

  /// Builds the GIF with FFmpeg and returns its path, or null if FFmpeg failed.
  /// [animate]: animated border. [xfade]: smooth transitions (false = plain cuts).
  Future<String?> _render({required bool animate, required bool xfade, bool trFx = true}) async {
    final q = kGifPresets[_quality];
    final ar = _aspect();
    var w = q.width;
    var h = (w / ar).round();
    if (h > 1280) {
      h = 1280;
      w = (h * ar).round();
    }
    w -= w % 2;
    h -= h % 2;
    final fps = q.fps;
    final ax = ((_panX + 1) / 2).toStringAsFixed(3);
    final ay = ((_panY + 1) / 2).toStringAsFixed(3);
    var cw = (w / _zoom).floor();
    var ch = (h / _zoom).floor();
    cw -= cw % 2;
    ch -= ch % 2;
    final vf = 'fps=$fps,scale=$w:$h:force_original_aspect_ratio=increase,'
        'crop=$w:$h:(iw-$w)*$ax:(ih-$h)*$ay'
        '${_zoom > 1.001 ? ',crop=$cw:$ch,scale=$w:$h' : ''},setsar=1,format=yuv420p';

    final n = _clips.length;
    final dur = xfade ? _totalSeconds : _clips.fold<double>(0, (a, c) => a + c.span);
    final dStr = dur.toStringAsFixed(3);
    final style = animate ? _style : _style.still();
    final args = <String>['-y'];
    for (final c in _clips) {
      args.addAll(['-ss', c.start.toStringAsFixed(3), '-t', c.span.toStringAsFixed(3), '-i', c.path]);
    }

    final tmp = await getTemporaryDirectory();
    final dir = await Directory('${tmp.path}/gif').create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;

    Future<String> draw(void Function(Canvas, Size) fn, String path) async {
      final rec = ui.PictureRecorder();
      fn(Canvas(rec), Size(w.toDouble(), h.toDouble()));
      final img = await rec.endRecording().toImage(w, h);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (data == null) throw Exception('could not draw the frame');
      await File(path).writeAsBytes(data.buffer.asUint8List(), flush: true);
      return path;
    }

    var next = n;
    int? maskIdx, ringIdx;
    if (style.active && style.transparent) {
      final path = await draw((c, s) => FramePainter.paintMask(c, s, style), '${dir.path}/mask_$stamp.png');
      args.addAll(['-loop', '1', '-framerate', '$fps', '-t', dStr, '-i', path]);
      maskIdx = next++;
    }
    if (style.active && (!style.transparent || style.hasBorder)) {
      if (animate && style.animated) {
        final k = math.min(fps * 2, 40); // one loop = 2 seconds
        for (var i = 0; i < k; i++) {
          await draw((c, s) => FramePainter(style, phase: i / k).paint(c, s),
              '${dir.path}/ring_${stamp}_${i.toString().padLeft(3, '0')}.png');
        }
        args.addAll([
          '-stream_loop', '-1', '-framerate', '${k ~/ 2}', '-t', dStr,
          '-i', '${dir.path}/ring_${stamp}_%03d.png',
        ]);
      } else {
        final path = await draw((c, s) => FramePainter(style).paint(c, s), '${dir.path}/ring_$stamp.png');
        args.addAll(['-loop', '1', '-framerate', '$fps', '-t', dStr, '-i', path]);
      }
      ringIdx = next++;
    }

    // Effect frames for the transitions (fire, lightning, ...), drawn over the junction.
    final fxIn = <(int, double, double)>[]; // input index, start, end
    if (xfade && trFx && n > 1) {
      var len = _clips[0].span;
      for (var k = 0; k < n - 1; k++) {
        final t = _junction(k);
        final fx = _transitions[_clips[k + 1].trans].$3;
        if (fx != TransFx.none && t > 0.2) {
          final count = math.max(2, (t * fps).ceil());
          for (var i = 0; i < count; i++) {
            await draw((c, s) => paintTransFx(c, s, fx, i / (count - 1)),
                '${dir.path}/tf${k}_${stamp}_${i.toString().padLeft(3, '0')}.png');
          }
          args.addAll(['-framerate', '$fps', '-i', '${dir.path}/tf${k}_${stamp}_%03d.png']);
          fxIn.add((next++, len - t, len));
        }
        len = len + _clips[k + 1].span - _junction(k);
      }
    }

    final parts = <String>[for (var i = 0; i < n; i++) '[$i:v]$vf,setpts=PTS-STARTPTS[v$i]'];
    var last = '[v0]';
    if (n > 1) {
      if (xfade) {
        var acc = '[v0]';
        var len = _clips[0].span;
        for (var k = 0; k < n - 1; k++) {
          final t = _junction(k);
          final name = _transitions[_clips[k + 1].trans].$2;
          final label = k == n - 2 ? '[c]' : '[x$k]';
          parts.add('$acc[v${k + 1}]xfade=transition=$name:duration=${t.toStringAsFixed(3)}'
              ':offset=${(len - t).toStringAsFixed(3)}$label');
          acc = label;
          len = len + _clips[k + 1].span - t;
        }
      } else {
        final ins = [for (var i = 0; i < n; i++) '[v$i]'].join();
        parts.add('${ins}concat=n=$n:v=1:a=0[c]');
      }
      last = '[c]';
    }
    for (var j = 0; j < fxIn.length; j++) {
      final f = fxIn[j];
      parts.add('[${f.$1}:v]format=rgba,setpts=PTS+${f.$2.toStringAsFixed(3)}/TB[tf$j]');
      parts.add("${last}[tf$j]overlay=0:0:eof_action=pass:format=auto:enable='between(t,${f.$2.toStringAsFixed(3)},${f.$3.toStringAsFixed(3)})'[fx$j]");
      last = '[fx$j]';
    }
    if (maskIdx != null) {
      parts.add('${last}format=yuva420p[vm]');
      parts.add('[$maskIdx:v]format=gray[mk]');
      parts.add('[vm][mk]alphamerge[va]');
      last = '[va]';
    }
    if (ringIdx != null) {
      parts.add('[$ringIdx:v]format=rgba[fr]');
      parts.add('$last[fr]overlay=0:0:shortest=1:format=auto[ov]');
      last = '[ov]';
    }
    final alpha = maskIdx != null;
    parts.add('${last}split[a][b]');
    parts.add('[a]palettegen=max_colors=${alpha ? 255 : 256}:stats_mode=diff${alpha ? ':reserve_transparent=1' : ''}[p]');
    parts.add('[b][p]paletteuse=dither=sierra2_4a${alpha ? ':alpha_threshold=128' : ':diff_mode=rectangle'}[o]');

    final out = '${dir.path}/make_$stamp.gif';
    args.addAll(['-filter_complex', parts.join(';'), '-map', '[o]', '-loop', '0', out]);
    final session = await FFmpegKit.executeWithArguments(args);
    final code = await session.getReturnCode();
    final f = File(out);
    if (ReturnCode.isSuccess(code) && await f.exists() && await f.length() > 0) return out;
    return null;
  }

  Future<void> _make() async {
    if (_busy || _clips.isEmpty) return;
    setState(() => _busy = true);
    _ctrl?.pause();
    final nav = Navigator.of(context);
    String? error;
    String? note;
    try {
      // Try the full result first, then simpler versions if this phone's FFmpeg refuses.
      final attempts = <(bool, bool, bool, String?)>[(true, true, true, null)];
      final hasFx = _clips.skip(1).any((c) => _transitions[c.trans].$3 != TransFx.none);
      if (hasFx) attempts.add((true, true, false, 'The transition effects were skipped.'));
      if (_style.animated) attempts.add((false, true, false, 'The border animation was skipped.'));
      if (_clips.length > 1) attempts.add((false, false, false, 'Transitions and animation were skipped.'));
      String? out;
      for (final at in attempts) {
        out = await _render(animate: at.$1, xfade: at.$2, trFx: at.$3);
        if (out != null) {
          note = at.$4;
          break;
        }
      }
      if (out != null) {
        await studio.addWork(
          kind: SavedTheme.gif,
          file: out,
          name: 'GIF',
          length: Duration(milliseconds: (_totalSeconds * 1000).round()),
          proj: _projectJson(),
        );
        final old = widget.replaceId;
        if (old != null) await studio.removeSaved(old);
      } else {
        error = 'Could not make the GIF. Try shorter clips or a lower quality.';
      }
    } catch (e) {
      error = 'Something went wrong: $e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      _toast(error);
      _ctrl?.play();
      _next?.pause();
      _startPlayback();
      return;
    }
    _toast(note == null ? 'GIF saved in My Work' : 'GIF saved. $note');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    studio.setTab(2);
    nav.popUntil((r) => r.isFirst);
  }

  // ---- UI

  @override
  Widget build(BuildContext context) {
    final cur = _cur;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppNav(
              title: 'Make GIF',
              back: 'Back',
              trailing: NavAction('Make', filled: true, onTap: _make),
            ),
            Expanded(
              child: _clips.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Add a video to start', style: AppText.small),
                          const SizedBox(height: 12),
                          OutlinedButton(onPressed: _addClip, child: const Text('Pick video')),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      children: [
                        _preview(),
                        const SizedBox(height: 12),
                        _clipRow(),
                        if (_clips.length > 1) ...[
                          const SizedBox(height: 8),
                          Seg(
                            labels: const ['Play all clips', 'Only this clip'],
                            index: _playAll ? 0 : 1,
                            onChanged: (i) {
                              setState(() => _playAll = i == 0);
                              _startPlayback();
                            },
                          ),
                          Row(
                            children: [
                              Text('Transition length', style: AppText.small),
                              Expanded(
                                child: Slider(
                                  value: _transDur,
                                  min: 0.2,
                                  max: 1.2,
                                  onChanged: (v) => setState(() => _transDur = v),
                                ),
                              ),
                              Text('${_transDur.toStringAsFixed(1)}s', style: AppText.small),
                            ],
                          ),
                        ],
                        if (cur != null) ...[
                          const SizedBox(height: 16),
                          _trim(cur),
                        ],
                        const SizedBox(height: 18),
                        const Text('Crop', style: AppText.h2),
                        const SizedBox(height: 8),
                        Seg(
                          labels: [for (final s in _shapes) s.$1],
                          index: _shape,
                          onChanged: (i) => setState(() {
                            _shape = i;
                            _panX = 0;
                            _panY = 0;
                          }),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text('Zoom', style: AppText.small),
                            Expanded(
                              child: Slider(
                                value: _zoom,
                                min: 1,
                                max: 3,
                                onChanged: (v) => setState(() => _zoom = v),
                              ),
                            ),
                            Text('${_zoom.toStringAsFixed(1)}x', style: AppText.small),
                          ],
                        ),
                        Text('Drag the picture above to move it inside the frame.',
                            style: AppText.small),
                        const SizedBox(height: 18),
                        const SizedBox(height: 4),
                        _frameSection(),
                        const SizedBox(height: 18),
                        const Text('Quality', style: AppText.h2),
                        const SizedBox(height: 8),
                        Seg(
                          labels: [for (final q in kGifPresets) '${q.width}'],
                          index: _quality,
                          onChanged: (i) => setState(() => _quality = i),
                        ),
                        const SizedBox(height: 6),
                        Text(kGifPresets[_quality].hint, style: AppText.small),
                        const SizedBox(height: 14),
                        Text(
                          '${_clips.length} clip${_clips.length == 1 ? '' : 's'} · '
                          '${_totalSeconds.toStringAsFixed(1)} s'
                          '${_totalSeconds > 15 ? ' · long GIFs make big files' : ''}',
                          style: AppText.small,
                        ),
                        if (_busy) ...[
                          const SizedBox(height: 16),
                          const LinearProgressIndicator(),
                          const SizedBox(height: 6),
                          Text('Making your GIF…', style: AppText.small),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot({required bool on, required Widget child, required VoidCallback onTap, VoidCallback? onLong}) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLong,
      child: Container(
        width: 34,
        height: 34,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: on ? AppColors.pri : AppColors.line, width: on ? 3 : 1),
        ),
        child: ClipOval(child: child),
      ),
    );
  }

  Widget _frameSection() {
    final active = _fshape != FrameShape.none;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Frame', style: AppText.h2),
        const SizedBox(height: 4),
        Text('The video plays inside the shape you choose.', style: AppText.small),
        const SizedBox(height: 8),
        Seg(
          labels: kFrameShapeLabels,
          index: _fshape.index,
          onChanged: (i) => setState(() {
            _fshape = FrameShape.values[i];
            // Shapes look right on a square canvas.
            if (_fshape != FrameShape.none && _shape == 0) _shape = 1;
          }),
        ),
        if (active) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Frame size', style: AppText.small),
              Expanded(
                child: Slider(
                  value: (0.32 - _pad).clamp(0.02, 0.30).toDouble(),
                  min: 0.02,
                  max: 0.30,
                  onChanged: (v) => setState(() => _pad = 0.32 - v),
                ),
              ),
            ],
          ),
          Text('Border animation', style: AppText.small),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (var i = 0; i < kFrameAnimLabels.length; i++)
                ChoiceChip(
                  label: Text(kFrameAnimLabels[i]),
                  selected: _anim.index == i,
                  onSelected: (_) => setState(() => _anim = FrameAnim.values[i]),
                ),
            ],
          ),
          if (_anim.index >= FrameAnim.fire.index)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Fire, Thunder and Sparkle use their own colours.', style: AppText.small),
            ),
          const SizedBox(height: 10),
          Text('Border colour', style: AppText.small),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < kFrameBorders.length; i++)
                _dot(
                  on: _border == i,
                  onTap: () => setState(() => _border = i),
                  child: kFrameBorders[i].color == null
                      ? const ColoredBox(
                          color: Colors.white,
                          child: Icon(Icons.block, size: 18, color: Colors.black38))
                      : DecoratedBox(
                          decoration: kFrameBorders[i].gold
                              ? const BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                  Color(0xFFF9E27D),
                                  Color(0xFFB8860B),
                                  Color(0xFFF9E27D),
                                ]))
                              : BoxDecoration(color: kFrameBorders[i].color),
                        ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Around the frame (first circle: nothing, video only in the shape)', style: AppText.small),
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _dot(
                    on: _artPath == null && _bg < 0,
                    onTap: () async {
                      _bg = -1;
                      await _setArt(null);
                    },
                    child: const ColoredBox(
                      color: Colors.white,
                      child: Icon(Icons.format_color_reset_outlined, size: 18, color: Colors.black54),
                    ),
                  ),
                ),
                for (var i = 0; i < kFrameBgs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _dot(
                      on: _artPath == null && _bg == i,
                      onTap: () async {
                        _bg = i;
                        await _setArt(null);
                      },
                      child: ColoredBox(color: kFrameBgs[i]),
                    ),
                  ),
                for (final f in _arts)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _dot(
                      on: _artPath == f.path,
                      onTap: () => _setArt(f.path),
                      onLong: () async {
                        await GifArt.remove(f.path);
                        if (_artPath == f.path) await _setArt(null);
                        await _loadArts();
                        if (mounted) _toast('Picture removed from GIF studio');
                      },
                      child: Image.file(f, fit: BoxFit.cover, cacheWidth: 100),
                    ),
                  ),
                GestureDetector(
                  onTap: _addArt,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.line),
                    ),
                    child: const Icon(Icons.add_rounded, color: AppColors.pri, size: 20),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text('Pictures you add stay here. Press and hold one to remove it.', style: AppText.small),
        ],
      ],
    );
  }

  Widget _videoView(VideoPlayerController c) {
    final size = c.value.size;
    return Transform.scale(
      scale: _zoom,
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment(_panX, _panY),
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(c)),
      ),
    );
  }

  /// The current clip, and during a transition the next one blended in like the exported GIF.
  Widget _stage(VideoPlayerController c, Size box) {
    final cur = _videoView(c);
    final nx = _next;
    if (!_inTrans || nx == null || !nx.value.isInitialized || _nextIdx < 0) return cur;
    final p = _tp;
    final name = _transitions[_clips[_nextIdx].trans].$2;
    final incoming = _videoView(nx);
    Widget fade(double o, [Widget? under]) => Stack(
          fit: StackFit.expand,
          children: [under ?? cur, Opacity(opacity: o.clamp(0.0, 1.0).toDouble(), child: incoming)],
        );
    switch (name) {
      case 'slideleft':
        return Stack(fit: StackFit.expand, children: [
          Transform.translate(offset: Offset(-box.width * p, 0), child: cur),
          Transform.translate(offset: Offset(box.width * (1 - p), 0), child: incoming),
        ]);
      case 'wipeleft':
        return Stack(fit: StackFit.expand, children: [
          cur,
          ClipRect(clipper: _RectClipper(Rect.fromLTWH(box.width * (1 - p), 0, box.width * p, box.height)), child: incoming),
        ]);
      case 'wipeup':
        return Stack(fit: StackFit.expand, children: [
          cur,
          ClipRect(clipper: _RectClipper(Rect.fromLTWH(0, box.height * (1 - p), box.width, box.height * p)), child: incoming),
        ]);
      case 'circleopen':
        return Stack(fit: StackFit.expand, children: [cur, ClipPath(clipper: _CircleClipper(p), child: incoming)]);
      case 'radial':
        return Stack(fit: StackFit.expand, children: [cur, ClipPath(clipper: _SweepClipper(p), child: incoming)]);
      case 'zoomin':
        return fade(p, Transform.scale(scale: 1 + p * 0.5, child: cur));
      case 'fadeblack':
        return Stack(fit: StackFit.expand, children: [
          p < 0.5 ? cur : incoming,
          Container(color: Colors.black.withValues(alpha: (1 - (p - 0.5).abs() * 2).clamp(0.0, 1.0).toDouble())),
        ]);
      case 'fadewhite':
        return Stack(fit: StackFit.expand, children: [
          p < 0.5 ? cur : incoming,
          Container(color: Colors.white.withValues(alpha: (1 - (p - 0.5).abs() * 2).clamp(0.0, 1.0).toDouble())),
        ]);
      default: // fade, dissolve, pixelize (the last two are approximated as a fade here)
        return fade(p);
    }
  }

  /// With a transparent surround only the shape shows the video.
  Widget _clipped(Widget video) {
    if (_style.active && _style.transparent) {
      return ClipPath(clipper: FrameClipper(_fshape, _pad), child: video);
    }
    return video;
  }

  Widget _preview() {
    final c = _ctrl;
    final ar = _aspect();
    return SizedBox(
      height: 340,
      child: Center(
        child: AspectRatio(
          aspectRatio: ar,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.hardEdge,
            child: (c == null || !c.value.isInitialized)
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : LayoutBuilder(
                    builder: (context, box) {
                      final size = c.value.size;
                      return GestureDetector(
                        onPanUpdate: (d) => setState(() {
                          _panX = (_panX - d.delta.dx / (box.maxWidth / 2)).clamp(-1.0, 1.0).toDouble();
                          _panY = (_panY - d.delta.dy / (box.maxHeight / 2)).clamp(-1.0, 1.0).toDouble();
                        }),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_style.active && _style.transparent)
                              const CustomPaint(size: Size.infinite, painter: _CheckerPainter()),
                            _clipped(_stage(c, box.biggest)),
                            if (_inTrans && _next != null && _next!.value.isInitialized)
                              IgnorePointer(
                                child: ClipPath(
                                  clipper: _style.active && _style.transparent
                                      ? FrameClipper(_fshape, _pad)
                                      : null,
                                  child: CustomPaint(
                                    size: Size.infinite,
                                    painter: TransFxPainter(_transitions[_clips[_nextIdx].trans].$3, _tp),
                                  ),
                                ),
                              ),
                            if (_style.needsOverlay)
                              IgnorePointer(
                                child: CustomPaint(
                                  size: Size.infinite,
                                  painter: FramePainter(_style, clock: _style.animated ? _clock : null),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _thumb(int i) {
    return GestureDetector(
      onTap: () => _select(i),
      child: Stack(
        children: [
          Container(
            width: 48,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: i == _sel ? AppColors.pri : AppColors.line, width: i == _sel ? 2.5 : 1),
              color: const Color(0xFF1E1B2E),
            ),
            clipBehavior: Clip.hardEdge,
            child: _clips[i].strip[0] == null
                ? const Icon(Icons.videocam_rounded, color: Colors.white54, size: 18)
                : Image.memory(_clips[i].strip[0]!, fit: BoxFit.cover, gaplessPlayback: true),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: () => _remove(i),
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            left: 3,
            bottom: 2,
            child: Text('${i + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// The small button between clip [k] and clip [k + 1]: picks the transition.
  Widget _junctionButton(int k) {
    final label = _transitions[_clips[k + 1].trans].$1;
    return GestureDetector(
      onTap: () => _pickTransition(k + 1),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 46,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: _clips[k + 1].trans == 0 ? Colors.white : AppColors.pri,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.pri),
              ),
              child: Icon(Icons.auto_awesome,
                  size: 14, color: _clips[k + 1].trans == 0 ? AppColors.pri : Colors.white),
            ),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTransition(int clipIndex) async {
    final res = await showModalBottomSheet<(int, bool)>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Transition', style: AppText.h2),
              const SizedBox(height: 4),
              Text('How clip $clipIndex changes into clip ${clipIndex + 1}. Fire, Lightning, Sparkle, Hearts and Confetti add an effect. It shows in the preview and the GIF.',
                  style: AppText.small),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _transitions.length; i++)
                    ChoiceChip(
                      label: Text(_transitions[i].$1),
                      selected: _clips[clipIndex].trans == i,
                      onSelected: (_) => Navigator.pop(c, (i, false)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Tap a name to use it here, or use the button below for all clips.',
                  style: AppText.small),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.pop(c, (_clips[clipIndex].trans, true)),
                  child: const Text('Use this one between all clips'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (res == null) return;
    setState(() {
      if (res.$2) {
        for (var i = 1; i < _clips.length; i++) {
          _clips[i].trans = res.$1;
        }
      } else {
        _clips[clipIndex].trans = res.$1;
      }
    });
  }

  Widget _clipRow() {
    return SizedBox(
      height: 70,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < _clips.length; i++) ...[
            _thumb(i),
            if (i < _clips.length - 1)
              _junctionButton(i)
            else
              const SizedBox(width: 8),
          ],
          GestureDetector(
            onTap: _addClip,
            child: Container(
              width: 48,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.line),
                color: Colors.white,
              ),
              child: const Icon(Icons.add_rounded, color: AppColors.pri),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trim(_Clip clip) {
    String t(double v) => '${v.toStringAsFixed(1)}s';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Frames to use', style: AppText.h2),
            const Spacer(),
            Text('${t(clip.start)} → ${t(clip.end)}  (${t(clip.span)})',
                style: AppText.mono.copyWith(fontSize: 11, color: AppColors.ink)),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                for (final b in clip.strip)
                  Expanded(
                    child: b == null
                        ? const ColoredBox(color: Color(0xFFCFCBDD), child: SizedBox.expand())
                        : SizedBox.expand(child: Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true)),
                  ),
              ],
            ),
          ),
        ),
        RangeSlider(
          values: RangeValues(clip.start.clamp(0.0, clip.length).toDouble(),
              clip.end.clamp(0.0, clip.length).toDouble()),
          min: 0,
          max: clip.length <= 0 ? 1 : clip.length,
          onChanged: _setRange,
        ),
      ],
    );
  }
}

/// Grey/white squares shown behind a transparent GIF in the preview.
class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 12.0;
    final a = Paint()..color = const Color(0xFFFFFFFF);
    final b = Paint()..color = const Color(0xFFD9D9E3);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), (x + y).isEven ? a : b);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => false;
}
