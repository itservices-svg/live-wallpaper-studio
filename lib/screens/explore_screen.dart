import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/scenes.dart';
import '../services/pixabay.dart';
import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../services/gif_art.dart';
import 'gif_editor_screen.dart';
import 'motion_editor_screen.dart';
import 'preview_screen.dart';

class _Kind {
  const _Kind(this.label, this.video, this.imageType, this.videoType, this.cats);
  final String label;
  final bool video;
  final String imageType; // photo | vector | illustration | all
  final String videoType; // all | animation
  final List<(String, String)> cats; // label, search words
}

const _kinds = <_Kind>[
  _Kind('Photos', false, 'photo', 'all', [
    ('Nature', 'nature landscape'),
    ('Space', 'space galaxy'),
    ('Tech', 'technology circuit'),
    ('Cars', 'sports car'),
    ('Abstract', 'abstract'),
    ('Dark', 'dark'),
    ('City', 'city night'),
    ('Ocean', 'ocean waves'),
    ('Mountains', 'mountains'),
    ('Sunset', 'sunset sky'),
    ('Animals', 'animals'),
    ('Flowers', 'flowers'),
    ('Minimal', 'minimal'),
    ('Texture', 'texture'),
  ]),
  _Kind('Live', true, 'photo', 'all', [
    ('Nature', 'nature'),
    ('Space', 'space'),
    ('Abstract', 'abstract'),
    ('Particles', 'particles'),
    ('Neon', 'neon'),
    ('Rain', 'rain'),
    ('Fire', 'fire'),
    ('Ocean', 'ocean waves'),
    ('City', 'city night'),
    ('Clouds', 'clouds'),
    ('Animals', 'animals'),
  ]),
  _Kind('Vectors', false, 'vector', 'all', [
    ('Abstract', 'abstract'),
    ('Gradient', 'gradient'),
    ('Pattern', 'pattern'),
    ('Geometric', 'geometric'),
    ('Minimal', 'minimal'),
    ('Mandala', 'mandala'),
    ('Landscape', 'landscape'),
    ('Animals', 'animals'),
    ('Neon', 'neon'),
  ]),
  _Kind('Illustrations', false, 'illustration', 'all', [
    ('Fantasy', 'fantasy'),
    ('Anime', 'anime'),
    ('Landscape', 'landscape'),
    ('Cartoon', 'cartoon'),
    ('Space', 'space'),
    ('Dark', 'dark'),
    ('Neon', 'neon'),
    ('Art', 'art'),
  ]),
  _Kind('Frames', false, 'all', 'all', [
    ('Photo frame', 'photo frame'),
    ('Floral', 'floral frame'),
    ('Gold', 'gold frame'),
    ('Neon', 'neon frame'),
    ('Border', 'border frame'),
    ('Vintage', 'vintage frame'),
    ('Polaroid', 'polaroid frame'),
  ]),
];

/// Free photos and videos from Pixabay, by category, ready to turn into wallpapers.
class ExploreScreen extends StatefulWidget {
  /// [allowed]: kinds (indexes into the list above) when this screen is opened to pick one
  /// item and return it; null for the normal Explore tab.
  const ExploreScreen({super.key, this.allowed, this.title});

  final List<int>? allowed;
  final String? title;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final List<PixabayItem> _items = [];

  PixabayFilters _filters = const PixabayFilters();
  final _rand = Random();
  int _kindIdx = 0;
  int _cat = 0;
  String _query = _kinds[0].cats[0].$2;
  int _startPage = 1;

  bool _downloading = false;

