import 'dart:io';

import 'package:flutter/material.dart';

import '../data/scenes.dart';
import '../services/gif_wallpaper.dart';
import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'pick_media_screen.dart';

/// Gallery GIF -> mp4 (same timing, loops) -> live wallpaper.
class GifWallpaperScreen extends StatefulWidget {
  const GifWallpaperScreen({super.key, required this.path});

  final String path;

  /// Picks a GIF from the gallery and opens this screen.
  static Future<void> pickAndOpen(BuildContext context) async {
    studio.openPicker(video: false);
    final item = await Navigator.of(context).push<MediaItem>(
        MaterialPageRoute(builder: (_) => const PickMediaScreen(forGif: true, photos: true)));
    if (item == null || !context.mounted) return;
    String? path;
    if (item.asset != null) {
      path = (await item.asset!.originFile)?.path ?? (await item.asset!.file)?.path;
    } else {
      path = item.file;
    }
    if (!context.mounted) return;
    if (path == null || !await _isGif(path)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Yeh GIF nahi hai. Gallery se koi GIF chunein.')));
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => GifWallpaperScreen(path: path!)));
  }

  static Future<bool> _isGif(String path) async {
    try {
      final f = await File(path).open();
      final head = await f.read(3);
      await f.close();
      return head.length == 3 && head[0] == 0x47 && head[1] == 0x49 && head[2] == 0x46;
    } catch (_) {
      return false;
    }
  }

  @override
  State<GifWallpaperScreen> createState() => _GifWallpaperScreenState();
}

class _GifWallpaperScreenState extends State<GifWallpaperScreen> {
  bool _fit = false;
  bool _busy = false;
  String _status = '';

  Future<void> _make() async {
    setState(() {
      _busy = true;
      _status = 'GIF ko video bana raha hoon…';
    });
    final mp4 = await GifWallpaper.convert(widget.path, fit: _fit);
    if (!mounted) return;
    if (mp4 == null) {
      setState(() {
        _busy = false;
        _status = 'Convert nahi ho saka. Dosri GIF try karein.';
      });
      return;
    }
    setState(() => _status = 'Live wallpaper set ho raha hai…');
    final r = await GifWallpaper.apply(mp4);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = r.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final (sw, sh) = GifWallpaper.screenSize();
    final fill = _fit ? BoxFit.contain : BoxFit.cover;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('GIF live wallpaper')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: sw / sh,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_fit) ...[
                            Image.file(File(widget.path), fit: BoxFit.cover),
                            Container(color: Colors.black.withValues(alpha: 0.35)),
                          ] else
                            Container(color: Colors.black),
                          Image.file(File(widget.path), fit: fill),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Fill (crop)')),
                  ButtonSegment(value: true, label: Text('Fit + blur')),
                ],
                selected: {_fit},
                onSelectionChanged: _busy ? null : (v) => setState(() => _fit = v.first),
              ),
              const SizedBox(height: 8),
              Text('GIF jaisi hi speed, hamesha loop.', style: AppText.small),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_status, style: AppText.small, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 12),
              if (_busy)
                const CircularProgressIndicator()
              else
                PrimaryButton(label: 'Make live wallpaper', wide: true, onTap: _make),
            ],
          ),
        ),
      ),
    );
  }
}
