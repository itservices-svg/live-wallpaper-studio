import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// A procedural "footage" scene. Real video/photo sources replace these later;
/// until then the sky + sea gradients and animated waves stand in for footage.
class Scene {
  const Scene(this.name, this.sky, this.sea, this.sun);

  final String name;
  final List<Color> sky; // 3 stops, top to bottom
  final List<Color> sea; // 2 stops
  final Color sun;

  /// Five colours "sampled" from the scene, used for tint swatches.
  List<Color> get palette => [sky[0], sky[1], sea[0], sky[2], sea[1]];
}

const scenes = <Scene>[
  Scene('Coastline Dusk', [Color(0xFFF2B27A), Color(0xFFD56A6A), Color(0xFF3B3A6E)],
      [Color(0xFF1F6B73), Color(0xFF0F3B4A)], Color(0xFFFFE2A8)),
  Scene('Golden Hour', [Color(0xFFFFD27A), Color(0xFFF08A3C), Color(0xFF7A3B4A)],
      [Color(0xFF2B6A68), Color(0xFF12384A)], Color(0xFFFFF1C2)),
  Scene('Night Surf', [Color(0xFF2A2F5A), Color(0xFF161A38), Color(0xFF0A0C1E)],
      [Color(0xFF1B4A63), Color(0xFF0B2233)], Color(0xFFCFD8FF)),
  Scene('Yellow Tram', [Color(0xFFFFE08A), Color(0xFFF2B84A), Color(0xFFC97B2B)],
      [Color(0xFF8A5A2B), Color(0xFF5A3A1C)], Color(0xFFFFFFFF)),
  Scene('Miradouro Sunset', [Color(0xFFF7C59F), Color(0xFFEE8F6A), Color(0xFF8B4A6E)],
      [Color(0xFF6A4A62), Color(0xFF3A2A46)], Color(0xFFFFE9C4)),
  Scene('Tiled Facades', [Color(0xFFCFE3EE), Color(0xFF9FC3D6), Color(0xFF5E8FAE)],
      [Color(0xFF2E5A78), Color(0xFF1B3A52)], Color(0xFFFFFFFF)),
  Scene('River at Night', [Color(0xFF3A2A5E), Color(0xFF1C1840), Color(0xFF0C0A22)],
      [Color(0xFF2A3A7A), Color(0xFF121A44)], Color(0xFF9AA8FF)),
  Scene('Neon Cafe', [Color(0xFFFF4D8D), Color(0xFF7A2AA8), Color(0xFF1C1245)],
      [Color(0xFF1A1A3A), Color(0xFF0C0C22)], Color(0xFFFFB3D9)),
  Scene('Seagull Sky', [Color(0xFFBFE3F5), Color(0xFF8FC6EA), Color(0xFF4F8FC4)],
      [Color(0xFF2D6EA0), Color(0xFF174A74)], Color(0xFFFFFFFF)),
  Scene('Kyoto Rain', [Color(0xFF9FB3A8), Color(0xFF6F8A82), Color(0xFF2F4A46)],
      [Color(0xFF263F3C), Color(0xFF142523)], Color(0xFFDFF0E6)),
  Scene('Espresso Pour', [Color(0xFFD9B48A), Color(0xFF8A5A3A), Color(0xFF3A2218)],
      [Color(0xFF2A1A12), Color(0xFF150C08)], Color(0xFFFFD9A8)),
  Scene('Fern Study', [Color(0xFFA8C98A), Color(0xFF5F8F4A), Color(0xFF1F3A22)],
      [Color(0xFF14301C), Color(0xFF0A1C10)], Color(0xFFE6FFC9)),
];

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// 0:07, 1:06
String fmtDur(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// One pickable item: either a sample scene or a real gallery asset.
class MediaItem {
  const MediaItem(this.name, this.duration, this.sceneIndex, {this.asset});

  /// Real gallery item. The name is a date label until the user renames the theme.
  factory MediaItem.fromAsset(AssetEntity a) {
    final video = a.type == AssetType.video;
    final d = a.createDateTime;
    return MediaItem(
      '${video ? 'Clip' : 'Photo'} ${d.day} ${_months[d.month - 1]}',
      video ? fmtDur(a.videoDuration) : '',
      0,
      asset: a,
    );
  }

  final String name;
  final String duration; // empty for photos
  final int sceneIndex; // only used by sample items
  final AssetEntity? asset; // null for sample items

  bool get isReal => asset != null;

  bool get isVideo => asset != null ? asset!.type == AssetType.video : duration.isNotEmpty;

  double get seconds => asset == null ? 0 : asset!.videoDuration.inMilliseconds / 1000.0;

  String get detail {
    final a = asset;
    if (a == null) return isVideo ? '00:14.08 · 4K · 60 FPS' : '4032×3024 · HEIC';
    final dims = '${a.width}×${a.height}';
    return isVideo ? '$dims · ${fmtDur(a.videoDuration)}' : dims;
  }
}

class MediaGroup {
  const MediaGroup(this.title, this.items);
  final String title;
  final List<MediaItem> items;
}

const videoGroups = <MediaGroup>[
  MediaGroup('TODAY · OCEAN BEACH', [
    MediaItem('Surf Break', '0:38', 0),
    MediaItem('Golden hour, Ocean Beach', '0:14', 1),
    MediaItem('Night Spark', '1:06', 2),
  ]),
  MediaGroup('SAT, 14 JUN · LISBON', [
    MediaItem('Yellow Tram', '0:09', 3),
    MediaItem('Miradouro Sunset', '0:27', 4),
    MediaItem('Tiled Facades', '0:05', 5),
    MediaItem('River at Night', '0:11', 6),
    MediaItem('Neon Cafe Days', '0:16', 7),
    MediaItem('Seagulls in Flight', '0:01', 8),
    MediaItem('Alley Light', '0:22', 9),
    MediaItem('Espresso Pour', '0:07', 10),
    MediaItem('Rooftops', '0:19', 0),
  ]),
];

final photoGroups = <MediaGroup>[
  MediaGroup('RECENTS', [
    for (var i = 0; i < scenes.length; i++) MediaItem(scenes[i].name, '', i),
  ]),
];
