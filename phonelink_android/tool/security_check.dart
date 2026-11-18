// ignore_for_file: avoid_relative_lib_imports
// Pure-Dart local transport checks. Does not build or launch Flutter/Android apps.
import 'dart:convert';
import 'dart:io';
import '../lib/fs_api.dart' as phone;
import '../../phonelink_desktop/lib/fs_api.dart' as desktop;
import '../../phonelink_desktop/lib/local_identity.dart';
import '../../phonelink_desktop/lib/secure_transport.dart' as secure;

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final temporary = await Directory.systemTemp.createTemp(
    'phonelink-security-',
  );
  final home = await Directory('${temporary.path}/home').create();
  final protected = await Directory(
    '${home.path}/.config/phonelink',
  ).create(recursive: true);
  final outside = await Directory('${temporary.path}/outside').create();
  final desktopIdentity = await LocalIdentity.load(
    Directory('${temporary.path}/keys'),
    'desktop',
  );
  final phoneIdentity = await LocalIdentity.load(
    Directory('${temporary.path}/keys'),
    'phone',
  );
  final wrongIdentity = await LocalIdentity.load(
    Directory('${temporary.path}/keys'),
    'wrong',
  );
  final token = secure.newSecret();
  final servers = <HttpServer>[];
  try {
    await File(
      '${home.path}/normal.txt',
    ).writeAsString('home folder remains shared');
    await File('${home.path}/.hidden-note').writeAsString('hidden home file');
    await File(
      '${protected.path}/desktop.key',
    ).writeAsString('private identity');
    await File('${outside.path}/secret.txt').writeAsString('outside');
    await Link('${home.path}/escape').create(outside.path);
    await Link(
      '${home.path}/escaped-file',
    ).create('${outside.path}/secret.txt');

    final pc = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      desktopIdentity.context,
    );
    servers.add(pc);
    pc.listen(
      (request) =>
          desktop.serveFs(request, home.path, token, blocked: [protected.path]),
      onError: (_) {},
    );
    final mobile = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      phoneIdentity.context,
    );
    servers.add(mobile);
    mobile.listen(
      (request) => phone.serveFs(request, home.path, token),
      onError: (_) {},
    );
    final pcHost = '127.0.0.1:${pc.port}';
    final phoneHost = '127.0.0.1:${mobile.port}';
    final client = secure.pinnedClient(desktopIdentity.pin);
    Future<HttpClientResponse> get(
      String path, {
      String? credential,
      String? origin,
    }) async {
      final request = await client.getUrl(
        secure.secureEndpoint(pcHost, '/file', query: {'path': path}),
      );
      if (credential != null) request.headers.set('x-token', credential);
      if (origin != null) request.headers.set('origin', origin);
      return request.close();
    }

    var response = await get('/normal.txt', credential: token);
    check(
      response.statusCode == 200,
      'Authenticated home file must be readable',
    );
    check(
      await utf8.decoder.bind(response).join() == 'home folder remains shared',
      'File content mismatch',
    );
    response = await get('/.hidden-note', credential: token);
    check(
      response.statusCode == 200,
      'Ordinary hidden HOME files must remain available',
    );
    await response.drain();
    for (final credential in <String?>[
      null,
      secure.newSecret(),
      'short-token',
    ]) {
      response = await get('/normal.txt', credential: credential);
      check(
        response.statusCode == 401,
        'Missing/wrong credentials must be rejected',
      );
      await response.drain();
    }
    response = await get(
      '/normal.txt',
      credential: token,
      origin: 'https://untrusted.example',
    );
    check(
      response.statusCode == 401,
      'Browser-origin requests must be rejected',
    );
    await response.drain();
    for (final path in [
      '/../outside/secret.txt',
      '/escape/secret.txt',
      '/escaped-file',
      '/.config/phonelink/desktop.key',
    ]) {
      response = await get(path, credential: token);
      check(
        response.statusCode == 403,
        'Path must be blocked: $path (${response.statusCode})',
      );
      await response.drain();
    }
    // Configuration directories are commonly symlinked into a dotfiles folder.
    final credentialAlias = Link('${home.path}/credential-alias');
    await credentialAlias.create(protected.path);
    var aliasDenied = false;
    try {
      await secure.confinedPath(
        home.path,
        '/.config/phonelink/desktop.key',
        blocked: [credentialAlias.path],
      );
    } on secure.FileAccessDenied {
      aliasDenied = true;
    }
    check(
      aliasDenied,
      'A symlinked credential exclusion must protect its target',
    );
    final ambiguous = await client.getUrl(
      secure.secureEndpoint(pcHost, '/file', query: {'path': '/normal.txt'}),
    );
    ambiguous.headers.add('x-token', token);
    ambiguous.headers.add('x-token', secure.newSecret());
    response = await ambiguous.close();
    check(
      response.statusCode == 401,
      'Ambiguous authentication must be rejected',
    );
    await response.drain();
    final mobileRequest = await secure
        .pinnedClient(phoneIdentity.pin)
        .getUrl(secure.secureEndpoint(phoneHost, '/list'));
    response = await mobileRequest.close();
    check(
      response.statusCode == 401,
      'Phone storage must require authentication',
    );
    await response.drain();
    final remote = desktop.RemoteFs(phoneHost, token, pin: phoneIdentity.pin);
    final source = File('${temporary.path}/upload.txt');
    await source.writeAsString('encrypted upload');
    await remote.upload(source, '/Documents/upload.txt');
    final destination = File('${temporary.path}/download.txt');
    await remote.download('/Documents/upload.txt', destination);
    check(
      await destination.readAsString() == 'encrypted upload',
      'Encrypted round trip failed',
    );
    var deniedUpload = false;
    try {
      await remote.upload(source, '/escape/overwrite.txt');
    } catch (_) {
      deniedUpload = true;
    }
    check(
      deniedUpload && !await File('${outside.path}/overwrite.txt').exists(),
      'Symlink upload escaped HOME',
    );
    final browser = phone.RemoteFs(pcHost, token, pin: desktopIdentity.pin);
    final configEntries = await browser.list('/.config');
    check(
      !configEntries.any((entry) => entry.name == 'phonelink'),
      'App credentials must not be listed',
    );
    var wrongPinRejected = false;
    try {
      final request = await secure
          .pinnedClient(wrongIdentity.pin)
          .getUrl(secure.secureEndpoint(pcHost, '/list'));
      await request.close();
    } catch (_) {
      wrongPinRejected = true;
    }
    check(wrongPinRejected, 'A different certificate must fail TLS');
    for (final host in [
      '8.8.8.8:443',
      'example.com:443',
      '127.0.0.1:80/redirect',
      'user@127.0.0.1:80',
    ]) {
      var rejected = false;
      try {
        secure.secureEndpoint(host, '/');
      } catch (_) {
        rejected = true;
      }
      check(rejected, 'Non-local/malformed destination was accepted: $host');
    }
    check(
      secure.strongPairingToken(token) && token.length == 64,
      'Pairing secret must be 256 bits',
    );
    check(
      secure.tokenMatches(token, token) &&
          !secure.tokenMatches(token, 'old-pairing-token'),
      'Token validation failed',
    );
    // The same request guard used by Hub runs before a WSS upgrade.
    final events = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      desktopIdentity.context,
    );
    servers.add(events);
    events.listen((request) async {
      if (!secure.authorizedRequest(request, token)) {
        request.response.statusCode = 401;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((event) {
        final value = jsonDecode(event as String) as Map;
        socket.add(
          jsonEncode({'accepted': value['v'] == secure.secureProtocolVersion}),
        );
      });
    }, onError: (_) {});
    final eventHost = '127.0.0.1:${events.port}';
    final socket = await WebSocket.connect(
      secure.secureEndpoint(eventHost, '/', websocket: true).toString(),
      headers: {'x-token': token},
      customClient: secure.pinnedClient(desktopIdentity.pin),
    );
    socket.add(jsonEncode({'v': 2, 'type': 'hello', 'token': token}));
    check(
      (jsonDecode(await socket.first as String) as Map)['accepted'] == true,
      'Encrypted event connection failed',
    );
    await socket.close();
    var unauthenticatedSocketRejected = false;
    try {
      await WebSocket.connect(
        secure.secureEndpoint(eventHost, '/', websocket: true).toString(),
        customClient: secure.pinnedClient(desktopIdentity.pin),
      );
    } catch (_) {
      unauthenticatedSocketRejected = true;
    }
    check(
      unauthenticatedSocketRejected,
      'Unauthenticated WebSocket was upgraded',
    );

    var plaintextRequests = 0;
    final canary = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servers.add(canary);
    canary.listen((request) async {
      plaintextRequests++;
      await request.response.close();
    });
    final redirector = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      desktopIdentity.context,
    );
    servers.add(redirector);
    redirector.listen((request) async {
      request.response.statusCode = 302;
      request.response.headers.set(
        'location',
        'http://127.0.0.1:${canary.port}/',
      );
      await request.response.close();
    }, onError: (_) {});
    var redirectRejected = false;
    try {
      await WebSocket.connect(
        secure
            .secureEndpoint(
              '127.0.0.1:${redirector.port}',
              '/',
              websocket: true,
            )
            .toString(),
        headers: {'x-token': token},
        customClient: secure.pinnedClient(desktopIdentity.pin),
      );
    } catch (_) {
      redirectRejected = true;
    }
    check(
      redirectRejected && plaintextRequests == 0,
      'Credentials followed a plaintext redirect',
    );

    final existing = File('${home.path}/Documents/keep.txt');
    await existing.writeAsString('original content');
    final interrupted = await secure
        .pinnedClient(phoneIdentity.pin)
        .putUrl(
          secure.secureEndpoint(
            phoneHost,
            '/file',
            query: {'path': '/Documents/keep.txt'},
          ),
        );
    interrupted.headers.set('x-token', token);
    interrupted.contentLength = 1000000;
    interrupted.done.ignore();
    interrupted.write('partial upload');
    await interrupted.flush();
    interrupted.abort();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    check(
      await existing.readAsString() == 'original content',
      'Interrupted upload truncated an existing file',
    );

    final permissions = await Process.run('stat', [
      '-c',
      '%a',
      '${temporary.path}/keys/desktop.key',
    ]);
    check(
      '${permissions.stdout}'.trim() == '600',
      'Private key permissions must be 600',
    );
    stdout.writeln(
      'PASS: WSS authentication, no plaintext redirects, interrupted-upload preservation, pinned TLS, rejected wrong certificates, authenticated HOME access, hidden files, protected credentials including symlinked exclusions, ambiguous-header rejection, symlink/traversal rejection, encrypted upload/download, local-only destinations, strong secrets, private key permissions',
    );
  } finally {
    for (final server in servers) {
      await server.close(force: true);
    }
    await temporary.delete(recursive: true);
  }
}
