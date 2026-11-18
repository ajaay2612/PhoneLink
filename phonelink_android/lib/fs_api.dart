import 'dart:convert';
import 'dart:io';
import 'secure_transport.dart';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import 'package:path/path.dart' as p;

class FEntry {
  FEntry(this.name, this.isDir, this.size);
  final String name;
  final bool isDir;
  final int size;
}

String fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1048576) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1073741824).toStringAsFixed(2)} GB';
}

/// Client for the other device's file server.
class RemoteFs {
  RemoteFs(this.hostPort, this.token, {this.pin = ''});
  final String hostPort, token;
  final String pin;
  HttpClient get _c => pinnedClient(pin);

  Future<HttpClientResponse> _send(HttpClientRequest req) async {
    req.followRedirects = false;
    req.headers.set('x-token', token);
    return req.close();
  }

  Future<void> _check(HttpClientResponse res) async {
    if (res.statusCode == 200) return;
    final body = await utf8.decoder.bind(res).join();
    throw Exception('HTTP ${res.statusCode} $body');
  }

  Future<List<FEntry>> list(String path) async {
    final req = await _c.getUrl(
      secureEndpoint(hostPort, '/list', query: {'path': path}),
    );
    final res = await _send(req);
    await _check(res);
    final j = jsonDecode(await utf8.decoder.bind(res).join()) as List;
    return [for (final e in j) FEntry(e['name'], e['dir'], e['size'])];
  }

  Future<void> download(String path, File dest) async {
    final req = await _c.getUrl(
      secureEndpoint(hostPort, '/file', query: {'path': path}),
    );
    final res = await _send(req);
    await _check(res);
    await dest.parent.create(recursive: true);
    final sink = dest.openWrite();
    await sink.addStream(res);
    await sink.close();
  }

  Future<void> upload(File src, String destPath) async {
    final req = await _c.putUrl(
      secureEndpoint(hostPort, '/file', query: {'path': destPath}),
    );
    req.followRedirects = false;
    req.headers.set('x-token', token);
    req.contentLength = await src.length();
    await req.addStream(src.openRead());
    final res = await req.close();
    await _check(res);
    await res.drain();
  }
}

const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'};
final _thumbnailCache = <String, Uint8List>{};

/// Recent pictures from the phone's user-visible photo and download folders.
Future<List<Map<String, dynamic>>> recentPhoneImages(
  String root, {
  int offset = 0,
  int? limit,
}) async {
  final folders = <Directory>[
    for (final relative in [
      'DCIM',
      'Pictures',
      'Download',
      'WhatsApp/Media/WhatsApp Images',
      'Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images',
      'Telegram/Telegram Images',
    ])
      Directory(p.join(root, relative)),
  ];
  final images = <Map<String, dynamic>>[];
  while (folders.isNotEmpty) {
    final directory = folders.removeLast();
    try {
      await for (final entry in directory.list(followLinks: false)) {
        if (p.basename(entry.path).startsWith('.')) continue;
        if (entry is Directory) {
          folders.add(entry);
        } else if (entry is File &&
            _imageExtensions.contains(p.extension(entry.path).toLowerCase())) {
          try {
            final stat = await entry.stat();
            images.add({
              'name': p.basename(entry.path),
              'path': '/${p.relative(entry.path, from: root)}',
              'size': stat.size,
              'modified': stat.modified.millisecondsSinceEpoch,
            });
          } on FileSystemException {
            /* A picture can be removed during the scan. */
          }
        }
      }
    } on FileSystemException {
      /* Ignore absent or inaccessible media folders. */
    }
  }
  images.sort((a, b) => (b['modified'] as int).compareTo(a['modified'] as int));
  final remaining = images.skip(offset);
  return (limit == null ? remaining : remaining.take(limit)).toList();
}

