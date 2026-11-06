import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/scenes.dart';
import '../services/depth_service.dart';
import '../services/photo3d.dart';
import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'explore_screen.dart';
import 'pick_media_screen.dart';

class _MaskPainter extends CustomPainter {
  _MaskPainter(this.photo, this.overlay);

  final ui.Image photo;
  final ui.Image? overlay;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    canvas.drawImageRect(photo, Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()), dst,
        Paint()..filterQuality = FilterQuality.medium);
    final o = overlay;
    if (o != null) {
      canvas.drawImageRect(o, Rect.fromLTWH(0, 0, o.width.toDouble(), o.height.toDouble()), dst,
          Paint()..filterQuality = FilterQuality.low);
    }
  }

  @override
  bool shouldRepaint(_MaskPainter old) => old.photo != photo || old.overlay != overlay;
}

/// Pick a photo, mark what is in front (a tree, a person ...), and get depth layers from it.
class Photo3dScreen extends StatefulWidget {
  const Photo3dScreen({super.key, this.holePath, this.startPath});

  /// Opens straight on this picture (e.g. an AI image) instead of asking to pick one.
  final String? startPath;

  /// Set to make a see-through hole in this picture instead of cutting depth layers.
  final String? holePath;

  @override
  State<Photo3dScreen> createState() => _Photo3dScreenState();
}

