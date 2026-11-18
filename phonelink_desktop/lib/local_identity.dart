import 'dart:io';
import 'package:path/path.dart' as p;
import 'secure_transport.dart';

class LocalIdentity {
  LocalIdentity(this.certificate, this.privateKey);
  final String certificate, privateKey;
  String get pin => certificatePin(certificate);
  SecurityContext get context => serverContext(certificate, privateKey);

  static Future<LocalIdentity> load(Directory directory, String name) async {
    await directory.create(recursive: true);
    await _run('chmod', ['700', directory.path]);
    final certificate = File(p.join(directory.path, '$name.crt'));
    final key = File(p.join(directory.path, '$name.key'));
    if (!await certificate.exists() || !await key.exists()) {
      await _run('openssl', [
        'req',
        '-x509',
        '-newkey',
        'rsa:3072',
        '-sha256',
        '-nodes',
        '-keyout',
        key.path,
        '-out',
        certificate.path,
        '-days',
        '3650',
        '-subj',
        '/CN=PhoneLink-$name',
      ]);
    }
    await _run('chmod', ['600', certificate.path, key.path]);
    return LocalIdentity(
      await certificate.readAsString(),
      await key.readAsString(),
    );
  }

  static Future<void> _run(String executable, List<String> args) async {
    final result = await Process.run(executable, args);
    if (result.exitCode != 0) {
      throw StateError('Could not prepare secure local identity ($executable)');
    }
  }
}
