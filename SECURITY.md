# Fonelink connection security

See [SECURITY_AUDIT.md](SECURITY_AUDIT.md) for the latest audit, verified fix, dependency results and remaining release checks.

## What remains shared

The desktop still shares the configured home folder, including normal hidden files. The phone still serves shared phone storage after storage permission is granted. No cloud account, relay or public server is introduced.

Fonelink's own desktop credential directory (`~/.config/phonelink`) is excluded from the file API. Paths that traverse outside the configured root, including symlink escapes, are rejected. This is a boundary fix, not a change to the configured shared folder.

## Transport and pairing

- Protocol version 2 only: HTTPS for files and previews, WSS for messages, clipboard and device events. There is no plaintext compatibility listener or downgrade fallback.
- A cryptographically random 256-bit secret replaces the old eight-character token. Requests authenticate before a WebSocket upgrade or any file access. Event sockets are checked again after credentials are rotated.
- The pairing QR contains the desktop certificate's SHA-256 fingerprint. Dart clients and the native Android background sender pin that certificate and check its validity. No accept-any-certificate callback is used.
- The authenticated encrypted desktop connection provisions a separate TLS identity for the phone's file server. The desktop pins that phone certificate. This is a paired-device trust model: the desktop provisions and knows the phone endpoint identity; it is not an independent hardware identity or mutual-client-certificate scheme.
- Connections are limited to literal private, link-local or loopback IPv4 addresses. Public addresses, DNS hostnames, URL credentials and malformed endpoint addresses are rejected. Environment proxies and redirects are not used.
- Browser-origin requests are rejected. Authentication headers with ambiguous values are rejected. WebSocket messages are bounded and compression is disabled on the desktop event server.
- Linux keys and configuration are kept in a mode-700 directory with mode-600 files. Android pairing material is kept in the app sandbox, excluded from cloud backup and device-transfer backups. Android cleartext traffic is disabled.

The pairing QR is a credential. Anyone you give it to is being authorized to access your shared home folder.

## File safety

The file handlers resolve existing ancestors before access and reject symlink/traversal escapes. Uploads are staged in the destination directory and renamed after completion, so an interrupted upload does not truncate an existing destination. File responses disable HTTP caching; photo thumbnails have a bounded in-memory cache.

The API remains an authorized read/write interface to your shared folder. It does not protect files from a device you have paired, malware running as your own desktop user, root access, or a compromised phone/PC. Normal operating-system filesystem permissions and Android external-storage behavior still apply. This is source hardening plus local integration testing, not an independent penetration-test certification.

## Updating existing installations

1. Update both applications together. The Linux desktop requires OpenSSL to prepare local certificates; generation is entirely local.
2. Fully rerun/reinstall the Android app so its native TLS sender and backup rules are updated.
3. Scan the new desktop QR. Old short-token pairings are deliberately invalidated. For manual pairing, copy the local address, new token and PC certificate fingerprint.

Files and the configured home-folder path are preserved. Mixed old/new versions fail closed rather than continuing unencrypted. To revoke trust later, use **Pair phone → Manual connection → Reset pairing** on desktop. It rotates the token and phone endpoint identity and stops existing desktop connections/transfers. A connected updated phone is told to forget the old pairing; an offline phone should also use Forget this PC before being repurposed.

Certificates are local self-signed identities. A changed/expired desktop identity requires visual re-pairing; the phone never silently trusts a replacement. If a protocol rollback is necessary, roll back both app versions together and establish fresh pairing. An older version reintroduces its old security properties; v2 does not offer an insecure fallback to support it.

## Checks completed

Run the pure-Dart loopback integration check from `phonelink_android`:

```sh
dart run tool/security_check.dart
```

The check uses temporary files and local test servers, not either Flutter application. It verifies certificate pinning and wrong-pin rejection, authenticated home and hidden-file access, denial of wrong/missing credentials and browser origins, WSS authentication, rejection of plaintext redirects, traversal/symlink and credential-directory protections, encrypted uploads/downloads, interrupted-upload preservation, local-only destinations, token shape and private key permissions.

Dart analysis and Android XML parsing are also checked. Flutter/native builds, Android-native compilation, live device connectivity, background lifecycle behavior and an on-device traffic capture were not run during this change. Those remain required release verification, especially the first full Android run and re-pair after this migration.
