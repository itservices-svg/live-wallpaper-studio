import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../data/scenes.dart';
import '../services/library_store.dart';
import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'pick_media_screen.dart';
import 'preview_screen.dart' show kGifPresets;

/// One video in the GIF, with the part of it that is used.
class _Clip {
  _Clip(this.path, this.name, this.length, this.size) {
    end = math.min(length, 4.0);
  }

  final String path;
  final String name;
  final double length; // seconds
  final Size size;
  double start = 0;
  late double end;
  List<Uint8List?> strip = List<Uint8List?>.filled(8, null);

  double get span => end - start;
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
  const GifEditorScreen({super.key});

  @override
  State<GifEditorScreen> createState() => _GifEditorScreenState();
}

class _GifEditorScreenState extends State<GifEditorScreen> {
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

  @override
  void initState() {
    super.initState();
    // Ask for the first video straight away.
    WidgetsBinding.instance.addPostFrameCallback((_) => _addClip(first: true));
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_loopCheck);
    _ctrl?.dispose();
    super.dispose();
  }

  _Clip? get _cur => (_sel >= 0 && _sel < _clips.length) ? _clips[_sel] : null;

  double get _totalSeconds => _clips.fold<double>(0, (a, c) => a + c.span);

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

  Future<void> _addClip({bool first = false}) async {
    if (_adding || _busy) return;
    _adding = true;
    try {
      studio.openPicker(video: true);
      final MediaItem? item = await Navigator.of(context)
          .push<MediaItem>(MaterialPageRoute(builder: (_) => const PickMediaScreen(forGif: true)));
      if (item == null) {
        if (first && _clips.isEmpty && mounted) Navigator.of(context).pop();
        return;
      }
      String? path;
      if (item.asset != null) {
        final f = await item.asset!.file;
        path = f?.path;
      } else {
        path = item.file;
      }
      if (path == null) {
        _toast('This clip is not available. Pick a video from your gallery.');
        return;
      }
      final c = VideoPlayerController.file(File(path));
      await c.initialize();
      final len = c.value.duration.inMilliseconds / 1000.0;
      final clip = _Clip(path, item.name, len, c.value.size);
      await c.setVolume(0);
      if (!mounted) {
        await c.dispose();
        return;
      }
      _ctrl?.removeListener(_loopCheck);
      await _ctrl?.dispose();
      _ctrl = c;
      _clips.add(clip);
      _sel = _clips.length - 1;
      _startPlayback();
      setState(() {});
      unawaited(_loadStrip(clip));
    } catch (e) {
      if (mounted) _toast('Could not open that video: $e');
    } finally {
      _adding = false;
    }
  }

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
    _ctrl?.removeListener(_loopCheck);
    await _ctrl?.dispose();
    _ctrl = c;
    _sel = i;
    _startPlayback();
    setState(() {});
    if (clip.strip.every((e) => e == null)) unawaited(_loadStrip(clip));
  }

  void _startPlayback() {
    final c = _ctrl, clip = _cur;
    if (c == null || clip == null) return;
    c.addListener(_loopCheck);
    c.seekTo(Duration(milliseconds: (clip.start * 1000).round()));
    c.play();
  }

  void _loopCheck() {
    final c = _ctrl, clip = _cur;
    if (c == null || clip == null || !c.value.isInitialized) return;
    final pos = c.value.position.inMilliseconds / 1000.0;
    if (pos >= clip.end - 0.02 || pos < clip.start - 0.3) {
      c.seekTo(Duration(milliseconds: (clip.start * 1000).round()));
      if (!c.value.isPlaying) c.play();
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
      _ctrl?.removeListener(_loopCheck);
      await _ctrl?.dispose();
      _ctrl = null;
      _sel = -1;
      if (mounted) setState(() {});
      return;
    }
    if (wasSel) {
      _sel = -1;
      await _select(math.min(i, _clips.length - 1));
    } else {
      if (i < _sel) _sel--;
      if (mounted) setState(() {});
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
    final c = _ctrl;
    if (c != null) {
      final pos = c.value.position.inMilliseconds / 1000.0;
      if (pos < clip.start || pos > clip.end) {
        c.seekTo(Duration(milliseconds: (clip.start * 1000).round()));
      }
    }
    setState(() {});
  }

  // ---- export

  Future<void> _make() async {
    if (_busy || _clips.isEmpty) return;
    setState(() => _busy = true);
    _ctrl?.pause();
    final nav = Navigator.of(context);
    String? error;
    try {
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
      final ax = ((_panX + 1) / 2).toStringAsFixed(3);
      final ay = ((_panY + 1) / 2).toStringAsFixed(3);
      var cw = (w / _zoom).floor();
      var ch = (h / _zoom).floor();
      cw -= cw % 2;
      ch -= ch % 2;
      final vf = 'fps=${q.fps},scale=$w:$h:force_original_aspect_ratio=increase,'
          'crop=$w:$h:(iw-$w)*$ax:(ih-$h)*$ay'
          '${_zoom > 1.001 ? ',crop=$cw:$ch,scale=$w:$h' : ''},setsar=1';

      final n = _clips.length;
      final args = <String>['-y'];
      for (final c in _clips) {
        args.addAll([
          '-ss', c.start.toStringAsFixed(3),
          '-t', c.span.toStringAsFixed(3),
          '-i', c.path,
        ]);
      }
      final head = [for (var i = 0; i < n; i++) '[$i:v]$vf[v$i]'].join(';');
      final ins = [for (var i = 0; i < n; i++) '[v$i]'].join();
      final join = n == 1 ? '[v0]split[a][b]' : '${ins}concat=n=$n:v=1:a=0[c];[c]split[a][b]';
      final fc = '$head;$join;[a]palettegen=max_colors=256:stats_mode=diff[p];'
          '[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle[o]';

      final base = await getTemporaryDirectory();
      final dir = await Directory('${base.path}/gif').create(recursive: true);
      final out = '${dir.path}/make_${DateTime.now().millisecondsSinceEpoch}.gif';
      args.addAll(['-filter_complex', fc, '-map', '[o]', '-loop', '0', out]);

      final session = await FFmpegKit.executeWithArguments(args);
      final code = await session.getReturnCode();
      final f = File(out);
      if (ReturnCode.isSuccess(code) && await f.exists() && await f.length() > 0) {
        await studio.addWork(
          kind: SavedTheme.gif,
          file: out,
          name: 'GIF',
          length: Duration(milliseconds: (_totalSeconds * 1000).round()),
        );
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
      return;
    }
    _toast('GIF saved in My Work');
    await Future<void>.delayed(const Duration(milliseconds: 600));
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
                        child: Transform.scale(
                          scale: _zoom,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            alignment: Alignment(_panX, _panY),
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: size.width,
                              height: size.height,
                              child: VideoPlayer(c),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _clipRow() {
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < _clips.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _select(i),
                child: Stack(
                  children: [
                    Container(
                      width: 48,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: i == _sel ? AppColors.pri : AppColors.line,
                            width: i == _sel ? 2.5 : 1),
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
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
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
