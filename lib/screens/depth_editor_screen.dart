import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../services/depth_service.dart';
import '../data/scenes.dart';
import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'explore_screen.dart';
import 'pick_media_screen.dart';

/// Tilt state shared by the preview painter (same maths as the native wallpaper service).
class _Rig {
  double tx = 0, ty = 0, t = 0;
}

class _DepthPainter extends CustomPainter {
  _DepthPainter(this.layers, this.images, this.rig, Listenable repaint) : super(repaint: repaint);

  final List<DepthLayer> layers;
  final List<ui.Image?> images;
  final _Rig rig;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    for (var i = 0; i < layers.length && i < images.length; i++) {
      final img = images[i];
      if (img == null) continue;
      final l = layers[i];
      final bw = img.width.toDouble(), bh = img.height.toDouble();
      final dx = rig.tx * l.d * 0.10 * w + math.sin(rig.t * 0.6 + i * 1.7) * l.f * w;
      final dy = rig.ty * l.d * 0.06 * h + math.cos(rig.t * 0.45 + i * 1.7) * l.f * w;
      double s, cx, cy;
      if (l.cover) {
        s = math.max(w / bw, h / bh) * (1 + 0.2 * l.d + 4 * l.f);
        cx = w / 2 + dx;
        cy = h / 2 + dy;
      } else {
        s = l.w * w / bw;
        cx = l.x * w + dx;
        cy = l.y * h + dy;
      }
      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(s);
      canvas.drawImage(img, Offset(-bw / 2, -bh / 2), Paint()..filterQuality = FilterQuality.medium);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_DepthPainter old) => true;
}

/// Build a wallpaper from picture layers that move when the phone is tilted.
class DepthEditorScreen extends StatefulWidget {
  const DepthEditorScreen({super.key});

  @override
  State<DepthEditorScreen> createState() => _DepthEditorScreenState();
}

