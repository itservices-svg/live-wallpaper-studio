import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/depth_service.dart';
import '../services/photo3d.dart';
import '../theme.dart';
import '../widgets/common.dart';

class _KeyPainter extends CustomPainter {
  _KeyPainter(this.img);

  final ui.Image? img;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    canvas.drawRect(
      dst,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height),
            [const Color(0xFF1C3C7A), const Color(0xFFC8668A), const Color(0xFFF0B070)]),
    );
    final i = img;
    if (i != null) {
      canvas.drawImageRect(i, Rect.fromLTWH(0, 0, i.width.toDouble(), i.height.toDouble()), dst,
          Paint()..filterQuality = FilterQuality.medium);
    }
  }

  @override
  bool shouldRepaint(_KeyPainter old) => old.img != img;
}

/// Turns a picture on a black (or white) background into a see-through overlay.
/// Real photos of cracks, rain, smoke, fire, light leaks and bokeh are usually shot this way.
class KeyOutScreen extends StatefulWidget {
  const KeyOutScreen({super.key, required this.path});

  final String path;

  @override
  State<KeyOutScreen> createState() => _KeyOutScreenState();
}

class _KeyOutScreenState extends State<KeyOutScreen> {
  ui.Image? _small;
  Uint8List _px = Uint8List(0);
  ui.Image? _out;
  bool _black = true;
  double _cut = 20;
  double _gain = 1.2;
  bool _busy = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _small?.dispose();
    _out?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final codec = await ui.instantiateImageCodec(await File(widget.path).readAsBytes(), targetWidth: 480);
      final img = (await codec.getNextFrame()).image;
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (!mounted) return;
      _small = img;
      _px = data!.buffer.asUint8List();
      await _update();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open it: $e')));
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _update() async {
    if (_working || _small == null) return;
    _working = true;
    try {
      final img = await Photo3d.fromRgba(
          Photo3d.keyPixels(_px, black: _black, cut: _cut, gain: _gain), _small!.width, _small!.height);
      final old = _out;
      if (mounted) setState(() => _out = img);
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    } finally {
      _working = false;
    }
  }

  Future<void> _done() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final out = await Photo3d.keyOut(widget.path, black: _black, cut: _cut, gain: _gain);
      if (mounted) Navigator.of(context).pop<String>(out);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not make it: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _small;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppNav(title: 'See-through overlay', back: 'Back', trailing: NavAction('Done', filled: true, onTap: _done)),
            Expanded(
              child: s == null
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
                                  aspectRatio: s.width / s.height,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CustomPaint(painter: _KeyPainter(_out)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Use a picture shot on a plain black (or white) background: cracks, rain, smoke, '
                              'fire, light leaks, bokeh. The background becomes see-through and the bright part keeps its real look. '
                              'The sunset behind is only to preview it.',
                              style: AppText.small,
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: [
                                ChoiceChip(
                                  label: const Text('Black background'),
                                  selected: _black,
                                  onSelected: (_) {
                                    setState(() => _black = true);
                                    _update();
                                  },
                                ),
                                ChoiceChip(
                                  label: const Text('White background'),
                                  selected: !_black,
                                  onSelected: (_) {
                                    setState(() => _black = false);
                                    _update();
                                  },
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const SizedBox(width: 70, child: Text('Clean up', style: AppText.small)),
                                Expanded(
                                  child: Slider(
                                    value: _cut,
                                    min: 0,
                                    max: 90,
                                    activeColor: AppColors.pri,
                                    onChanged: (v) {
                                      setState(() => _cut = v);
                                      _update();
                                    },
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const SizedBox(width: 70, child: Text('Strength', style: AppText.small)),
                                Expanded(
                                  child: Slider(
                                    value: _gain,
                                    min: 0.6,
                                    max: 2.5,
                                    activeColor: AppColors.pri,
                                    onChanged: (v) {
                                      setState(() => _gain = v);
                                      _update();
                                    },
                                  ),
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
                              child: const CircularProgressIndicator(color: Colors.white),
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
