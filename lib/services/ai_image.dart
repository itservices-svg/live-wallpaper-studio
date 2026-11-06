import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../config.dart';

class AiImageException implements Exception {
  AiImageException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Text -> image through the API.market "cheap-ai-image" product.
/// All provider details live here, so switching provider (or a backend) only
/// touches this file.
class AiImage {
  static const _host = 'https://prod.api.market';
  // The docs page shows a "mcp" base path, but API.market's usual form is
  // /api/v1/<store>/<product>/... so try the likely ones in turn on a 404/405.
  static const _bases = <String>[
    '$_host/api/v1/aqua-ai/cheap-ai-image/v1',
    '$_host/api/v1/aqua-ai/cheap-ai-image',
    '$_host/api/mcp/aqua-ai/cheap-ai-image/v1',
    '$_host/api/mcp/aqua-ai/cheap-ai-image',
  ];
  static String? _good; // the base that worked last time
  static String _lastBase = _bases.first;

  /// Soft per-day limit so a test key is not drained by accident.
  static const dailyLimit = 20;

  static bool get hasKey => kAiImageKey.isNotEmpty;

  static Future<Directory> dir() async {
    final b = await getApplicationSupportDirectory();
    return Directory('${b.path}/ai').create(recursive: true);
  }

  // ---- daily counter -------------------------------------------------------
  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  static Future<int> usedToday() async {
    try {
      final f = File('${(await dir()).path}/usage.json');
      if (!await f.exists()) return 0;
      final o = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return o['day'] == _today() ? (o['n'] as num).toInt() : 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _bump() async {
    try {
      final n = await usedToday() + 1;
      await File('${(await dir()).path}/usage.json')
          .writeAsString(jsonEncode({'day': _today(), 'n': n}));
    } catch (_) {}
  }

  // ---- history -------------------------------------------------------------
  static Future<List<File>> history() async {
    try {
      final d = await dir();
      final files = d
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('/ai_') && f.path.endsWith('.png'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      return files;
    } catch (_) {
      return [];
    }
  }

  static Future<void> remove(File f) async {
    try {
      await f.delete();
    } catch (_) {}
  }

  // ---- generate ------------------------------------------------------------
  /// [model]: 'zimage' (fast) or 'gptimage-2' (better). Returns the saved PNG.
  static Future<File> generate(String prompt, {String model = 'zimage'}) async {
    if (!hasKey) {
      throw AiImageException('This build has no AI key. Add the AI_IMAGE_KEY secret and rebuild.');
    }
    if (await usedToday() >= dailyLimit) {
      throw AiImageException('Daily limit reached ($dailyLimit). Try again tomorrow.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final url = await _request(client, prompt, model);
      final bytes = await _fetch(client, url);
      final d = await dir();
      final f = File('${d.path}/ai_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(bytes);
      await _bump();
      return f;
    } on SocketException {
      throw AiImageException('No internet connection.');
    } on HandshakeException {
      throw AiImageException('Secure connection failed. Check your internet.');
    } finally {
      client.close();
    }
  }

  static void _auth(HttpClientRequest r) {
    r.headers.set('Authorization', 'Bearer $kAiImageKey');
    r.headers.set('x-api-market-key', kAiImageKey);
  }

  static Future<String> _request(HttpClient client, String prompt, String model) async {
    final bases = [if (_good != null) _good!, ..._bases.where((b) => b != _good)];
    var notFound = 0;
    for (final base in bases) {
      for (var attempt = 0; attempt < 2; attempt++) {
        final req = await client.postUrl(Uri.parse('$base/images/generations'));
        _auth(req);
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode({'model': model, 'prompt': prompt, 'ratio': 'portrait'})));
        final res = await req.close().timeout(const Duration(seconds: 120),
            onTimeout: () => throw AiImageException('The AI took too long. Try again.'));
        final body = await res.transform(utf8.decoder).join();
        Map<String, dynamic> o = {};
        try {
          o = jsonDecode(body) as Map<String, dynamic>;
        } catch (_) {}
        final code = res.statusCode;
        if (code == 200 && o['success'] != false && o['url'] is String) {
          _good = base;
          _lastBase = base;
          return o['url'] as String;
        }
        if (code == 404 || code == 405) {
          notFound++;
          break; // wrong address: next base
        }
        if ((code == 502 || code == 504 || code == 500) && attempt == 0) continue; // one retry
        final err = (o['error'] ?? o['detail'] ?? '').toString();
        switch (code) {
          case 400:
            throw AiImageException(err.toLowerCase().contains('safety')
                ? 'This prompt was blocked by the safety filter. Try different words.'
                : 'The request was rejected${err.isEmpty ? '' : ': $err'}');
          case 401:
            throw AiImageException('The AI key is invalid or missing.');
          case 402:
            throw AiImageException('The AI credit is finished.');
          case 403:
            throw AiImageException('This key is not allowed to use the service.');
          case 429:
            throw AiImageException('Too many requests. Wait a minute and try again.');
          default:
            final short = body.length > 120 ? body.substring(0, 120) : body;
            throw AiImageException('The AI service failed ($code). $short');
        }
      }
    }
    throw AiImageException(
        'The AI address was not found (404 on $notFound addresses). The service may have changed; send this message to the developer.');
  }

  /// The API returns a path like /generation/img_x.png. The host is not in the
  /// docs, so try the likely prefixes until one returns an image.
  static Future<List<int>> _fetch(HttpClient client, String url) async {
    final candidates = url.startsWith('http')
        ? [url]
        : ['$_host$url', '$_lastBase$url'];
    for (final c in candidates) {
      try {
        final req = await client.getUrl(Uri.parse(c));
        _auth(req);
        final res = await req.close().timeout(const Duration(seconds: 60));
        if (res.statusCode != 200) {
          await res.drain<void>();
          continue;
        }
        final b = <int>[];
        await for (final chunk in res) {
          b.addAll(chunk);
        }
        // PNG, JPEG or WEBP magic bytes.
        final ok = b.length > 1000 &&
            ((b[0] == 0x89 && b[1] == 0x50) ||
                (b[0] == 0xFF && b[1] == 0xD8) ||
                (b[0] == 0x52 && b[1] == 0x49));
        if (ok) return b;
      } catch (_) {}
    }
    throw AiImageException('The image was made but could not be downloaded. Try again.');
  }
}
