import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// One saved item in "My Work": a wallpaper (from a photo), a live wallpaper
/// (from a video) or a GIF. Files live in app storage; the list is a JSON file.
class SavedTheme {
  SavedTheme({
    required this.id,
    required this.kind,
    required this.assetId,
    required this.name,
    required this.isVideo,
    required this.duration,
    required this.createdMs,
    required this.file,
    this.thumb,
    this.blur = 0,
    this.start = 0,
    this.end = 3,
    this.key = 1.5,
    this.zoom = 1,
    this.panX = 0,
    this.panY = 0,
    this.proj,
  });

  static const wallpaper = 'wallpaper';
  static const live = 'live';
  static const gif = 'gif';

  final String id;
  final String kind; // wallpaper | live | gif
  final String assetId; // gallery source, used by Edit
  final String name;
  final bool isVideo;
  final String duration;
  final int createdMs;
  final String file; // png / mp4 / gif in app storage
  final String? thumb; // jpg poster for live items
  final double blur; // 0 = no blur (photos only)
  final double start, end, key;
  final double zoom, panX, panY;
  final String? proj; // GIF project (clips + settings) as JSON, so a GIF can be edited again

  bool get isGif => kind == gif;
  bool get canEdit => kind != gif && assetId.isNotEmpty;
  bool get canEditGif => kind == gif && proj != null && proj!.isNotEmpty;

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind,
        'assetId': assetId,
        'name': name,
        'isVideo': isVideo,
        'duration': duration,
        'createdMs': createdMs,
        'file': file,
        'thumb': thumb,
        'blur': blur,
        'start': start,
        'end': end,
        'key': key,
        'zoom': zoom,
        'panX': panX,
        'panY': panY,
        'proj': proj,
      };

  static SavedTheme? fromJson(Object? o) {
    if (o is! Map) return null;
    double d(String k, double def) => (o[k] is num) ? (o[k] as num).toDouble() : def;
    final id = o['id'], file = o['file'];
    if (id is! String || file is! String) return null; // older entries had no files
    return SavedTheme(
      id: id,
      kind: (o['kind'] as String?) ?? wallpaper,
      assetId: (o['assetId'] as String?) ?? '',
      name: (o['name'] as String?) ?? 'Untitled',
      isVideo: o['isVideo'] == true,
      duration: (o['duration'] as String?) ?? '',
      createdMs: (o['createdMs'] as num?)?.toInt() ?? 0,
      file: file,
      thumb: o['thumb'] as String?,
      blur: d('blur', 0),
      start: d('start', 0),
      end: d('end', 3),
      key: d('key', 1.5),
      zoom: d('zoom', 1),
      panX: d('panX', 0),
      panY: d('panY', 0),
      proj: o['proj'] as String?,
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
  static Future<Directory> workDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/work').create(recursive: true);
  }

  /// Copies [src] into app storage as "<id>.<ext>" and returns the new path.
  static Future<String> copyIn(String src, String id, String ext) async {
    final dir = await workDir();
    final dest = '${dir.path}/$id.$ext';
    await File(src).copy(dest);
    return dest;
  }

  static Future<String> writeBytes(List<int> bytes, String id, String ext) async {
    final dir = await workDir();
    final dest = '${dir.path}/$id.$ext';
    await File(dest).writeAsBytes(bytes, flush: true);
    return dest;
  }

  static Future<void> deleteFiles(SavedTheme t) async {
    for (final p in [t.file, t.thumb]) {
      if (p == null) continue;
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/work.json');
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
