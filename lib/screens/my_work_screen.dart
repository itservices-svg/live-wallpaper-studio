import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../services/library_store.dart';
import '../services/wallpaper_service.dart';
import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/work_thumb.dart';
import 'gif_editor_screen.dart';
import 'studio_screen.dart';

/// Everything the user made, by category. Updates the moment anything is added,
/// changed or deleted because it listens to the shared state.
class MyWorkScreen extends StatefulWidget {
  const MyWorkScreen({super.key});

  @override
  State<MyWorkScreen> createState() => _MyWorkScreenState();
}

class _MyWorkScreenState extends State<MyWorkScreen> {
  String? _filter; // null = all

  static const _tabs = <(String?, String)>[
    (null, 'All'),
    (SavedTheme.wallpaper, 'Wallpapers'),
    (SavedTheme.live, 'Live'),
    (SavedTheme.gif, 'GIFs'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: studio,
      builder: (context, _) {
        final all = studio.library;
        final items = _filter == null ? all : all.where((e) => e.kind == _filter).toList();
        int count(String? k) => k == null ? all.length : all.where((e) => e.kind == k).length;
        return SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: Text('My Work', style: AppText.title),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    for (final t in _tabs) ...[
                      _FilterChip(
                        label: t.$2,
                        count: count(t.$1),
                        on: _filter == t.$1,
                        onTap: () => setState(() => _filter = t.$1),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            all.isEmpty
                                ? 'Nothing here yet. Wallpapers, live wallpapers and GIFs you make show up here.'
                                : 'No items in this category yet.',
                            textAlign: TextAlign.center,
                            style: AppText.small,
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 130),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 14,
                          childAspectRatio: 0.5,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, i) => _WorkTile(
                          key: ValueKey(items[i].id),
                          item: items[i],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => WorkViewer(item: items[i])),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.count, required this.on, required this.onTap});

  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? const Color(0xFF14111F) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? const Color(0xFF14111F) : AppColors.line),
        ),
        child: Text(
          '$label  $count',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: on ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _WorkTile extends StatelessWidget {
  const _WorkTile({super.key, required this.item, required this.onTap});

  final SavedTheme item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final live = item.kind == SavedTheme.live;
    final gif = item.kind == SavedTheme.gif;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  WorkThumb(item),
                  Positioned(left: 5, top: 5, child: Pill(gif ? 'GIF' : (live ? 'LIVE' : 'STILL'), live: live)),
                  if (live)
                    const Center(
                      child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 34),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          Text(item.ago,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.small.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}

/// Full-screen view of one item with Share, Download, Edit and Delete.
class WorkViewer extends StatefulWidget {
  const WorkViewer({super.key, required this.item});

  final SavedTheme item;

  @override
  State<WorkViewer> createState() => _WorkViewerState();
}

class _WorkViewerState extends State<WorkViewer> {
  VideoPlayerController? _video;

  SavedTheme get item => widget.item;

  @override
  void initState() {
    super.initState();
    if (item.kind == SavedTheme.live) _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final c = VideoPlayerController.file(File(item.file));
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

  Future<void> _share() async {
    try {
      await Share.shareXFiles([XFile(item.file)], text: item.name);
    } catch (e) {
      if (mounted) _toast('Could not share: $e');
    }
  }

  Future<void> _download() async {
    final r = await WallpaperService.saveToGallery(
      item.file,
      name: item.name,
      video: item.kind == SavedTheme.live,
    );
    if (mounted) _toast(r.message);
  }

  Future<void> _edit() async {
    final nav = Navigator.of(context);
    nav.pop();
    studio.setTab(0);
    if (item.isGif) {
      await nav.push(MaterialPageRoute(
          builder: (_) => GifEditorScreen(project: item.proj, replaceId: item.id)));
      return;
    }
    await openWorkForEdit(nav.context, item);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete this?'),
        content: Text('"${item.name}" will be removed from My Work. Your original photo or video is not deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.of(context).pop();
    await studio.removeSaved(item.id);
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    Widget content;
    if (item.kind == SavedTheme.live) {
      content = v == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Center(
              child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v)),
            );
    } else {
      content = InteractiveViewer(
        child: Center(child: Image.file(File(item.file), fit: BoxFit.contain, gaplessPlayback: true)),
      );
    }

    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 24),
                  const SizedBox(height: 4),
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                ],
              ),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(child: content),
          SafeArea(
            top: false,
            child: Row(
              children: [
                action(Icons.share_outlined, 'Share', _share),
                action(Icons.download_outlined, 'Download', _download),
                if (item.canEdit || item.canEditGif) action(Icons.edit_outlined, 'Edit', _edit),
                action(Icons.delete_outline, 'Delete', _delete),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
