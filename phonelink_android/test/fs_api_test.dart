import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:phonelink_android/fs_api.dart';
import 'package:phonelink_android/secure_transport.dart';
// ignore: avoid_relative_lib_imports
import '../../phonelink_desktop/lib/local_identity.dart';

void main() {
  late Directory root;
  late HttpServer server;
  late HttpClient client;
  late String address;
  final token = newSecret();
  late LocalIdentity identity;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('phonelink-fs-test-');
    identity = await LocalIdentity.load(
      Directory('${root.path}/.keys'),
      'test',
    );
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      identity.context,
    );
    server.listen((request) => serveFs(request, root.path, token));
    address = '127.0.0.1:${server.port}';
    client = pinnedClient(identity.pin);
  });
  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  test(
    'Authenticated upload streams a file to the requested phone folder',
    () async {
      final source = File('${root.path}/source.txt');
      await source.writeAsString('local transfer content');
      final remote = RemoteFs(address, token, pin: identity.pin);
      await remote.upload(source, '/Download/PhoneLink/received.txt');
      final target = File('${root.path}/Download/PhoneLink/received.txt');
      expect(await target.readAsString(), 'local transfer content');
      final entries = await remote.list('/Download/PhoneLink');
      expect(entries.single.name, 'received.txt');
    },
  );

  test('Recent images skip hidden entries and sort newest first', () async {
    final folder = await Directory(
      '${root.path}/DCIM/Camera',
    ).create(recursive: true);
    final bytes = img.encodeJpg(img.Image(width: 640, height: 320));
    final older = File('${folder.path}/older.jpg');
    final newer = File('${folder.path}/newer.jpg');
    await older.writeAsBytes(bytes);
    await newer.writeAsBytes(bytes);
    await older.setLastModified(DateTime(2026, 1, 1));
    await newer.setLastModified(DateTime(2026, 1, 2));
    await File('${folder.path}/.hidden.jpg').writeAsBytes(bytes);
    await Directory('${folder.path}/.private').create();
    await File('${folder.path}/.private/hidden.jpg').writeAsBytes(bytes);
    final request = await client.getUrl(
      secureEndpoint(address, '/recent-images'),
    );
    request.headers.set('x-token', token);
    final response = await request.close();
    expect(response.statusCode, 200);
    final images = jsonDecode(await utf8.decoder.bind(response).join()) as List;
    expect(images.map((entry) => entry['name']), ['newer.jpg', 'older.jpg']);
    final thumbnailRequest = await client.getUrl(
      secureEndpoint(
        address,
        '/thumbnail',
        query: {'path': images.first['path'] as String},
      ),
    );
    thumbnailRequest.headers.set('x-token', token);
    final thumbnail = await thumbnailRequest.close();
    expect(thumbnail.statusCode, 200);
    final thumbnailBytes = await thumbnail.fold<List<int>>(
      [],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    final decoded = img.decodeJpg(Uint8List.fromList(thumbnailBytes));
    expect(decoded?.width, 480);
    expect(decoded?.height, 240);
  });

  test(
    'Recent images page past 48 entries and include new images on refresh',
    () async {
      final folder = await Directory('${root.path}/Pictures').create();
      for (var i = 0; i < 72; i++) {
        final file = File('${folder.path}/photo-$i.jpg');
        await file.writeAsString('metadata fixture');
        await file.setLastModified(
          DateTime(2026, 1, 1).add(Duration(minutes: i)),
        );
      }
      Future<List<dynamic>> page(int offset) async {
        final request = await client.getUrl(
          secureEndpoint(
            address,
            '/recent-images',
            query: {'offset': '$offset', 'limit': '64'},
          ),
        );
        request.headers.set('x-token', token);
        final response = await request.close();
        return jsonDecode(await utf8.decoder.bind(response).join()) as List;
      }

      final first = await page(0);
      final second = await page(64);
      expect(first.length, 64);
      expect(second.length, 8);
      expect(
        {
          ...first.map((e) => e['path']),
          ...second.map((e) => e['path']),
        }.length,
        72,
      );
      final newest = File('${folder.path}/new-photo.jpg');
      await newest.writeAsString('new metadata fixture');
      await newest.setLastModified(DateTime(2026, 2, 1));
      expect((await page(0)).first['name'], 'new-photo.jpg');
    },
  );

  test('Media endpoints reject requests without the pairing token', () async {
    for (final endpoint in ['/recent-images', '/thumbnail']) {
      final response = await (await client.getUrl(
        secureEndpoint(address, endpoint),
      )).close();
      expect(response.statusCode, HttpStatus.unauthorized);
      await response.drain();
    }
  });
}
