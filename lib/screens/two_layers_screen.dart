import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/scenes.dart';
import '../services/depth_service.dart';
import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'art_library_screen.dart';
import 'explore_screen.dart';
import 'photo3d_screen.dart';
import 'pick_media_screen.dart';

/// Pick a picture for the back and one for the front; the front moves more when the phone tilts.
class TwoLayersScreen extends StatefulWidget {
  const TwoLayersScreen({super.key});

  @override
  State<TwoLayersScreen> createState() => _TwoLayersScreenState();
}

class _TwoLayersScreenState extends State<TwoLayersScreen> {
  String? _back;
  String? _front;
  bool _busy = false;

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<String?> _pickPicture(String title, {required bool front}) async {
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text(title, style: AppText.h2),
              ),
              ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('From gallery'),
                  onTap: () => Navigator.pop(c, 'gallery')),
              ListTile(
                  leading: const Icon(Icons.explore_outlined),
                  title: const Text('From Explore (photos, vectors, frames)'),
                  onTap: () => Navigator.pop(c, 'explore')),
              ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: Text(front ? 'Built-in overlays (glass, vines, frost ...)' : 'Built-in back pictures'),
                  onTap: () => Navigator.pop(c, 'library')),
            ],
          ),
        ),
      ),
    );
    if (src == null || !mounted) return null;
    if (src == 'library') {
      final res = await Navigator.of(context).push<(ArtDef, String)>(
          MaterialPageRoute(builder: (_) => ArtLibraryScreen(only: front)));
      return res?.$2;
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
    if (item == null) return null;
    final path = item.asset != null ? (await item.asset!.file)?.path : item.file;
    if (path == null) {
      _toast('This picture is not available.');
      return null;
    }
    return DepthService.addFile(path);
  }

  Future<void> _setBack() async {
    final p = await _pickPicture('Back picture (far)', front: false);
    if (p != null && mounted) setState(() => _back = p);
  }

  Future<void> _setFront() async {
    final p = await _pickPicture('Front picture (near)', front: true);
    if (p != null && mounted) setState(() => _front = p);
  }

  Future<void> _hole() async {
    final f = _front;
    if (f == null) return;
    final out = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => Photo3dScreen(holePath: f)));
    if (out != null && mounted) setState(() => _front = out);
  }

  void _next() {
    final b = _back, f = _front;
    if (b == null || f == null) {
      _toast('Pick both pictures first.');
      return;
    }
    const kk = 1 + 0.2 * 0.8;
    Navigator.of(context).pop<List<DepthLayer>>([
      DepthLayer(path: b, name: 'Back', d: 0.15, cover: true, k: kk),
      DepthLayer(path: f, name: 'Front', d: 0.8, cover: true, k: kk),
    ]);
  }

  Widget _slot(String title, String hint, String? path, VoidCallback onPick, {VoidCallback? onHole}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onPick,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 90,
                height: math.min(160.0, 90 * 16 / 9),
                color: path == null ? AppColors.dim : const Color(0xFF222222),
                child: path == null
                    ? const Icon(Icons.add_photo_alternate_outlined, color: AppColors.pri, size: 30)
                    : Image.file(File(path), fit: BoxFit.contain, cacheWidth: 300),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.h2),
                const SizedBox(height: 3),
                Text(hint, style: AppText.small),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton(onPressed: onPick, child: Text(path == null ? 'Pick' : 'Change')),
                    if (onHole != null && path != null)
                      OutlinedButton(onPressed: onHole, child: const Text('Make a hole')),
                  ],
                ),
              ],
            ),
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
              title: 'Two layers',
              back: 'Back',
              trailing: NavAction('Next', filled: true, onTap: _next),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                children: [
                  _slot(
                    'Back picture',
                    'The far view (a circuit board, a landscape ...). It moves a little.',
                    _back,
                    _setBack,
                  ),
                  const SizedBox(height: 12),
                  _slot(
                    'Front picture',
                    'The near layer (broken glass, a window, a frame ...). It moves more. '
                        'It must have a see-through part so the back can show: use a PNG with transparency, '
                        'or tap "Make a hole" and mark the part to cut out.',
                    _front,
                    _setFront,
                    onHole: _hole,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Next shows a live preview you can tilt, and lets you change depth and strength before setting it.',
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
