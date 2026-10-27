import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A theme the user finished and applied. Stored as JSON in app storage.
class SavedTheme {
  SavedTheme({
    required this.id,
    required this.assetId,
    required this.name,
    required this.isVideo,
    required this.duration,
    required this.createdMs,
    this.blur = 24,
    this.dim = 32,
    this.tint = 68,
    this.tintIdx = 0,
    this.start = 0,
    this.end = 3,
    this.key = 1.5,
    this.zoom = 1,
    this.panX = 0,
    this.panY = 0,
  });

  final String id;
  final String assetId;
  final String name;
  final bool isVideo;
  final String duration;
  final int createdMs;
  final double blur, dim, tint;
  final int tintIdx;
  final double start, end, key;
  final double zoom, panX, panY;

  Map<String, Object?> toJson() => {
        'id': id,
        'assetId': assetId,
        'name': name,
        'isVideo': isVideo,
        'duration': duration,
        'createdMs': createdMs,
        'blur': blur,
        'dim': dim,
        'tint': tint,
        'tintIdx': tintIdx,
        'start': start,
        'end': end,
        'key': key,
        'zoom': zoom,
        'panX': panX,
        'panY': panY,
      };

  static SavedTheme? fromJson(Object? o) {
    if (o is! Map) return null;
    double d(String k, double def) => (o[k] is num) ? (o[k] as num).toDouble() : def;
    final id = o['id'], asset = o['assetId'];
    if (id is! String || asset is! String) return null;
    return SavedTheme(
      id: id,
      assetId: asset,
      name: (o['name'] as String?) ?? 'Theme',
      isVideo: o['isVideo'] == true,
      duration: (o['duration'] as String?) ?? '',
      createdMs: (o['createdMs'] as num?)?.toInt() ?? 0,
      blur: d('blur', 24),
      dim: d('dim', 32),
      tint: d('tint', 68),
      tintIdx: (o['tintIdx'] as num?)?.toInt() ?? 0,
      start: d('start', 0),
      end: d('end', 3),
      key: d('key', 1.5),
      zoom: d('zoom', 1),
      panX: d('panX', 0),
      panY: d('panY', 0),
    );
  }

  String get ago {
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(createdMs));
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final d = DateTime.fromMillisecondsSinceEpoch(createdMs);
    return '${d.day}/${d.month}/${d.year}';
  }
}

class LibraryStore {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/themes.json');
  }

  static Future<List<SavedTheme>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final data = jsonDecode(await f.readAsString());
      if (data is! List) return [];
      return data.map(SavedTheme.fromJson).whereType<SavedTheme>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<SavedTheme> items) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode([for (final t in items) t.toJson()]));
    } catch (_) {}
  }
}
