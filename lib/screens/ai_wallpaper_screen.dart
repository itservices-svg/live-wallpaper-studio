import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/scenes.dart';
import '../services/ai_image.dart';
import '../services/wallpaper_service.dart';
import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'motion_editor_screen.dart';
import 'photo3d_screen.dart';
import 'preview_screen.dart';

class _Style {
  const _Style(this.label, this.icon, this.text);
  final String label;
  final IconData icon;
  final String text;
}

const _styles = <_Style>[
  _Style('Photo', Icons.photo_camera_outlined, 'ultra realistic photo, cinematic lighting, sharp detail'),
  _Style('Neon', Icons.bolt_outlined, 'neon glow, cyberpunk, vivid colors, night'),
  _Style('Anime', Icons.auto_awesome_outlined, 'anime style, detailed illustration, soft colors'),
  _Style('Fantasy', Icons.castle_outlined, 'epic fantasy art, magical atmosphere, painterly'),
  _Style('Minimal', Icons.crop_square, 'minimalist, clean shapes, soft gradient, lots of empty space'),
  _Style('Dark', Icons.dark_mode_outlined, 'dark moody, deep black background, AMOLED friendly'),
  _Style('Abstract', Icons.blur_on, 'abstract fluid shapes, smooth gradients, modern art'),
];

const _ideas = <String>[
  'A lone lighthouse in a storm at night',
  'Glowing jellyfish floating in deep blue ocean',
  'A samurai standing under falling cherry blossoms',
  'Northern lights over a snowy mountain lake',
  'A tiny cabin in a misty pine forest at dawn',
  'Astronaut sitting on the moon looking at Earth',
  'Cyberpunk street in the rain with neon signs',
  'A golden dragon curled around a glowing crystal',
];

/// Text -> AI picture -> wallpaper, 3D effect or gallery.
class AiWallpaperScreen extends StatefulWidget {
  const AiWallpaperScreen({super.key});

  @override
  State<AiWallpaperScreen> createState() => _AiWallpaperScreenState();
}

class _AiWallpaperScreenState extends State<AiWallpaperScreen> {
  final _prompt = TextEditingController();
  int _style = 0;
  int _mode = 0; // 0 picture, 1 video
  File? _video;
  VideoPlayerController? _vc;
  int _vused = 0;
  bool _busy = false;
  String? _error;
  File? _current;
  List<File> _history = [];
  int _used = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _vc?.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final h = await AiImage.history();
    final u = await AiImage.usedToday();
    _vused = await AiImage.videoUsedToday();
    if (_video == null) {
      final v = await AiImage.latestVideo();
      if (v != null) await _loadVideo(v);
    }
    if (!mounted) return;
    setState(() {
      _history = h;
      _used = u;
      _current ??= h.isEmpty ? null : h.first;
    });
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<void> _generate() async {
    final idea = _prompt.text.trim();
    if (idea.isEmpty) {
      _toast('Describe your wallpaper first.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final full = '$idea, ${_styles[_style].text}, vertical phone wallpaper, '
        'high quality, no text, no watermark, no border';
    try {
      final f = await AiImage.generate(full, model: 'zimage');
      _current = f;
      await _refresh();
    } on AiImageException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Something went wrong. Try again.';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _loadVideo(File f) async {
    final old = _vc;
    final c = VideoPlayerController.file(f);
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
    } catch (_) {
      await c.dispose();
      return;
    }
    _vc = c;
    _video = f;
    await old?.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _generateVideo() async {
    final idea = _prompt.text.trim();
    if (idea.isEmpty) {
      _toast('Describe your video first.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Make a video?'),
        content: const Text('A ${AiImage.videoSeconds}-second video costs real money (about \$0.06, quick preview quality). '
            'It can take a minute or two. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Make it')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final full = '$idea, ${_styles[_style].text}, vertical 9:16 phone wallpaper, '
        'smooth seamless loop, gentle motion, no text, no watermark';
    try {
      final f = await AiImage.generateVideo(full);
      await _loadVideo(f);
      _vused = await AiImage.videoUsedToday();
    } on AiImageException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Something went wrong. Try again.';
    }
    if (mounted) setState(() => _busy = false);
  }

  void _videoAsWallpaper() {
    final f = _video;
    if (f == null) return;
    studio.loadMedia(MediaItem.fromFile(f.path, 'AI video', video: true,
        seconds: AiImage.videoSeconds.toDouble()));
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MotionEditorScreen()));
  }

