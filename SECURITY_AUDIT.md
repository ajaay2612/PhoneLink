# Fonelink security audit — 16 November 2026

## Assessment

Source review and isolated integration tests found no unauthenticated file-access or plaintext transport bypass in the reviewed v2 paths after the fix below. This is not a claim of zero network risk or a certification of the installed applications.

Both apps intentionally expose authenticated TLS listeners to IPv4 interfaces: desktop TCP 8766 and phone TCP 8767. LAN devices can attempt connections. Source-address restrictions are enforced after TLS connects; they are not a firewall. Do not forward these ports from a router. No UPnP port-opening, cloud relay, telemetry endpoint or public-host connection was found in the graph-indexed application source reviewed.

## Confirmed finding and fix

**Medium: symlinked configuration directory could bypass credential exclusion.** Requested paths were canonicalized, but excluded paths were compared lexically. If `~/.config` or its Fonelink subdirectory was a symlink, an authenticated phone could potentially read or overwrite Fonelink credentials through the resolved location. An unpaired device still needed the pairing secret.

Both copies of `secure_transport.dart` now canonicalize exclusions too, and fail closed when an exclusion cannot be resolved. The new regression first failed on the original implementation and passed after the fix. Ordinary home-folder sharing is preserved.

## Controls reviewed

- HTTPS/WSS only for application transfers; certificate fingerprint pinning, validity checks, no environment proxy, no redirects or plaintext compatibility fallback.
- Local literal IPv4 destinations only; incoming private/link-local/loopback source check. Authentication before file operations and WebSocket upgrade; ambiguous authentication headers and browser origins rejected.
- Random 256-bit pairing secret, protocol v2 handshake, session-token revalidation and desktop pairing reset/revocation.
- Desktop and Android Dart connections plus the native Android notification/clipboard sender. Native sender verifies the pinned TLS certificate before transmitting credentials.
- Canonical shared-root confinement, symlink/traversal checks, credential-directory exclusion, staged upload writes and no-store responses.
- Private desktop configuration/key permissions; Android sandbox storage, backup exclusions, non-exported clipboard components and permission-protected SMS/notification components.

## Verification

- Pure-Dart temporary loopback TLS integration: authenticated transfers, wrong/missing tokens, phone storage authentication, duplicate token headers, wrong certificate pin, browser-origin rejection, WSS guard, plaintext redirect rejection, traversal/symlink rejection, symlinked credential exclusions, interrupted upload preservation and private key permissions.
- Dart analysis across both projects: no issues.
- Android source manifests and backup XML parse successfully. Shared transport implementations match byte-for-byte.
- OSV batch queries of all locked hosted Pub packages: 90 Android and 35 desktop package/version entries; no matching advisories returned at audit time. Exact queries, responses, timestamps and lockfile hashes are in `security-audit/dependency-advisories.json`. This does not cover Gradle dependencies, bundled native code, Flutter/Dart SDK or OS/OpenSSL vulnerabilities. Database silence is not proof that a dependency is safe.
- Read-only host listener inspection: no TCP 8766 listener was present at the time. Neither Flutter app was built, installed or launched for this audit.

## Remaining trust boundaries and release work

1. **Full home access remains intentional.** A device with the pairing secret can read and overwrite ordinary home files, including hidden files and executable configuration such as shell startup files. A stolen QR/token or compromised paired phone therefore has substantial impact. Fonelink's own credential directory is excluded; other application secrets are not. This preserves the requested home-folder sharing policy.
2. **Availability is not guaranteed on hostile networks.** TLS handshakes and connections reach the listener before application authentication. There is no comprehensive connection-rate, upload-size, disk-usage or request-concurrency quota. Network flooding can exhaust resources; a trusted peer can fill shared storage. Use a trusted LAN or restrict exposure with the host/network firewall.
3. **Release signing is unfinished.** Android's release build still uses the debug signing configuration. Use a private release keystore before distributing the app; no signing keys or configuration were invented during this audit.
4. **Installed/native verification remains open.** No Android-native compilation, real-phone traffic capture, external LAN scan, router/NAT/firewall audit, device lifecycle test or full native dependency audit was performed. A source fix does not update an installed APK or Linux executable. Both apps need updated builds and v2 pairing before relying on these protections.
5. **Filesystem race boundary.** Canonical path checks are not kernel-level descriptor-relative confinement. A local process that can replace path components during an operation may race the check. Malware running as the same desktop user and a compromised paired endpoint are outside this protection model.

The audit supports encrypted, authenticated local sharing within those boundaries. It does not support describing either app as completely safe or having no exposed network surface.
