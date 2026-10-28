import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../data/scenes.dart';
import '../services/pixabay.dart';
import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'motion_editor_screen.dart';
import 'preview_screen.dart';

const _categories = <(String, String)>[
  ('Nature', 'nature landscape'),
  ('Space', 'space galaxy'),
  ('Tech', 'technology circuit'),
  ('Cars', 'sports car'),
  ('Abstract', 'abstract'),
  ('Dark', 'dark'),
  ('City', 'city night'),
  ('Ocean', 'ocean waves'),
  ('Animals', 'animals'),
  ('Flowers', 'flowers'),
];

/// Free photos and videos from Pixabay, by category, ready to turn into wallpapers.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final List<PixabayItem> _items = [];

  bool _video = false;
  int _cat = 0;
  String _query = _categories[0].$2;
  int _page = 1;
  bool _loading = false;
  bool _done = false;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _load();
      }
    });
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    _token++;
    _items.clear();
    _page = 1;
    _done = false;
    _error = null;
    _loading = false;
    if (mounted) setState(() {});
    _load();
  }

  Future<void> _load() async {
    if (_loading || _done) return;
    final token = _token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await Pixabay.search(query: _query, video: _video, page: _page);
      if (!mounted || token != _token) return;
      setState(() {
        _items.addAll(list);
        _page++;
        if (list.length < 20) _done = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 2),
            child: Text('Explore', style: AppText.title),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text('Free photos and videos from Pixabay', style: AppText.small),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Seg(
              labels: const ['Photos', 'Live videos'],
              index: _video ? 1 : 0,
              onChanged: (i) {
                _video = i == 1;
                _reload();
              },
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                final q = v.trim();
                if (q.isEmpty) return;
                _cat = -1;
                _query = q;
                _reload();
              },
              decoration: InputDecoration(
                hintText: 'Search wallpapers',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final on = i == _cat;
                return GestureDetector(
                  onTap: () {
                    _cat = i;
                    _query = _categories[i].$2;
                    _search.clear();
                    _reload();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? const Color(0xFF14111F) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: on ? const Color(0xFF14111F) : AppColors.line),
                    ),
                    child: Text(_categories[i].$1,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: on ? Colors.white : AppColors.ink)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: _grid()),
        ],
      ),
    );
  }

  Widget _grid() {
    if (_items.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? 'Nothing found. Try another word.',
                  textAlign: TextAlign.center, style: AppText.small),
              if (_error != null && Pixabay.hasKey) ...[
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _reload, child: const Text('Try again')),
              ],
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 130),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.62,
      ),
      itemCount: _items.length + (_loading || _error != null ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return Center(
            child: _error != null
                ? TextButton(onPressed: _load, child: const Text('Retry'))
                : const CircularProgressIndicator(),
          );
        }
        final it = _items[i];
        return GestureDetector(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => ExploreViewer(item: it))),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                it.thumb.isEmpty
                    ? const ColoredBox(color: Color(0xFF1E1B2E))
                    : Image.network(
                        it.thumb,
                        fit: BoxFit.cover,
                        cacheWidth: 400,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFEEEDF5)),
                        loadingBuilder: (c, child, p) =>
                            p == null ? child : const ColoredBox(color: Color(0xFFEEEDF5)),
                      ),
                if (it.isVideo)
                  const Center(
                    child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 38),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Full view of one Pixabay item. "Use in Studio" saves it to the gallery and opens the editor.
class ExploreViewer extends StatefulWidget {
  const ExploreViewer({super.key, required this.item});

  final PixabayItem item;

  @override
  State<ExploreViewer> createState() => _ExploreViewerState();
}

class _ExploreViewerState extends State<ExploreViewer> {
  VideoPlayerController? _video;
  bool _busy = false;

  PixabayItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    if (item.isVideo) _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(item.url));
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _video = c);
    } catch (_) {}
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<void> _use() async {
    if (_busy) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.hasAccess) {
        _toast('Allow Photos access to continue.');
        return;
      }
      _video?.pause();
      final file = await Pixabay.download(item.url, item.isVideo ? 'mp4' : 'jpg');
      final AssetEntity asset = item.isVideo
          ? await PhotoManager.editor.saveVideo(file, title: 'pixabay_${item.id}.mp4')
          : await PhotoManager.editor
              .saveImageWithPath(file.path, title: 'pixabay_${item.id}.jpg');
      studio.loadMedia(MediaItem.fromAsset(asset));
      nav.pushReplacement(MaterialPageRoute(
        builder: (_) => item.isVideo ? const MotionEditorScreen() : const PreviewScreen(),
      ));
    } catch (e) {
      if (mounted) _toast('Could not download: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    Widget content;
    if (item.isVideo) {
      content = v == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: v.value.size.width,
                  height: v.value.size.height,
                  child: VideoPlayer(v),
                ),
              ),
            );
    } else {
      content = InteractiveViewer(
        child: Center(
          child: Image.network(
            item.url,
            fit: BoxFit.contain,
            loadingBuilder: (c, child, p) => p == null
                ? child
                : const Center(child: CircularProgressIndicator(color: Colors.white)),
            errorBuilder: (_, __, ___) =>
                const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54)),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(item.user.isEmpty ? 'Pixabay' : '${item.user} · Pixabay',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
      ),
      body: Column(
        children: [
          Expanded(child: content),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: _busy
                  ? const SizedBox(
                      height: 48,
                      child: Center(child: CircularProgressIndicator(color: Colors.white)),
                    )
                  : PrimaryButton(wide: true, label: 'Use in Studio', onTap: _use),
            ),
          ),
        ],
      ),
    );
  }
}
