import 'dart:convert';
import 'dart:io';

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
  });

  final int id;
  final String thumb; // small picture for the grid
  final String url; // large photo, or mp4 for videos
  final bool isVideo;
  final int width;
  final int height;
  final String user;
}

class PixabayException implements Exception {
  PixabayException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Free photos and videos from Pixabay (https://pixabay.com/api/docs/).
class Pixabay {
  static bool get hasKey => kPixabayKey.isNotEmpty;

  static Future<List<PixabayItem>> search({
    required String query,
    required bool video,
    int page = 1,
    int perPage = 30,
  }) async {
    if (!hasKey) throw PixabayException('Pixabay key is not set in this build.');
    final params = <String, String>{
      'key': kPixabayKey,
      'q': query,
      'page': '$page',
      'per_page': '$perPage',
      'safesearch': 'true',
      if (!video) ...{
        'image_type': 'photo',
        'orientation': 'vertical',
        'min_height': '1200',
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
      return out;
    } on SocketException {
      throw PixabayException('No internet connection.');
    } on HttpException {
      throw PixabayException('Could not reach Pixabay.');
    } finally {
      client.close();
    }
  }

  /// Downloads [url] to a temp file with the given extension.
  static Future<File> download(String url, String ext) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) throw PixabayException('Download failed (${res.statusCode}).');
      final dir = await Directory.systemTemp.createTemp('pbx_');
      final file = File('${dir.path}/pixabay_${DateTime.now().millisecondsSinceEpoch}.$ext');
      final sink = file.openWrite();
      await res.pipe(sink);
      return file;
    } finally {
      client.close();
    }
  }
}