Future<Uint8List?> _phoneThumbnail(File file) async {
  final stat = await file.stat();
  if (stat.size > 40 * 1024 * 1024) return null;
  final key =
      '${file.path}:${stat.modified.millisecondsSinceEpoch}:${stat.size}';
  if (_thumbnailCache.containsKey(key)) return _thumbnailCache[key];
  final path = file.path;
  final bytes = await Isolate.run(() async {
    final decoded = img.decodeImage(await File(path).readAsBytes());
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    final resized = oriented.width > 480 || oriented.height > 480
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? 480 : null,
            height: oriented.height > oriented.width ? 480 : null,
            interpolation: img.Interpolation.average,
          )
        : oriented;
    return img.encodeJpg(resized, quality: 75);
  });
  if (bytes != null) {
    if (_thumbnailCache.length >= 48) {
      _thumbnailCache.remove(_thumbnailCache.keys.first);
    }
    _thumbnailCache[key] = bytes;
  }
  return bytes;
}

/// Serves the authenticated shared root on the app's TLS server. Closes the response itself.
Future<void> serveFs(
  HttpRequest req,
  String root,
  String token, {
  List<String> blocked = const [],
}) async {
  final res = req.response;
  try {
    res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    res.headers.set('X-Content-Type-Options', 'nosniff');
    if (!authorizedRequest(req, token)) {
      res.statusCode = HttpStatus.unauthorized;
      return;
    }
    final canonicalRoot = await Directory(root).resolveSymbolicLinks();
    final full = await confinedPath(
      canonicalRoot,
      req.uri.queryParameters['path'] ?? '',
      blocked: blocked,
    );

    if (req.method == 'GET' && req.uri.path == '/recent-images') {
      res.headers.contentType = ContentType.json;
      final offset =
          (int.tryParse(req.uri.queryParameters['offset'] ?? '') ?? 0).clamp(
            0,
            1000000,
          );
      final limit = (int.tryParse(req.uri.queryParameters['limit'] ?? '') ?? 64)
          .clamp(1, 200);
      res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      res.write(
        jsonEncode(await recentPhoneImages(root, offset: offset, limit: limit)),
      );
    } else if (req.method == 'GET' && req.uri.path == '/thumbnail') {
      final file = File(full);
      if (!_imageExtensions.contains(p.extension(full).toLowerCase()) ||
          !await file.exists()) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final thumbnail = await _phoneThumbnail(file);
      if (thumbnail == null) {
        res.statusCode = HttpStatus.unsupportedMediaType;
        return;
      }
      res.headers.contentType = ContentType('image', 'jpeg');
      res.contentLength = thumbnail.length;
      res.add(thumbnail);
    } else if (req.method == 'GET' && req.uri.path == '/list') {
      final dir = Directory(full);
      if (!await dir.exists()) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final items = <Map<String, dynamic>>[];
      await for (final e in dir.list(followLinks: false)) {
        try {
          await confinedPath(
            root,
            p.relative(e.path, from: canonicalRoot),
            blocked: blocked,
          );
          final st = await e.stat();
          items.add({
            'name': p.basename(e.path),
            'dir': st.type == FileSystemEntityType.directory,
            'size': st.size,
          });
        } catch (_) {}
      }
      items.sort((a, b) {
        if (a['dir'] != b['dir']) return a['dir'] == true ? -1 : 1;
        return (a['name'] as String).toLowerCase().compareTo(
          (b['name'] as String).toLowerCase(),
        );
      });
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(items));
    } else if (req.method == 'GET' && req.uri.path == '/file') {
      final f = File(full);
      if (!await f.exists()) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      res.contentLength = await f.length();
      await res.addStream(f.openRead());
    } else if (req.method == 'PUT' && req.uri.path == '/file') {
      await receiveFile(req, full);
    } else {
      res.statusCode = HttpStatus.notFound;
    }
  } catch (e) {
    try {
      res.statusCode = e is FileAccessDenied
          ? HttpStatus.forbidden
          : HttpStatus.internalServerError;
      res.write(
        e is FileAccessDenied ? 'Path unavailable' : 'File operation failed',
      );
    } catch (_) {}
  } finally {
    try {
      await res.close();
    } catch (_) {}
  }
}
