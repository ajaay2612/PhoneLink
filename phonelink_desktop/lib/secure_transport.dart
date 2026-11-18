import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const secureProtocolVersion = 2;
bool strongPairingToken(String value) =>
    RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
bool validPin(String value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
String newSecret() => List.generate(
  32,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

bool tokenMatches(String expected, String? supplied) {
  if (!strongPairingToken(expected) || supplied == null) return false;
  final a = utf8.encode(expected), b = utf8.encode(supplied);
  var difference = a.length ^ b.length;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ (i < b.length ? b[i] : 0);
  }
  return difference == 0;
}

bool localAddress(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return false;
  final b = address.rawAddress;
  return b[0] == 10 ||
      b[0] == 127 ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 169 && b[1] == 254);
}

Uri secureEndpoint(
  String hostPort,
  String path, {
  Map<String, String>? query,
  bool websocket = false,
}) {
  final uri = Uri.parse('https://$hostPort');
  final address = InternetAddress.tryParse(uri.host);
  if (address == null ||
      !localAddress(address) ||
      uri.userInfo.isNotEmpty ||
      uri.path.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !uri.hasPort ||
      uri.port < 1) {
    throw const FormatException('Use a local IPv4 address and port');
  }
  return Uri(
    scheme: websocket ? 'wss' : 'https',
    host: uri.host,
    port: uri.port,
    path: path,
    queryParameters: query,
  );
}

final _clients = <String, HttpClient>{};
HttpClient pinnedClient(String pin) {
  if (!validPin(pin)) {
    throw const FormatException(
      'Scan the updated pairing QR to establish trust',
    );
  }
  return _clients.putIfAbsent(pin, () {
    if (_clients.length >= 4) {
      _clients.remove(_clients.keys.first)?.close(force: true);
    }
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = const Duration(seconds: 5)
      ..findProxy = ((_) => 'DIRECT')
      ..badCertificateCallback = (certificate, host, port) {
        final now = DateTime.now();
        return localAddress(
              InternetAddress.tryParse(host) ?? InternetAddress.anyIPv4,
            ) &&
            !now.isBefore(certificate.startValidity) &&
            !now.isAfter(certificate.endValidity) &&
            tokenMatches(pin, sha256.convert(certificate.der).toString());
      };
    return _LocalPinnedClient(client);
  });
}

/// Also enforces policy for WebSocket.connect's internal HTTP upgrade request.
class _LocalPinnedClient implements HttpClient {
  _LocalPinnedClient(this.inner);
  final HttpClient inner;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri uri) async {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        !localAddress(
          InternetAddress.tryParse(uri.host) ?? InternetAddress.anyIPv4,
        )) {
      throw const FormatException('Only encrypted local endpoints are allowed');
    }
    final request = await inner.openUrl(method, uri);
    request.followRedirects = false;
    return request;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri uri) => openUrl('GET', uri);
  @override
  Future<HttpClientRequest> putUrl(Uri uri) => openUrl('PUT', uri);
  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unsupported secure client operation');
}

bool authorizedRequest(HttpRequest request, String token) {
  final values = request.headers['x-token'];
  return localAddress(
        request.connectionInfo?.remoteAddress ?? InternetAddress.anyIPv4,
      ) &&
      request.headers['origin'] == null &&
      values != null &&
      values.length == 1 &&
      tokenMatches(token, values.single);
}

String certificatePin(String pem) {
  final encoded = pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), '');
  return sha256.convert(base64Decode(encoded)).toString();
}

SecurityContext serverContext(String certificate, String key) =>
    SecurityContext()
      ..useCertificateChainBytes(utf8.encode(certificate))
      ..usePrivateKeyBytes(utf8.encode(key));

/// Resolve existing ancestors before access: lexical '..' and symlink escapes are rejected.
Future<String> confinedPath(
  String root,
  String relative, {
  List<String> blocked = const [],
}) async {
  if (relative.contains('\x00') || p.posix.split(relative).contains('..')) {
    throw const FileAccessDenied();
  }
  final canonicalRoot = await Directory(root).resolveSymbolicLinks();
  final full = p.normalize(
    p.join(canonicalRoot, relative.replaceFirst(RegExp(r'^/+'), '')),
  );
  if (full != canonicalRoot && !p.isWithin(canonicalRoot, full)) {
    throw const FileAccessDenied();
  }
  var existing = full;
  final suffix = <String>[];
  while (await FileSystemEntity.type(existing, followLinks: false) ==
      FileSystemEntityType.notFound) {
    suffix.insert(0, p.basename(existing));
    final parent = p.dirname(existing);
    if (parent == existing) throw const FileAccessDenied();
    existing = parent;
  }
  final resolved = await File(existing).resolveSymbolicLinks();
  final target = p.normalize(p.joinAll([resolved, ...suffix]));
  if (target != canonicalRoot && !p.isWithin(canonicalRoot, target)) {
    throw const FileAccessDenied();
  }
  for (final path in blocked) {
    final forbidden = p.normalize(path);
    if (target == forbidden || p.isWithin(forbidden, target)) {
      throw const FileAccessDenied();
    }
    // Apply exclusions to the same canonical namespace as the requested path.
    // ~/.config (or the credential directory itself) may be a symlink.
    try {
      final canonicalForbidden = await Directory(
        forbidden,
      ).resolveSymbolicLinks();
      if (target == canonicalForbidden ||
          p.isWithin(canonicalForbidden, target)) {
        throw const FileAccessDenied();
      }
    } on FileSystemException {
      // An unavailable exclusion cannot safely be checked; fail closed.
      throw const FileAccessDenied();
    }
  }
  return target;
}

class FileAccessDenied implements Exception {
  const FileAccessDenied();
}

/// Stage writes so a failed transfer cannot truncate the existing destination.
Future<void> receiveFile(HttpRequest request, String target) async {
  final destination = File(target);
  await destination.parent.create(recursive: true);
  final temporary = File(
    p.join(destination.parent.path, '.phonelink-upload-${newSecret()}'),
  );
  try {
    final sink = temporary.openWrite();
    try {
      await sink.addStream(request);
      await sink.flush();
    } finally {
      await sink.close();
    }
    await temporary.rename(destination.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
