import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Pictures (vectors, illustrations, frames, photos) kept in the GIF studio so they can be
/// used again as the backdrop around a framed video. They stay until the user removes them.
class GifArt {
  static Future<Directory> dir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/art').create(recursive: true);
  }

  /// Saved pictures, newest first.
  static Future<List<File>> list() async {
    final d = await dir();
    final files = <File>[];
    await for (final e in d.list()) {
      if (e is File) files.add(e);
    }
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  /// Copies [src] into the art folder and returns the stored path.
  static Future<String> add(String src) async {
    final d = await dir();
    final name = src.split('/').last;
    final ext = name.contains('.') ? name.split('.').last : 'jpg';
    final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final dest = '${d.path}/art_$safe.$ext';
    final f = File(dest);
    if (!await f.exists()) await File(src).copy(dest);
    return dest;
  }

  static Future<void> remove(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