class _DepthEditorScreenState extends State<DepthEditorScreen> with SingleTickerProviderStateMixin {
  DepthProject _p = DepthProject();
  final List<ui.Image?> _imgs = [];
  final _Rig _rig = _Rig();
  final ValueNotifier<int> _frame = ValueNotifier(0);
  late final Ticker _ticker;
  final Stopwatch _sw = Stopwatch()..start();
  StreamSubscription<AccelerometerEvent>? _sub;
  double _gx = 0, _gy = 0, _baseY = 7;
  bool _haveBase = false;
  bool _dragging = false;
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      _rig.t = _sw.elapsedMilliseconds / 1000.0;
      _rig.tx += (_gx - _rig.tx) * 0.12;
      _rig.ty += (_gy - _rig.ty) * 0.12;
      _frame.value++;
    })
      ..start();
    try {
      _sub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen((e) {
        if (_dragging) return;
        if (!_haveBase) {
          _baseY = e.y;
          _haveBase = true;
        }
        _baseY += (e.y - _baseY) * 0.006;
        final k = (_p.invert ? -1 : 1) * _p.sens;
        _gx = (-e.x / 4.5).clamp(-1.0, 1.0).toDouble() * k;
        _gy = ((_baseY - e.y) / 4.5).clamp(-1.0, 1.0).toDouble() * k;
      }, onError: (_) {});
    } catch (_) {}
    _init();
  }

  Future<void> _init() async {
    _p = await DepthService.load();
    if (_p.layers.isEmpty) {
      await _preset('moon');
    } else {
      await _reloadImages();
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    _frame.dispose();
    for (final i in _imgs) {
      i?.dispose();
    }
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<ui.Image?> _decode(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 900);
      final f = await codec.getNextFrame();
      return f.image;
    } catch (_) {
      return null;
    }
  }

  Future<void> _reloadImages() async {
    final old = List<ui.Image?>.of(_imgs);
    final fresh = <ui.Image?>[];
    for (final l in _p.layers) {
      fresh.add(await _decode(l.path));
    }
    _imgs
      ..clear()
      ..addAll(fresh);
    for (final i in old) {
      i?.dispose();
    }
    if (mounted) setState(() {});
  }

  Future<void> _persist() => DepthService.save(_p);

  // ---- presets and adding layers

  Future<void> _preset(String kind) async {
    setState(() => _busy = true);
    try {
      final st = await DepthArt.stars();
      final layers = <DepthLayer>[DepthLayer(path: st, name: 'Stars', d: 0.1, f: 0.004)];
      if (kind == 'moon') {
        layers.add(DepthLayer(
            path: await DepthArt.moon(), name: 'Moon', d: 0.3, cover: false, w: 1.3, x: 0.5, y: 0.4, f: 0.008));
        layers.add(DepthLayer(path: await DepthArt.window(), name: 'Window', d: 0.9));
      } else if (kind == 'earth') {
        layers.add(DepthLayer(
            path: await DepthArt.earth(), name: 'Earth', d: 0.4, cover: false, w: 1.5, x: 0.5, y: 0.62, f: 0.01));
      }
      _p.layers
        ..clear()
        ..addAll(layers);
      await _reloadImages();
      await _persist();
    } catch (e) {
      _toast('Could not make the scene: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _addBuiltIn(String kind) async {
    try {
      late DepthLayer l;
      switch (kind) {
        case 'stars':
          l = DepthLayer(path: await DepthArt.stars(), name: 'Stars', d: 0.1, f: 0.004);
        case 'moon':
          l = DepthLayer(
              path: await DepthArt.moon(), name: 'Moon', d: 0.3, cover: false, w: 1.3, x: 0.5, y: 0.4, f: 0.008);
        case 'earth':
          l = DepthLayer(
              path: await DepthArt.earth(), name: 'Earth', d: 0.4, cover: false, w: 1.5, x: 0.5, y: 0.62, f: 0.01);
        default:
          l = DepthLayer(path: await DepthArt.window(), name: 'Window', d: 0.9);
      }
      await _addLayer(l);
    } catch (e) {
      _toast('Could not add it: $e');
    }
  }

  Future<void> _addLayer(DepthLayer l) async {
    _p.layers.add(l);
    _imgs.add(await _decode(l.path));
    await _persist();
    if (mounted) setState(() {});
  }

  Future<String?> _itemPath(MediaItem item) async {
    if (item.asset != null) return (await item.asset!.file)?.path;
    return item.file;
  }

  Future<void> _addPicture() async {
    final src = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text('Add a layer', style: AppText.h2),
                ),
                ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Your photo'),
                    onTap: () => Navigator.pop(c, 'gallery')),
                ListTile(
                    leading: const Icon(Icons.explore_outlined),
                    title: const Text('From Explore (photos, vectors, frames)'),
                    onTap: () => Navigator.pop(c, 'explore')),
                const Divider(height: 8),
                ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: const Text('Stars'),
                    onTap: () => Navigator.pop(c, 'b:stars')),
                ListTile(
                    leading: const Icon(Icons.nightlight_round),
                    title: const Text('Moon'),
                    onTap: () => Navigator.pop(c, 'b:moon')),
                ListTile(
                    leading: const Icon(Icons.public),
                    title: const Text('Earth'),
                    onTap: () => Navigator.pop(c, 'b:earth')),
                ListTile(
                    leading: const Icon(Icons.window_outlined),
                    title: const Text('Window frame'),
                    onTap: () => Navigator.pop(c, 'b:window')),
              ],
            ),
          ),
        ),
      ),
    );
    if (src == null || !mounted) return;
    if (src.startsWith('b:')) {
      await _addBuiltIn(src.substring(2));
      return;
    }
    MediaItem? item;
    if (src == 'gallery') {
      studio.openPicker(video: false);
      item = await Navigator.of(context).push<MediaItem>(
          MaterialPageRoute(builder: (_) => const PickMediaScreen(forGif: true, photos: true)));
    } else {
      item = await Navigator.of(context).push<MediaItem>(MaterialPageRoute(
          builder: (_) => const ExploreScreen(allowed: [0, 2, 3, 4], title: 'Pick a picture')));
    }
    if (item == null) return;
    final path = await _itemPath(item);
    if (path == null) {
      _toast('This picture is not available.');
      return;
    }
    final stored = await DepthService.addFile(path);
    final first = _p.layers.isEmpty;
    await _addLayer(DepthLayer(
      path: stored,
      name: first ? 'Background' : 'Picture',
      d: first ? 0.25 : 0.5,
      cover: first,
      w: 0.9,
      y: 0.5,
    ));
  }

  Future<void> _removeAt(int i) async {
    _p.layers.removeAt(i);
    final img = _imgs.removeAt(i);
    img?.dispose();
    await _persist();
    if (mounted) setState(() {});
  }

  Future<void> _move(int i, int by) async {
    final j = i + by;
    if (j < 0 || j >= _p.layers.length) return;
    final l = _p.layers.removeAt(i);
    _p.layers.insert(j, l);
    final im = _imgs.removeAt(i);
    _imgs.insert(j, im);
    await _persist();
    if (mounted) setState(() {});
  }

  Future<void> _apply() async {
    if (_busy) return;
    setState(() => _busy = true);
    final err = await DepthService.apply(_p);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) _toast(err);
  }

  // ---- UI

  Widget _preview() {
    return SizedBox(
      height: 420,
      child: Center(
        child: AspectRatio(
          aspectRatio: 9 / 19.5,
          child: LayoutBuilder(
            builder: (context, box) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.ink, width: 3),
                ),
                clipBehavior: Clip.antiAlias,
                child: GestureDetector(
                  onPanStart: (_) => _dragging = true,
                  onPanUpdate: (d) {
                    final w = box.maxWidth, h = box.maxHeight;
                    final k = (_p.invert ? -1 : 1) * _p.sens;
                    _gx = ((d.localPosition.dx / w) * 2 - 1).clamp(-1.0, 1.0).toDouble() * k;
                    _gy = (-((d.localPosition.dy / h) * 2 - 1)).clamp(-1.0, 1.0).toDouble() * k;
                  },
                  onPanEnd: (_) {
                    _dragging = false;
                    _gx = 0;
                    _gy = 0;
                  },
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _DepthPainter(_p.layers, _imgs, _rig, _frame),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppColors.pri),
      label: Text(label),
      onPressed: _busy ? null : onTap,
    );
  }

  Widget _slider(String label, double v, double min, double max, ValueChanged<double> on,
      {String? left, String? right}) {
    return Row(
      children: [
        SizedBox(width: 62, child: Text(label, style: AppText.small)),
        if (left != null) Text(left, style: AppText.mono),
        Expanded(
          child: Slider(
            value: v.clamp(min, max).toDouble(),
            min: min,
            max: max,
            activeColor: AppColors.pri,
            onChanged: on,
            onChangeEnd: (_) => _persist(),
          ),
        ),
        if (right != null) Text(right, style: AppText.mono),
      ],
    );
  }

  Widget _layerCard(int i) {
    final l = _p.layers[i];
    final img = i < _imgs.length ? _imgs[i] : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 38,
                  height: 38,
                  color: Colors.black,
                  child: img == null ? null : RawImage(image: img, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('${i + 1}. ${l.name}', style: AppText.body)),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: i == 0 ? null : () => _move(i, -1),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18)),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: i == _p.layers.length - 1 ? null : () => _move(i, 1),
                  icon: const Icon(Icons.arrow_downward_rounded, size: 18)),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _removeAt(i),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18)),
            ],
          ),
          _slider('Depth', l.d, 0, 1, (v) => setState(() => l.d = v), left: 'far', right: 'near'),
          if (!l.cover) ...[
            _slider('Size', l.w, 0.3, 2.2, (v) => setState(() => l.w = v)),
            _slider('Up/down', l.y, 0, 1, (v) => setState(() => l.y = v)),
            _slider('Left/right', l.x, 0, 1, (v) => setState(() => l.x = v)),
          ],
          _slider('Float', l.f, 0, 0.03, (v) => setState(() => l.f = v), left: 'still', right: 'drift'),
          Row(
            children: [
              const SizedBox(width: 4),
              const Expanded(child: Text('Fill the whole screen', style: AppText.small)),
              Switch(
                value: l.cover,
                activeColor: AppColors.pri,
                onChanged: (v) {
                  setState(() => l.cover = v);
                  _persist();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppNav(
              title: 'Depth wallpaper',
              back: 'Back',
              trailing: NavAction('Set', filled: true, onTap: _apply),
            ),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                      children: [
                        _preview(),
                        const SizedBox(height: 6),
                        const Text(
                          'Tilt your phone left / right (or drag the preview). Far layers move a little, near layers move more.',
                          style: AppText.small,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _chip('Moon in window', Icons.nightlight_round, () => _preset('moon')),
                            _chip('Earth in galaxy', Icons.public, () => _preset('earth')),
                            _chip('Stars only', Icons.auto_awesome, () => _preset('stars')),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _slider('Strength', _p.sens, 0.4, 2.0, (v) => setState(() => _p.sens = v)),
                        Row(
                          children: [
                            const SizedBox(width: 4),
                            const Expanded(child: Text('Reverse direction', style: AppText.small)),
                            Switch(
                              value: _p.invert,
                              activeColor: AppColors.pri,
                              onChanged: (v) {
                                setState(() => _p.invert = v);
                                _persist();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Expanded(child: Text('Layers (back to front)', style: AppText.h2)),
                            TextButton.icon(
                              onPressed: _addPicture,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add'),
                            ),
                          ],
                        ),
                        for (var i = 0; i < _p.layers.length; i++) _layerCard(i),
                        const SizedBox(height: 8),
                        const Text(
                          'Set opens Android\'s live wallpaper screen. Confirm there, and choose Home or Home + Lock.',
                          style: AppText.small,
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
