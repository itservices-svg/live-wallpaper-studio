import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';


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
  /// Our own small Cloudflare Worker: it holds the AI access, so no key is in the app.
  /// POST {"prompt": "..."} -> image bytes.
  static const _worker = 'https://ai-wallpaper.adeelhashmi485.workers.dev';

  /// Soft per-day limit so a test key is not drained by accident.
  static const dailyLimit = 20;

  static bool get hasKey => true;

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
  /// Returns the saved image file.
  static Future<File> generate(String prompt, {String model = 'zimage'}) async {
    if (await usedToday() >= dailyLimit) {
      throw AiImageException('Daily limit reached ($dailyLimit). Try again tomorrow.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      List<int> bytes = const [];
      for (var attempt = 0; attempt < 2; attempt++) {
        final body = utf8.encode(jsonEncode({'prompt': prompt}));
        final req = await client.postUrl(Uri.parse(_worker));
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        req.contentLength = body.length;
        req.add(body);
        final res = await req.close().timeout(const Duration(seconds: 120),
            onTimeout: () => throw AiImageException('The AI took too long. Try again.'));
        final b = <int>[];
        await for (final c in res) {
          b.addAll(c);
        }
        if (res.statusCode == 200) {
          final ok = b.length > 1000 &&
              ((b[0] == 0x89 && b[1] == 0x50) || (b[0] == 0xFF && b[1] == 0xD8) || (b[0] == 0x52 && b[1] == 0x49));
          if (!ok) throw AiImageException('The AI sent something that is not a picture.');
          bytes = b;
          break;
        }
        final text = utf8.decode(b, allowMalformed: true);
        final short = text.length > 150 ? text.substring(0, 150) : text;
        if ((res.statusCode == 502 || res.statusCode == 500) && attempt == 0) continue;
        if (res.statusCode == 400) {
          throw AiImageException('The prompt was rejected. Try different words.');
        }
        if (res.statusCode == 429) {
          throw AiImageException('Too many requests. Wait a minute and try again.');
        }
        throw AiImageException('The AI service failed (${res.statusCode}). $short');
      }
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
}
