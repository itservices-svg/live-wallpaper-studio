import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../config.dart';

/// One Pixabay photo or video.
class PixabayItem {
  const PixabayItem({
    required this.id,
    required this.thumb,
    required this.url,
    required this.isVideo,
    required this.width,
    required this.height,
    required this.user,
    this.seconds = 0,
  });

  final int id;
  final String thumb; // small picture for the grid
  final String url; // large photo, or mp4 for videos
  final bool isVideo;
  final int width;
  final int height;
  final String user;
  final double seconds;
}

class PixabayException implements Exception {
  PixabayException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What the user picked in the filter sheet.
class PixabayFilters {
  const PixabayFilters({this.orientation = 'portrait', this.order = 'popular', this.color = ''});

  final String orientation; // portrait | landscape | all
  final String order; // popular | latest
  final String color; // '' or a Pixabay colour name (photos only)

  PixabayFilters copyWith({String? orientation, String? order, String? color}) => PixabayFilters(
        orientation: orientation ?? this.orientation,
        order: order ?? this.order,
        color: color ?? this.color,
      );

  bool get isDefault => orientation == 'portrait' && order == 'popular' && color.isEmpty;
}

class PixabayPage {
  const PixabayPage(this.items, this.nextPage, this.done);
  final List<PixabayItem> items;
  final int nextPage;
  final bool done;
}

/// Free photos and videos from Pixabay (https://pixabay.com/api/docs/).
class Pixabay {
  static bool get hasKey => kPixabayKey.isNotEmpty;

  static Future<PixabayPage> search({
    required String query,
    required bool video,
    required PixabayFilters filters,
    int page = 1,
  }) async {
    // The video API has no orientation filter, so fetch more and filter here.
    final clientFilter = video && filters.orientation != 'all';
    final out = <PixabayItem>[];
    var p = page;
    var done = false;
    for (var round = 0; round < (clientFilter ? 4 : 1); round++) {
      final res = await _fetch(query, video, filters, p);
      out.addAll(clientFilter
          ? res.items.where((e) => filters.orientation == 'portrait' ? e.height > e.width : e.width >= e.height)
          : res.items);
      p++;
      if (res.raw < res.perPage) {
        done = true;
        break;
      }
      if (out.length >= 12) break;
    }
    return PixabayPage(out, p, done);
  }

  static Future<({List<PixabayItem> items, int raw, int perPage})> _fetch(
      String query, bool video, PixabayFilters f, int page) async {
    if (!hasKey) throw PixabayException('Pixabay key is not set in this build.');
    final perPage = video ? 50 : 30;
    final params = <String, String>{
      'key': kPixabayKey,
      'q': query,
      'page': '$page',
      'per_page': '$perPage',
      'safesearch': 'true',
      'order': f.order,
      if (!video) ...{
        'image_type': 'photo',
        'orientation': switch (f.orientation) {
          'portrait' => 'vertical',
          'landscape' => 'horizontal',
          _ => 'all',
        },
        if (f.orientation == 'portrait') 'min_height': '1000',
        if (f.color.isNotEmpty) 'colors': f.color,
      },
    };
    final uri = Uri.https('pixabay.com', video ? '/api/videos/' : '/api/', params);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 429) throw PixabayException('Too many requests. Try again in a minute.');
      if (res.statusCode != 200) throw PixabayException('Pixabay error (${res.statusCode}).');
      final data = jsonDecode(body) as Map<String, dynamic>;
      final hits = (data['hits'] as List?) ?? const [];
      final out = <PixabayItem>[];
      for (final h in hits) {
        final m = h as Map<String, dynamic>;
        if (video) {
          final v = (m['videos'] as Map?)?.cast<String, dynamic>() ?? const {};
          final pick = (v['medium'] ?? v['large'] ?? v['small'] ?? v['tiny']) as Map?;
          if (pick == null || (pick['url'] as String?)?.isNotEmpty != true) continue;
          final tiny = (v['tiny'] as Map?) ?? pick;
          out.add(PixabayItem(
            id: (m['id'] as num).toInt(),
            thumb: (pick['thumbnail'] ?? tiny['thumbnail'] ?? '') as String,
            url: pick['url'] as String,
            isVideo: true,
            width: (pick['width'] as num?)?.toInt() ?? 0,
            height: (pick['height'] as num?)?.toInt() ?? 0,
            user: (m['user'] as String?) ?? '',
            seconds: (m['duration'] as num?)?.toDouble() ?? 0,
          ));
        } else {
          out.add(PixabayItem(
            id: (m['id'] as num).toInt(),
            thumb: (m['webformatURL'] ?? m['previewURL']) as String,
            url: (m['largeImageURL'] ?? m['webformatURL']) as String,
            isVideo: false,
            width: (m['imageWidth'] as num?)?.toInt() ?? 0,
            height: (m['imageHeight'] as num?)?.toInt() ?? 0,
            user: (m['user'] as String?) ?? '',
          ));
        }
      }
      return (items: out, raw: hits.length, perPage: perPage);
    } on SocketException {
      throw PixabayException('No internet connection.');
    } on HttpException {
      throw PixabayException('Could not reach Pixabay.');
    } finally {
      client.close();
    }
  }

  /// Folder for downloaded sources. They stay until cleaned, so saved work can be re-edited.
  static Future<Directory> dir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/explore').create(recursive: true);
  }

  /// Deletes downloads older than [days] that no saved work refers to.
  static Future<void> cleanup(Set<String> keep, {int days = 3}) async {
    try {
      final d = await dir();
      final cutoff = DateTime.now().subtract(Duration(days: days));
      await for (final e in d.list()) {
        if (e is File && !keep.contains(e.path) && (await e.lastModified()).isBefore(cutoff)) {
          await e.delete();
        }
      }
    } catch (_) {}
  }

  /// Downloads [url] into app storage (not the gallery).
  static Future<File> download(String url, String ext, {int? id}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final d = await dir();
      final file = File('${d.path}/pixabay_${id ?? DateTime.now().millisecondsSinceEpoch}.$ext');
      if (await file.exists() && await file.length() > 0) return file;
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw PixabayException('Download failed (${res.statusCode}).');
      }
      final tmp = File('${file.path}.part');
      await res.pipe(tmp.openWrite());
      return tmp.rename(file.path);
    } on SocketException {
      throw PixabayException('No internet connection.');
    } finally {
      client.close();
    }
  }
}
