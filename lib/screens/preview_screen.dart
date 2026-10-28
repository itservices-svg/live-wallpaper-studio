import 'dart:async';

import 'package:flutter/material.dart';

import '../services/exporter.dart';
import '../services/library_store.dart';
import '../services/trimmer.dart';
import '../services/wallpaper_service.dart';
import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_view.dart';
import '../widgets/mocks.dart';

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  bool _playing = false;
  double _clock = 0;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // A video loop plays by itself on both screens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && studio.media.isVideo) _startLoop();
    });
  }

  void _startLoop() {
    _timer?.cancel();
    studio.holdStart();
    setState(() {
      _playing = true;
      _clock = 0;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      studio.holdTick();
      if (mounted) setState(() => _clock = (_clock + 0.05) % studio.span);
    });
  }

  void _stopLoop() {
    _timer?.cancel();
    studio.holdEnd();
    if (mounted && _playing) setState(() => _playing = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    studio.holdEnd();
    super.dispose();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2200),
      ));
  }

  void _goMyWork() {
    studio.setTab(1);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// Stores what the user just made in My Work.
  Future<void> _remember(ExportFiles files) async {
    final s = studio;
    if (s.media.isVideo) {
      final v = files.videoPath;
      if (v != null) {
        await s.addWork(kind: SavedTheme.live, file: v, thumb: s.keyStill);
      }
    } else {
      await s.addWork(
        kind: SavedTheme.wallpaper,
        file: s.homeBlur > 0 ? files.homePath : files.lockPath,
      );
    }
  }

  Future<void> _set() async {
    if (_busy) return;
    final s = studio;
    ApplyTarget? target;
    if (!s.isIOS && !s.media.isVideo) {
      // Photos: choose which screen. Videos go straight to Android's own screen.
      target = await showModalBottomSheet<ApplyTarget>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        builder: (_) => const _TargetSheet(),
      );
      if (target == null || !mounted) return;
    } else if (!s.isIOS) {
      target = ApplyTarget.live;
    }
    setState(() => _busy = true);
    _stopLoop();
    ApplyResult result;
    ExportFiles? files;
    try {
      files = await Exporter.render(s);
      result = s.isIOS
          ? await WallpaperService.saveToPhotos(files, name: s.themeName)
          : await WallpaperService.applyAndroid(target!, files);
    } catch (e) {
      result = ApplyResult(false, 'Something went wrong: $e');
    }
    if (!mounted) return;
    if (result.ok && files != null) {
      try {
        await _remember(files);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(result.message);
    if (!result.ok) return;
    s.markSaved();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) _goMyWork();
  }

  Future<void> _saveGif() async {
    if (_busy) return;
    final q = await showModalBottomSheet<GifQuality>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => const _GifSheet(),
    );
    if (q == null || !mounted) return;
    final s = studio;
    setState(() => _busy = true);
    _stopLoop();
    String message;
    try {
      final size = MediaQuery.of(context).size;
      final mp4 = await Trimmer.render(s,
          width: q.width * 2 > 1080 ? 1080 : q.width * 2,
          height: ((q.width * 2 > 1080 ? 1080 : q.width * 2) * size.height / size.width).round(),
          prefix: 'gifsrc');
      final gif = mp4 == null ? null : await Trimmer.toGif(mp4, width: q.width, fps: q.fps);
      if (gif == null) {
        message = 'Could not make the GIF. Try a shorter clip or lower quality.';
      } else {
        await s.addWork(kind: SavedTheme.gif, file: gif);
        message = 'GIF saved in My Work';
      }
    } catch (e) {
      message = 'Something went wrong: $e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(message);
    if (message == 'GIF saved in My Work') {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) _goMyWork();
    } else if (s.media.isVideo) {
      _startLoop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: studio,
      builder: (context, _) {
        final s = studio;
        final lock = s.side == PreviewSide.lock;
        final video = s.media.isVideo;
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                const AppNav(title: 'Preview', back: 'Back'),
                Seg(
                  labels: const ['Lock Screen', 'Home Screen'],
                  index: s.side.index,
                  onChanged: (i) => s.setSide(PreviewSide.values[i]),
                ),
                const SizedBox(height: 22),
                Center(
                  child: CropMarks(
                    inset: 6,
                    child: PhoneBezel(
                      glow: s.palette[0].withValues(alpha: 0.45),
                      child: lock
                          ? LockScreenMock(
                              background: LiveBackdrop(state: s, showVideo: _playing, animate: _playing),
                              clockLabel: video ? fmtTime(_clock) : null,
                              tag: video ? 'LIVE' : 'STILL',
                            )
                          : HomeScreenMock(
                              background: LiveBackdrop(state: s, showVideo: _playing, animate: _playing),
                              state: s,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (video)
                  Center(
                    child: Text('Your ${fmtSec(s.span)} loop plays on both screens',
                        style: AppText.small.copyWith(fontSize: 11.5)),
                  )
                else
                  _BlurCard(state: s),
                const SizedBox(height: 14),
                if (_busy)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)),
                    ),
                  )
                else ...[
                  PrimaryButton(
                    wide: true,
                    label: s.isIOS ? 'Save to Photos' : 'Set as wallpaper',
                    sub: s.isIOS ? '${s.exportFiles} ${s.exportFiles == 1 ? 'file' : 'files'}' : null,
                    onTap: _set,
                  ),
                  if (video && s.videoPath != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _saveGif,
                      icon: const Icon(Icons.gif_box_outlined, size: 20),
                      label: const Text('Make GIF'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(color: AppColors.line),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Photos only: optionally soften the Home screen. Off means a sharp Home screen.
class _BlurCard extends StatelessWidget {
  const _BlurCard({required this.state});

  final StudioState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Blur Home screen',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              Switch(value: state.blurOn, onChanged: state.setBlurOn),
            ],
          ),
          if (state.blurOn)
            Row(
              children: [
                Text('Soft', style: AppText.small),
                Expanded(
                  child: Slider(
                    value: state.blur,
                    min: 4,
                    max: 60,
                    onChanged: state.setBlur,
                  ),
                ),
                Text('Strong', style: AppText.small),
              ],
            ),
        ],
      ),
    );
  }
}