class _Photo3dScreenState extends State<Photo3dScreen> {
  String? _path;
  ui.Image? _view;
  ui.Image? _overlay;
  Uint8List _cls = Uint8List(0);
  Uint8List _rgba = Uint8List(0);
  int _mw = 0, _mh = 0;
  int _tool = 0; // 0 tap-select, 1 brush, 2 eraser
  int _level = 2; // 2 near, 1 middle
  double _tol = 28;
  double _brush = 10;
  final List<Uint8List> _undo = [];
  bool _busy = false;
  bool _ovBusy = false, _ovPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = widget.holePath ?? widget.startPath;
      if (h != null) {
        _load(h);
      } else {
        _pick();
      }
    });
  }

  @override
  void dispose() {
    _view?.dispose();
    _overlay?.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<void> _pick() async {
    final src = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text('Pick a photo', style: AppText.h2),
              ),
              ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('From gallery'),
                  onTap: () => Navigator.pop(c, 'gallery')),
              ListTile(
                  leading: const Icon(Icons.explore_outlined),
                  title: const Text('From Explore (free photos)'),
                  onTap: () => Navigator.pop(c, 'explore')),
            ],
          ),
        ),
      ),
    );
    if (src == null || !mounted) {
      if (mounted && _path == null) Navigator.of(context).pop();
      return;
    }
    MediaItem? item;
    if (src == 'gallery') {
      studio.openPicker(video: false);
      item = await Navigator.of(context).push<MediaItem>(
          MaterialPageRoute(builder: (_) => const PickMediaScreen(forGif: true, photos: true)));
    } else {
      item = await Navigator.of(context).push<MediaItem>(MaterialPageRoute(
          builder: (_) => const ExploreScreen(allowed: [0], title: 'Pick a photo')));
    }
    if (item == null || !mounted) {
      if (mounted && _path == null) Navigator.of(context).pop();
      return;
    }
    final path = item.asset != null ? (await item.asset!.file)?.path : item.file;
    if (path == null) {
      _toast('This photo is not available.');
      if (mounted && _path == null) Navigator.of(context).pop();
      return;
    }
    await _load(path);
  }

  Future<void> _load(String path) async {
    try {
      final codec = await ui.instantiateImageCodec(await File(path).readAsBytes(), targetWidth: 1000);
      final img = (await codec.getNextFrame()).image;
      final s = 512 / math.max(img.width, img.height);
      final mw = math.max(8, (img.width * s).round()), mh = math.max(8, (img.height * s).round());
      final rec = ui.PictureRecorder();
      Canvas(rec).drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromLTWH(0, 0, mw.toDouble(), mh.toDouble()), Paint()..filterQuality = FilterQuality.medium);
      final small = await rec.endRecording().toImage(mw, mh);
      final px = (await small.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      small.dispose();
      _view?.dispose();
      _overlay?.dispose();
      if (!mounted) return;
      setState(() {
        _path = path;
        _view = img;
        _overlay = null;
        _mw = mw;
        _mh = mh;
        _rgba = px;
        _cls = Uint8List(mw * mh);
        _undo.clear();
      });
    } catch (e) {
      _toast('Could not open the photo: $e');
      if (mounted && _path == null) Navigator.of(context).pop();
    }
  }

  void _snap() {
    _undo.add(Uint8List.fromList(_cls));
    if (_undo.length > 15) _undo.removeAt(0);
  }

  Future<void> _refreshOverlay() async {
    if (_ovBusy) {
      _ovPending = true;
      return;
    }
    _ovBusy = true;
    try {
      do {
        _ovPending = false;
        final px = Uint8List(_mw * _mh * 4);
        for (var i = 0; i < _cls.length; i++) {
          final c = _cls[i];
          if (c == 2) {
            px[i * 4] = 255;
            px[i * 4 + 1] = 60;
            px[i * 4 + 2] = 60;
            px[i * 4 + 3] = 120;
          } else if (c == 1) {
            px[i * 4] = 40;
            px[i * 4 + 1] = 130;
            px[i * 4 + 2] = 255;
            px[i * 4 + 3] = 110;
          }
        }
        final img = await Photo3d.fromRgba(px, _mw, _mh);
        if (!mounted) {
          img.dispose();
          return;
        }
        final old = _overlay;
        setState(() => _overlay = img);
        WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
      } while (_ovPending);
    } finally {
      _ovBusy = false;
    }
  }

  Offset _toMask(Offset p, Size box) =>
      Offset((p.dx / box.width * _mw).clamp(0, _mw - 1.0).toDouble(), (p.dy / box.height * _mh).clamp(0, _mh - 1.0).toDouble());

  void _stamp(Offset m) {
    final v = _tool == 2 ? 0 : _level;
    final r = _brush;
    final x0 = math.max(0, (m.dx - r).floor()), x1 = math.min(_mw - 1, (m.dx + r).ceil());
    final y0 = math.max(0, (m.dy - r).floor()), y1 = math.min(_mh - 1, (m.dy + r).ceil());
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = x - m.dx, dy = y - m.dy;
        if (dx * dx + dy * dy <= r * r) _cls[y * _mw + x] = v;
      }
    }
  }

  Offset? _last;

  void _stroke(Offset m) {
    final a = _last ?? m;
    final dist = (m - a).distance;
    final steps = math.max(1, (dist / math.max(1.0, _brush / 3)).ceil());
    for (var i = 1; i <= steps; i++) {
      _stamp(Offset.lerp(a, m, i / steps)!);
    }
    _last = m;
    _refreshOverlay();
  }

  void _wand(Offset m) {
    final sx = m.dx.round().clamp(0, _mw - 1).toInt(), sy = m.dy.round().clamp(0, _mh - 1).toInt();
    var r0 = 0, g0 = 0, b0 = 0, n = 0;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final x = sx + dx, y = sy + dy;
        if (x < 0 || y < 0 || x >= _mw || y >= _mh) continue;
        final i = (y * _mw + x) * 4;
        r0 += _rgba[i];
        g0 += _rgba[i + 1];
        b0 += _rgba[i + 2];
        n++;
      }
    }
    r0 ~/= n;
    g0 ~/= n;
    b0 ~/= n;
    final thr = 6 + _tol * 1.6;
    final seen = Uint8List(_mw * _mh);
    final stack = <int>[sy * _mw + sx];
    seen[sy * _mw + sx] = 1;
    final v = _tool == 2 ? 0 : _level;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final p = i * 4;
      final d = ((_rgba[p] - r0).abs() + (_rgba[p + 1] - g0).abs() + (_rgba[p + 2] - b0).abs()) / 3;
      if (d > thr) continue;
      _cls[i] = v;
      final x = i % _mw, y = i ~/ _mw;
      if (x > 0 && seen[i - 1] == 0) {
        seen[i - 1] = 1;
        stack.add(i - 1);
      }
      if (x < _mw - 1 && seen[i + 1] == 0) {
        seen[i + 1] = 1;
        stack.add(i + 1);
      }
      if (y > 0 && seen[i - _mw] == 0) {
        seen[i - _mw] = 1;
        stack.add(i - _mw);
      }
      if (y < _mh - 1 && seen[i + _mw] == 0) {
        seen[i + _mw] = 1;
        stack.add(i + _mw);
      }
    }
    _refreshOverlay();
  }

  Future<void> _make() async {
    if (_busy || _path == null) return;
    setState(() => _busy = true);
    try {
      if (widget.holePath != null) {
        final out = await Photo3d.cutHole(_path!, _cls, _mw, _mh);
        if (!mounted) return;
        if (out == null) {
          _toast('First mark the part that should become see-through.');
          setState(() => _busy = false);
          return;
        }
        Navigator.of(context).pop<String>(out);
        return;
      }
      final layers = await Photo3d.build(_path!, _cls, _mw, _mh);
      if (!mounted) return;
      if (layers == null) {
        _toast('First mark what should come forward (tap the tree).');
        setState(() => _busy = false);
        return;
      }
      Navigator.of(context).pop<List<DepthLayer>>(layers);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast('Could not make the 3D layers: $e');
      }
    }
  }

  Widget _toolChip(String label, IconData icon, int t) => ChoiceChip(
        avatar: Icon(icon, size: 16),
        label: Text(label),
        selected: _tool == t,
        onSelected: (_) => setState(() => _tool = t),
      );

  @override
  Widget build(BuildContext context) {
    final view = _view;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppNav(
              title: widget.holePath != null ? 'Make a hole' : '3D from a photo',
              back: 'Back',
              trailing: NavAction(widget.holePath != null ? 'Done' : 'Make 3D', filled: true, onTap: _make),
            ),
            Expanded(
              child: view == null
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      children: [
                        ListView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                          children: [
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 440),
                                child: AspectRatio(
                                  aspectRatio: view.width / view.height,
                                  child: LayoutBuilder(
                                    builder: (context, box) {
                                      final size = Size(box.maxWidth, box.maxHeight);
                                      return GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTapUp: (d) {
                                          if (_tool == 0) {
                                            _snap();
                                            _wand(_toMask(d.localPosition, size));
                                          }
                                        },
                                        onPanStart: (d) {
                                          if (_tool == 0) return;
                                          _snap();
                                          _last = null;
                                          _stroke(_toMask(d.localPosition, size));
                                        },
                                        onPanUpdate: (d) {
                                          if (_tool == 0) return;
                                          _stroke(_toMask(d.localPosition, size));
                                        },
                                        onPanEnd: (_) => _last = null,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: CustomPaint(size: size, painter: _MaskPainter(view, _overlay)),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              widget.holePath != null
                                  ? 'Mark the part that should become see-through (tap it, or paint over it). '
                                      'The picture behind will show through there.'
                                  : 'Mark what should be in front (for example the tree): tap it, or paint over it. '
                                      'The rest stays far behind. Tilting the phone then moves the marked part more.',
                              style: AppText.small,
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _toolChip('Tap select', Icons.touch_app_outlined, 0),
                                _toolChip('Brush', Icons.brush_outlined, 1),
                                _toolChip('Eraser', Icons.auto_fix_off_outlined, 2),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (widget.holePath == null)
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                ChoiceChip(
                                  label: const Text('Near (red)'),
                                  selected: _level == 2,
                                  onSelected: (_) => setState(() => _level = 2),
                                ),
                                ChoiceChip(
                                  label: const Text('Middle (blue)'),
                                  selected: _level == 1,
                                  onSelected: (_) => setState(() => _level = 1),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                SizedBox(width: 90, child: Text(_tool == 0 ? 'Select range' : 'Brush size', style: AppText.small)),
                                Expanded(
                                  child: Slider(
                                    value: _tool == 0 ? _tol : _brush,
                                    min: _tool == 0 ? 5 : 3,
                                    max: _tool == 0 ? 70 : 30,
                                    activeColor: AppColors.pri,
                                    onChanged: (v) => setState(() => _tool == 0 ? _tol = v : _brush = v),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _undo.isEmpty
                                      ? null
                                      : () {
                                          _cls = _undo.removeLast();
                                          _refreshOverlay();
                                          setState(() {});
                                        },
                                  icon: const Icon(Icons.undo_rounded, size: 18),
                                  label: const Text('Undo'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    _snap();
                                    _cls = Uint8List(_mw * _mh);
                                    _refreshOverlay();
                                  },
                                  icon: const Icon(Icons.layers_clear_outlined, size: 18),
                                  label: const Text('Clear'),
                                ),
                                const SizedBox(width: 8),
                                if (widget.holePath == null)
                                  OutlinedButton.icon(
                                    onPressed: _pick,
                                    icon: const Icon(Icons.photo_outlined, size: 18),
                                    label: const Text('Other photo'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        if (_busy)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black38,
                              alignment: Alignment.center,
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: Colors.white),
                                  SizedBox(height: 12),
                                  Text('Making layers...', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
