import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';

import '../data/scenes.dart';
import '../state/studio_state.dart';
import 'scene_view.dart';

/// Small square-ish thumbnail for grids and lists (sample scene or real asset).
class MediaThumb extends StatelessWidget {
  const MediaThumb(this.item, {super.key});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final a = item.asset;
    if (a == null) return SceneView(scene: scenes[item.sceneIndex % scenes.length]);
    return SizedBox.expand(
      child: AssetEntityImage(
        a,
        isOriginal: false,
        thumbnailSize: const ThumbnailSize.square(300),
        fit: BoxFit.cover,
      ),
    );
  }
}

/// The still of the current media: photo, video key frame, or sample scene.
/// This is what the Home screen and the resting Lock screen use.
class StillBackdrop extends StatelessWidget {
  const StillBackdrop({super.key, required this.state});

  final StudioState state;

  @override
  Widget build(BuildContext context) {
    final m = state.media;
    final a = m.asset;
    if (a == null) return SceneView(scene: state.scene);
    final key = state.keyStill;
    if (m.isVideo && key != null) {
      return SizedBox.expand(
        child: Image.memory(key, fit: BoxFit.cover, gaplessPlayback: true),
      );
    }
    return SizedBox.expand(
      child: AssetEntityImage(
        a,
        isOriginal: false,
        thumbnailSize: const ThumbnailSize(1080, 1920),
        fit: BoxFit.cover,
      ),
    );
  }
}

/// The moving version. Real videos play through [VideoPlayer] when [showVideo]
/// is true; sample scenes animate their waves when [animate] is true.
class LiveBackdrop extends StatelessWidget {
  const LiveBackdrop({
    super.key,
    required this.state,
    this.showVideo = true,
    this.animate = false,
  });

  final StudioState state;
  final bool showVideo;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final m = state.media;
    if (m.asset == null) return SceneView(scene: state.scene, animate: animate);
    final c = state.video;
    if (m.isVideo && showVideo && state.videoReady && c != null) {
      final size = c.value.size;
      return ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(c),
            ),
          ),
        ),
      );
    }
    return StillBackdrop(state: state);
  }
}
