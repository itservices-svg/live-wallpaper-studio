import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/scenes.dart';
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

  void _openRecent(BuildContext context, RecentItem r) {
    studio.loadScene(r.sceneIndex, name: r.name, video: r.live);
    if (r.live) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MotionEditorScreen()));
    } else {
      goAfterEdit(context, fromVideo: false);
    }
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
                  Text(recents.length.toString().padLeft(2, '0'), style: AppText.mono),
                  const Spacer(),
                  const Text('See All',
                      style: TextStyle(
                          color: AppColors.pri, fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < recents.length; i++) ...[
                    if (i > 0) const SizedBox(width: 9),
                    Expanded(
                      child: _RecentTile(item: recents[i], onTap: () => _openRecent(context, recents[i])),
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
          height: 262,
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
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(video ? 'Trim & loop into a Live Photo' : 'Crop to Lock or Home',
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
  const _RecentTile({required this.item, required this.onTap});

  final RecentItem item;
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
                  SceneView(scene: scenes[item.sceneIndex]),
                  Positioned(left: 4, top: 4, child: Pill(item.live ? 'LIVE' : 'STILL', live: item.live)),
                  if (item.duration.isNotEmpty)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Text(item.duration,
                          style: AppText.mono.copyWith(fontSize: 9, color: Colors.white)),
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
          Text(item.ago, style: AppText.small.copyWith(fontSize: 10)),
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
