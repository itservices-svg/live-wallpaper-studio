import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/library_store.dart';
import '../state/studio_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/work_thumb.dart';
import 'depth_editor_screen.dart';
import 'gif_editor_screen.dart';
import 'motion_editor_screen.dart';
import 'my_work_screen.dart' show WorkViewer;
import 'pick_media_screen.dart';
import 'preview_screen.dart';

/// Where a finished edit goes next.
Future<void> goAfterEdit(BuildContext context, {required bool fromVideo}) {
  return Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const PreviewScreen()));
}

/// Re-opens a saved wallpaper / live wallpaper for editing.
Future<void> openWorkForEdit(BuildContext context, SavedTheme t) async {
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
    nav.push(MaterialPageRoute(builder: (_) => const PreviewScreen()));
  }
}

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  int _mode = 0; // 0 = Make Wallpaper, 1 = Make GIF

  void _openPicker(BuildContext context, bool video) {
    studio.openPicker(video: video);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PickMediaScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: studio,
      builder: (context, _) {
        final gifMode = _mode == 1;
        final depthMode = _mode == 2;
        final recent = studio.library
            .where((e) => gifMode ? e.isGif : e.canEdit)
            .take(4)
            .toList();
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
            children: [
              if (kDebugMode) const _DebugPlatform(),
              const Text('Create Studio', style: AppText.title),
              const SizedBox(height: 14),
              Seg(
                labels: const ['Make Wallpaper', 'Make GIF', 'Depth'],
                index: _mode,
                onChanged: (i) => setState(() => _mode = i),
              ),
              const SizedBox(height: 18),
              if (depthMode)
                _DepthCard(onTap: () {
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const DepthEditorScreen()));
                })
              else if (gifMode)
                _GifCard(onTap: () {
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const GifEditorScreen()));
                })
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _CreateCard(video: true, onTap: () => _openPicker(context, true))),
                    const SizedBox(width: 14),
                    Expanded(child: _CreateCard(video: false, onTap: () => _openPicker(context, false))),
                  ],
                ),
              const SizedBox(height: 14),
              if (!gifMode && !depthMode)
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
                  Text(gifMode ? 'Recent GIFs' : 'Recent', style: AppText.h2),
                  const Spacer(),
                  if (studio.library.isNotEmpty)
                    GestureDetector(
                      onTap: () => studio.setTab(2),
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
              if (recent.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    gifMode
                        ? 'GIFs you make show up here and in My Work.'
                        : 'Wallpapers you make show up here and in My Work.',
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
                        child: i < recent.length
                            ? _RecentTile(
                                item: recent[i],
                                onTap: () => gifMode
                                    ? Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => WorkViewer(item: recent[i])))
                                    : openWorkForEdit(context, recent[i]))
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

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.item, required this.onTap});

  final SavedTheme item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                  WorkThumb(item, cacheWidth: 240),
                  Positioned(
                      left: 4,
                      top: 4,
                      child: Pill(item.isGif ? 'GIF' : (item.kind == SavedTheme.live ? 'LIVE' : 'STILL'),
                          live: item.kind == SavedTheme.live)),
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

class _GifCard extends StatelessWidget {
  const _GifCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        height: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE7E2F8), Color(0xFFF4F2FB)],
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: Color(0xFF14111F),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.gif_box_outlined, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('New GIF',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text('Pick videos, choose the frames, crop and join them',
                          style: AppText.small.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
                    child: SizedBox(
                      width: double.infinity,
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


class _DepthCard extends StatelessWidget {
  const _DepthCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: const Row(
          children: [
            Icon(Icons.threed_rotation_rounded, size: 34, color: AppColors.pri),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Depth wallpaper', style: AppText.h2),
                  SizedBox(height: 4),
                  Text(
                    'Layers that move when you tilt the phone: Moon in a window, Earth in space, or your own photos.',
                    style: AppText.small,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.sub),
          ],
        ),
      ),
    );
  }
}
