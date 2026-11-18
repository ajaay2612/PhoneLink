import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'secure_transport.dart';

import 'package:path/path.dart' as p;

class FEntry {
  FEntry(this.name, this.isDir, this.size);
  final String name;
  final bool isDir;
  final int size;
}

class RemoteImage {
  RemoteImage(this.name, this.path, this.size, this.modified);
  final String name, path;
  final int size, modified;
}

String fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1048576) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1073741824).toStringAsFixed(2)} GB';
}

/// Client for the other device's file server.
class RemoteFs {
  RemoteFs(this.hostPort, this.token, {this.onTransfer, this.pin = ''});
  final void Function(bool sent, String name)? onTransfer;
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

  Uri imageUri(String path, {bool thumbnail = false, String? version}) =>
      secureEndpoint(
        hostPort,
        thumbnail ? '/thumbnail' : '/file',
        query: {'path': path, 'v': ?version},
      );

  Future<List<RemoteImage>> recentImages({
    int offset = 0,
    int limit = 64,
  }) async {
    final req = await _c.getUrl(
      secureEndpoint(
        hostPort,
        '/recent-images',
        query: {'offset': '$offset', 'limit': '$limit'},
      ),
    );
    final res = await _send(req);
    if (res.statusCode == HttpStatus.notFound) {
      await res.drain();
      throw Exception('Restart the updated phone app to enable recent images.');
    }
    await _check(res);
    final list = jsonDecode(await utf8.decoder.bind(res).join()) as List;
    return [
      for (final item in list)
        RemoteImage(
          item['name'] as String,
          item['path'] as String,
          item['size'] as int,
          item['modified'] as int,
        ),
    ];
  }

  static final _thumbnails = <String, Uint8List>{};
  Future<Uint8List> imageBytes(
    String path, {
    bool thumbnail = true,
    String? version,
  }) async {
    final uri = imageUri(path, thumbnail: thumbnail, version: version);
    final cacheKey = '$pin:$uri';
    if (thumbnail && _thumbnails.containsKey(cacheKey)) {
      return _thumbnails[cacheKey]!;
    }
    final request = await _c.getUrl(uri);
    final response = await _send(request);
    await _check(response);
    final maximum = thumbnail ? 2 * 1024 * 1024 : 40 * 1024 * 1024;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maximum) {
        throw const FormatException('Image is too large to preview');
      }
      bytes.add(chunk);
    }
    final result = bytes.takeBytes();
    if (thumbnail) {
      if (_thumbnails.length >= 64) _thumbnails.remove(_thumbnails.keys.first);
      _thumbnails[cacheKey] = result;
    }
    return result;
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
    onTransfer?.call(false, p.posix.basename(path));
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
    onTransfer?.call(true, p.basename(src.path));
  }
}

/// Serves the authenticated shared root on the app's TLS server. Closes the response itself.
Future<void> serveFs(
  HttpRequest req,
  String root,
  String token, {
  void Function(bool sent, String name)? onTransfer,
  List<String> blocked = const [],
}) async {
  bool? sent;
  String? transferName;
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

    if (req.method == 'GET' && req.uri.path == '/list') {
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
      sent = true;
      transferName = p.basename(full);
    } else if (req.method == 'PUT' && req.uri.path == '/file') {
      await receiveFile(req, full);
      sent = false;
      transferName = p.basename(full);
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
      if (sent != null && transferName != null) {
        onTransfer?.call(sent, transferName);
      }
    } catch (_) {}
  }
}