  Future<void> _saveVideo() async {
    final f = _video;
    if (f == null) return;
    final r = await WallpaperService.saveToGallery(f.path,
        name: 'ai_video_${DateTime.now().millisecondsSinceEpoch}', video: true);
    _toast(r.ok ? 'Saved to your gallery' : r.message);
  }

  void _surprise() {
    setState(() => _prompt.text = _ideas[math.Random().nextInt(_ideas.length)]);
  }

  void _useAsWallpaper() {
    final f = _current;
    if (f == null) return;
    studio.loadMedia(MediaItem.fromFile(f.path, 'AI wallpaper', video: false));
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PreviewScreen()));
  }

  void _make3d() {
    final f = _current;
    if (f == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Photo3dScreen(startPath: f.path)));
  }

  Future<void> _save() async {
    final f = _current;
    if (f == null) return;
    final r = await WallpaperService.saveToGallery(f.path,
        name: 'ai_wallpaper_${DateTime.now().millisecondsSinceEpoch}', video: false);
    _toast(r.ok ? 'Saved to your gallery' : r.message);
  }

  Future<void> _delete(File f) async {
    await AiImage.remove(f);
    if (_current?.path == f.path) _current = null;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final left = (AiImage.dailyLimit - _used).clamp(0, AiImage.dailyLimit);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            AppNav(title: 'AI Wallpaper', back: 'Create'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                children: [
                  if (!AiImage.hasKey) _notice('This build has no AI key yet. Add the AI_IMAGE_KEY secret and rebuild.'),
                  Seg(
                    labels: const ['Picture', 'Video'],
                    index: _mode,
                    onChanged: (i) {
                      if (_busy) return;
                      setState(() {
                        _mode = i;
                        _error = null;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  _mode == 0 ? _preview() : _videoPreview(),
                  const SizedBox(height: 14),
                  if (_mode == 0 && _current != null && !_busy) _actions(),
                  if (_mode == 1 && _video != null && !_busy) _videoActions(),
                  if (_error != null) _notice(_error!, error: true),
                  const SizedBox(height: 14),
                  _promptBox(),
                  const SizedBox(height: 14),
                  const Text('STYLE', style: AppText.mono),
                  const SizedBox(height: 8),
                  _styleRow(),
                  const SizedBox(height: 14),
                  const SizedBox(height: 16),
                  if (_busy)
                    _busyBar()
                  else
                    PrimaryButton(
                        label: _mode == 0
                            ? (_current == null ? 'Generate' : 'Generate new')
                            : 'Make ${AiImage.videoSeconds}-sec video',
                        wide: true,
                        onTap: _mode == 0 ? _generate : _generateVideo),
                  const SizedBox(height: 8),
                  Center(
                      child: Text(
                          _mode == 0
                              ? '$left of ${AiImage.dailyLimit} left today'
                              : '${(AiImage.videoDailyLimit - _vused).clamp(0, AiImage.videoDailyLimit)} of ${AiImage.videoDailyLimit} videos left today',
                          style: AppText.small)),
                  if (_mode == 0 && _history.length > 1) ...[
                    const SizedBox(height: 18),
                    const Text('YOUR AI PICTURES', style: AppText.mono),
                    const SizedBox(height: 8),
                    _historyRow(),
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 250),
        child: AspectRatio(
          aspectRatio: 1024 / 1792,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line, width: 2),
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE7E2F8), Color(0xFFF7F5FC)],
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_current != null)
                    Image.file(_current!, fit: BoxFit.cover, gaplessPlayback: true)
                  else
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome, size: 38, color: AppColors.pri),
                            const SizedBox(height: 10),
                            Text('Describe it.\nAI paints it.', textAlign: TextAlign.center, style: AppText.h2),
                          ],
                        ),
                      ),
                    ),
                  if (_busy)
                    Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _videoPreview() {
    final c = _vc;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 250),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line, width: 2),
                borderRadius: BorderRadius.circular(26),
                color: const Color(0xFFE7E2F8),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (c != null && c.value.isInitialized)
                    FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: c.value.size.width,
                        height: c.value.size.height,
                        child: VideoPlayer(c),
                      ),
                    )
                  else
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.movie_creation_outlined, size: 38, color: AppColors.pri),
                            const SizedBox(height: 10),
                            Text('Describe it.\nAI films it.', textAlign: TextAlign.center, style: AppText.h2),
                          ],
                        ),
                      ),
                    ),
                  if (_busy)
                    Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _videoActions() {
    Widget btn(IconData i, String l, VoidCallback t, {bool main = false}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: main ? AppColors.pri : Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: t,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: main ? AppColors.pri : AppColors.line),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(i, size: 21, color: main ? Colors.white : AppColors.ink),
                      const SizedBox(height: 3),
                      Text(l,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: main ? Colors.white : AppColors.ink)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
    return Row(
      children: [
        btn(Icons.wallpaper_outlined, 'Live wallpaper', _videoAsWallpaper, main: true),
        btn(Icons.download_outlined, 'Save', _saveVideo),
      ],
    );
  }

  Widget _actions() {
    Widget btn(IconData i, String l, VoidCallback t, {bool main = false}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: main ? AppColors.pri : Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: t,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: main ? AppColors.pri : AppColors.line),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(i, size: 21, color: main ? Colors.white : AppColors.ink),
                      const SizedBox(height: 3),
                      Text(l,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: main ? Colors.white : AppColors.ink)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
    return Row(
      children: [
        btn(Icons.wallpaper_outlined, 'Wallpaper', _useAsWallpaper, main: true),
        btn(Icons.threed_rotation_rounded, '3D effect', _make3d),
        btn(Icons.download_outlined, 'Save', _save),
      ],
    );
  }

  Widget _promptBox() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _prompt,
              minLines: 2,
              maxLines: 4,
              maxLength: 300,
              enabled: !_busy,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
                hintText: 'e.g. A lone lighthouse in a storm at night',
              ),
            ),
          ),
          IconButton(
            tooltip: 'Surprise me',
            onPressed: _busy ? null : _surprise,
            icon: const Icon(Icons.casino_outlined, color: AppColors.pri),
          ),
        ],
      ),
    );
  }

  Widget _styleRow() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _styles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final on = i == _style;
          return GestureDetector(
            onTap: _busy ? null : () => setState(() => _style = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: on ? AppColors.pri : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: on ? AppColors.pri : AppColors.line),
              ),
              child: Row(
                children: [
                  Icon(_styles[i].icon, size: 16, color: on ? Colors.white : AppColors.sub),
                  const SizedBox(width: 6),
                  Text(_styles[i].label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: on ? Colors.white : AppColors.ink)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _busyBar() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: const LinearProgressIndicator(minHeight: 6, color: AppColors.pri),
        ),
        const SizedBox(height: 8),
        Text('Painting your wallpaper… this can take up to a minute.', style: AppText.small),
      ],
    );
  }

  Widget _historyRow() {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _history.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = _history[i];
          final on = _current?.path == f.path;
          return GestureDetector(
            onTap: () => setState(() => _current = f),
            onLongPress: () => _delete(f),
            child: AspectRatio(
              aspectRatio: 1024 / 1792,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: on ? AppColors.pri : AppColors.line, width: on ? 3 : 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.file(f, fit: BoxFit.cover, cacheWidth: 240),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _notice(String text, {bool error = false}) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFDECEF) : const Color(0xFFFFF6E0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(error ? Icons.error_outline : Icons.info_outline, size: 18, color: error ? AppColors.live : const Color(0xFF9A6B00)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppText.small.copyWith(color: AppColors.ink))),
        ],
      ),
    );
  }
}