/// GIF size / smoothness presets.
class GifQuality {
  const GifQuality(this.label, this.hint, this.width, this.fps);
  final String label;
  final String hint;
  final int width;
  final int fps;
}

const _gifPresets = [
  GifQuality('Small', '320 px · 10 fps · smallest file', 320, 10),
  GifQuality('Medium', '480 px · 15 fps · good for chats', 480, 15),
  GifQuality('High', '640 px · 20 fps · sharper and smoother', 640, 20),
  GifQuality('Best', '720 px · 24 fps · biggest file', 720, 24),
];

class _GifSheet extends StatelessWidget {
  const _GifSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('GIF quality', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Higher quality makes a bigger file and takes longer.', style: AppText.small),
            for (final q in _gifPresets)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(q),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    side: const BorderSide(color: AppColors.line),
                    padding: const EdgeInsets.all(14),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Row(
                    children: [
                      Text(q.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(q.hint,
                            textAlign: TextAlign.end,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.small.copyWith(fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TargetSheet extends StatelessWidget {
  const _TargetSheet();

  @override
  Widget build(BuildContext context) {
    Widget option(ApplyTarget t, String label) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OutlinedButton(
          onPressed: () => Navigator.of(context).pop(t),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.line),
            padding: const EdgeInsets.all(14),
            minimumSize: const Size.fromHeight(52),
            alignment: Alignment.centerLeft,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Set wallpaper', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            option(ApplyTarget.lock, 'Lock screen'),
            option(ApplyTarget.home, 'Home screen'),
            option(ApplyTarget.both, 'Lock + Home'),
          ],
        ),
      ),
    );
  }
}