  bool get _picking => widget.allowed != null;
  List<int> get _kindList => widget.allowed ?? const [0, 1, 2, 3, 4];
  _Kind get _kind => _kinds[_kindIdx];
  bool get _video => _kind.video;
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
    if (_picking) {
      _kindIdx = widget.allowed!.first;
      _query = _kind.cats[0].$2;
      if (_kind.video) _filters = _filters.copyWith(orientation: 'all');
    }
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
    // Start from a random page so the same pictures do not show every time.
    _startPage = 1 + _rand.nextInt(_video ? 4 : 6);
    _page = _startPage;
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
      final r = await Pixabay.search(
          query: _query,
          video: _video,
          filters: _filters,
          imageType: _kind.imageType,
          videoType: _kind.videoType,
          page: _page);
      if (!mounted || token != _token) return;
      if (r.items.isEmpty && _items.isEmpty && _page > 1) {
        // Random page was past the end of a small result set: start from the top.
        _page = 1;
        _loading = false;
        _load();
        return;
      }
      final fresh = r.items.toList()..shuffle(_rand);
      setState(() {
        _items.addAll(fresh);
        _page = r.nextPage;
        _done = r.done;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      if (e is PixabayException && e.status == 400 && _page > 1 && _items.isEmpty) {
        _page = 1;
        _loading = false;
        _load();
        return;
      }
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<void> _pickItem(PixabayItem it) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final file = await Pixabay.download(it.url, it.isVideo ? 'mp4' : 'jpg', id: it.id);
      if (!mounted) return;
      Navigator.of(context).pop(MediaItem.fromFile(file.path, 'Pixabay ${it.id}',
          video: it.isVideo, seconds: it.seconds));
    } catch (e) {
      if (mounted) _toast('Could not download: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _content(context);
    if (!_picking) return body;
    return Scaffold(
      body: Stack(
        children: [
          body,
          if (_downloading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator(color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_picking)
            AppNav(title: widget.title ?? 'Explore', back: 'Back')
          else ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 2),
              child: Text('Explore', style: AppText.title),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text('Free photos and videos from Pixabay', style: AppText.small),
            ),
          ],
          if (_kindList.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _kindList.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, ix) {
                  final i = _kindList[ix];
                  final on = i == _kindIdx;
                  return GestureDetector(
                    onTap: () {
                      if (i == _kindIdx) return;
                      _kindIdx = i;
                      _cat = 0;
                      _query = _kind.cats[0].$2;
                      _search.clear();
                      // Frames look best in any shape; everything else starts portrait.
                      _filters = _filters.copyWith(orientation: i == 4 ? 'all' : 'portrait');
                      _reload();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on ? AppColors.pri : AppColors.dim,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_kinds[i].label,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: on ? Colors.white : AppColors.ink)),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Expanded(child: TextField(
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
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _openFilters,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _filters.isDefault ? Colors.white : const Color(0xFF14111F),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Icon(Icons.tune_rounded,
                      size: 20, color: _filters.isDefault ? AppColors.ink : Colors.white),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _kind.cats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final on = i == _cat;
                return GestureDetector(
                  onTap: () {
                    _cat = i;
                    _query = _kind.cats[i].$2;
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
                    child: Text(_kind.cats[i].$1,
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

  Future<void> _openFilters() async {
    final res = await showModalBottomSheet<PixabayFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FilterSheet(initial: _filters, video: _video),
    );
    if (res == null) return;
    _filters = res;
    _reload();
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
      padding: EdgeInsets.fromLTRB(20, 0, 20, _picking ? 24 : 130),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: switch (_filters.orientation) {
          'landscape' => 1.25,
          'all' => 0.85,
          _ => 0.62,
        },
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
          onTap: () => _picking
              ? _pickItem(it)
              : Navigator.of(context)
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

  /// [gif] false: open the wallpaper editor. true: open the GIF studio (video as a clip,
  /// pictures as a backdrop that stays saved there).
  Future<void> _go(bool gif) async {
    if (_busy) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      _video?.pause();
      final file = await Pixabay.download(item.url, item.isVideo ? 'mp4' : 'jpg', id: item.id);
      bool keep(String p) =>
          p == file.path ||
          studio.library.any((t) => t.assetId == 'file:$p' || (t.proj?.contains(p) ?? false));
      unawaited(Pixabay.cleanup(keep));
      final mi = MediaItem.fromFile(file.path, 'Pixabay ${item.id}',
          video: item.isVideo, seconds: item.seconds);
      if (gif) {
        if (item.isVideo) {
          nav.pushReplacement(MaterialPageRoute(builder: (_) => GifEditorScreen(initialClip: mi)));
        } else {
          final art = await GifArt.add(file.path);
          nav.pushReplacement(MaterialPageRoute(builder: (_) => GifEditorScreen(initialArt: art)));
        }
      } else {
        studio.loadMedia(mi);
        nav.pushReplacement(MaterialPageRoute(
          builder: (_) => item.isVideo ? const MotionEditorScreen() : const PreviewScreen(),
        ));
      }
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
                  : Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                              wide: true, label: 'Make Wallpaper', onTap: () => _go(false)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PrimaryButton(
                              wide: true,
                              label: item.isVideo ? 'Make GIF' : 'Add to GIF Studio',
                              onTap: () => _go(true)),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.video});

  final PixabayFilters initial;
  final bool video;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late PixabayFilters f = widget.initial;

  static const _orient = ['portrait', 'landscape', 'all'];
  static const _orders = ['popular', 'latest'];
  static const _colors = <(String, Color)>[
    ('red', Color(0xFFE53935)),
    ('orange', Color(0xFFFB8C00)),
    ('yellow', Color(0xFFFDD835)),
    ('green', Color(0xFF43A047)),
    ('turquoise', Color(0xFF00ACC1)),
    ('blue', Color(0xFF1E88E5)),
    ('lilac', Color(0xFF9575CD)),
    ('pink', Color(0xFFEC407A)),
    ('white', Color(0xFFFFFFFF)),
    ('gray', Color(0xFF9E9E9E)),
    ('black', Color(0xFF212121)),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filters', style: AppText.h2),
            const SizedBox(height: 14),
            Text('Shape', style: AppText.small),
            const SizedBox(height: 6),
            Seg(
              labels: const ['Portrait', 'Landscape', 'All'],
              index: _orient.indexOf(f.orientation),
              onChanged: (i) => setState(() => f = f.copyWith(orientation: _orient[i])),
            ),
            const SizedBox(height: 14),
            Text('Sort by', style: AppText.small),
            const SizedBox(height: 6),
            Seg(
              labels: const ['Popular', 'Latest'],
              index: _orders.indexOf(f.order),
              onChanged: (i) => setState(() => f = f.copyWith(order: _orders[i])),
            ),
            if (!widget.video) ...[
              const SizedBox(height: 14),
              Text('Colour', style: AppText.small),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in _colors)
                    GestureDetector(
                      onTap: () => setState(
                          () => f = f.copyWith(color: f.color == c.$1 ? '' : c.$1)),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: c.$2,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: f.color == c.$1 ? AppColors.pri : AppColors.line,
                            width: f.color == c.$1 ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => f = const PixabayFilters()),
                  child: const Text('Reset'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PrimaryButton(
                      wide: true, label: 'Apply', onTap: () => Navigator.pop(context, f)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
