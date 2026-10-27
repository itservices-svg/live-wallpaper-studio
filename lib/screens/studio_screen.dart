import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../data/scenes.dart';
import '../services/library_store.dart';
import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/scene_view.dart';
import 'motion_editor_screen.dart';
import 'pick_media_screen.dart';
import 'preview_screen.dart';
import 'theme_builder_screen.dart';

/// Where a finished edit goes next, depending on mode and source.
Future<void> goAfterEdit(BuildContext context, {required bool fromVideo}) {
  final next = studio.mode == WallMode.theme ? const ThemeBuilderScreen() : const PreviewScreen();
  return Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => next));
}

class StudioScreen extends StatelessWidget {
  const StudioScreen({super.key});

  void _openPicker(BuildContext context, bool video) {
    studio.openPicker(video: video);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PickMediaScreen()));
  }

  Future<void> _openRecent(BuildContext context, SavedTheme t) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await studio.openSaved(t);
    if (!ok) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('That photo or video is no longer in your gallery.'),
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }
    if (t.isVideo) {
      nav.push(MaterialPageRoute(builder: (_) => const MotionEditorScreen()));
    } else {
      nav.push(MaterialPageRoute(
          builder: (_) => studio.mode == WallMode.theme
              ? const ThemeBuilderScreen()
              : const PreviewScreen()));
    }
  }

  void _seeAll(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, controller) => ListenableBuilder(
          listenable: studio,
          builder: (_, __) => Column(
            children: [
              const SizedBox(height: 14),
              const Text('All themes', style: AppText.h2),
              Text('Tap to edit · long-press to delete', style: AppText.small),
              const SizedBox(height: 10),
              Expanded(
                child: studio.library.isEmpty
                    ? Center(child: Text('Nothing saved yet', style: AppText.small))
                    : GridView.builder(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.52,
                        ),
                        itemCount: studio.library.length,
                        itemBuilder: (_, i) {
                          final t = studio.library[i];
                          return _RecentTile(
                            item: t,
                            onTap: () {
                              Navigator.of(sheet).pop();
                              _openRecent(context, t);
                            },
                            onLongPress: () => studio.removeSaved(t.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: studio,
      builder: (context, _) {
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
            children: [
              if (kDebugMode) const _DebugPlatform(),
              const Text('Create Studio', style: AppText.title),
              const SizedBox(height: 16),
              Seg(
                labels: const ['Single Wallpaper', 'Theme · Lock + Home'],
                index: studio.mode.index,
                onChanged: (i) => studio.setMode(WallMode.values[i]),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _CreateCard(video: true, onTap: () => _openPicker(context, true))),
                  const SizedBox(width: 14),
                  Expanded(child: _CreateCard(video: false, onTap: () => _openPicker(context, false))),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('▸ No footage? Try ', style: AppText.small),
                  GestureDetector(
                    onTap: () {
                      studio.loadScene(9);
                      Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const MotionEditorScreen()));
                    },
                    child: const Text(
                      '"Kyoto Rain"',
                      style: TextStyle(
                        color: AppColors.live,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text('Recent', style: AppText.h2),
                  const SizedBox(width: 4),
                  Text(studio.library.length.toString().padLeft(2, '0'), style: AppText.mono),
                  const Spacer(),
                  if (studio.library.length > 4)
                    GestureDetector(
                      onTap: () => _seeAll(context),
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        child: Text('See All',
                            style: TextStyle(
                                color: AppColors.pri, fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (studio.library.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Themes you set as wallpaper show up here so you can edit them again.',
                    style: AppText.small,
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < 4; i++) ...[
                      if (i > 0) const SizedBox(width: 9),
                      Expanded(
                        child: i < studio.library.length
                            ? _RecentTile(
                                item: studio.library[i],
                                onTap: () => _openRecent(context, studio.library[i]),
                                onLongPress: () => studio.removeSaved(studio.library[i].id),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CreateCard extends StatelessWidget {
  const _CreateCard({required this.video, required this.onTap});

  final bool video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CropMarks(
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: (MediaQuery.of(context).size.height * 0.31).clamp(210.0, 280.0).toDouble(),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
            gradient: video
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFE7E2F8), Color(0xFFF4F2FB)],
                  )
                : null,
            color: video ? null : const Color(0xFFEEEDF5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      video
                          ? Row(children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                    color: AppColors.live, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 4),
                              Text('LIVE', style: AppText.mono.copyWith(color: AppColors.live)),
                            ])
                          : const Text('STILL', style: AppText.mono),
                      Text(video ? '00:00 / 05:00' : '9:19.5', style: AppText.mono),
                    ],
                  ),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (video) const Positioned(left: 0, right: 0, bottom: 2, child: _Bars()),
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: video ? const Color(0xFF14111F) : Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(color: Color(0x4D140A32), blurRadius: 14, offset: Offset(0, 6)),
                            ],
                          ),
                          child: Icon(
                            video ? Icons.play_arrow_rounded : Icons.image_outlined,
                            color: video ? Colors.white : AppColors.ink,
                            size: video ? 30 : 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(video ? 'New from video' : 'New from photo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(video ? 'Trim & loop a live clip' : 'Frame it for Lock or Home',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.small.copyWith(fontSize: 11.5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 30; i++)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                height: 8 + (18 * ((i * 7919) % 100) / 100) + (8 * (i % 3) / 2),
                color: const Color(0xFFB9B3D6),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.item, required this.onTap, required this.onLongPress});

  final SavedTheme item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 9 / 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _SavedThumb(assetId: item.assetId),
                  Positioned(
                      left: 4,
                      top: 4,
                      child: Pill(item.isVideo ? 'LIVE' : 'STILL', live: item.isVideo)),
                  if (item.duration.isNotEmpty)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Text(item.duration,
                          style: AppText.mono.copyWith(
                              fontSize: 9,
                              color: Colors.white,
                              shadows: const [Shadow(color: Colors.black54, blurRadius: 4)])),
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
          Text(item.ago, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppText.small.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}

class _SavedThumb extends StatefulWidget {
  const _SavedThumb({required this.assetId});

  final String assetId;

  @override
  State<_SavedThumb> createState() => _SavedThumbState();
}

class _SavedThumbState extends State<_SavedThumb> {
  late final Future<Uint8List?> _bytes = _load();

  Future<Uint8List?> _load() async {
    if (widget.assetId.startsWith('sample:')) return null;
    final a = await AssetEntity.fromId(widget.assetId);
    return a?.thumbnailDataWithSize(const ThumbnailSize(240, 420));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.assetId.startsWith('sample:')) {
      final i = int.tryParse(widget.assetId.substring(7)) ?? 0;
      return SceneView(scene: scenes[i % scenes.length]);
    }
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snap) {
        final b = snap.data;
        if (b == null) return const ColoredBox(color: Color(0xFFEEEDF5));
        return Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}

/// Debug-only: flip between the iOS and Android flows on one device.
class _DebugPlatform extends StatelessWidget {
  const _DebugPlatform();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: true, label: Text('iOS flow')),
          ButtonSegment(value: false, label: Text('Android flow')),
        ],
        selected: {studio.isIOS},
        onSelectionChanged: (s) => studio.setPlatformOverride(s.first),
      ),
    );
  }
}
