# Preparing a GitHub release

The repository is source-first. `.gitignore` excludes local build/install output, signing material, SDK paths and the project graph. Attach binaries to a GitHub **Release** instead of committing APKs, native libraries or complete Flutter bundles.

## 1. Review the source upload

Before the first push:

- Read the home-folder sharing boundary in the root README and security documents.
- Keep both application `pubspec.lock` files, source assets, font license notices, platform runners, Gradle wrapper and documentation images.
- Exclude real pairing QRs/tokens, `config.json`, phone preferences, TLS private keys/certificates, local SDK paths, signing keys/passwords, `.env` files and real messages/photos.
- Review what you are staging with `git status --short` and `git diff --cached`. GitHub’s web uploader does not automatically apply `.gitignore`; use Git or select source/docs manually. Ignore rules do not remove files already staged or committed; remove those from the index/history as appropriate before publishing and rotate any exposed credentials.
- Keep the existing dummy-data images. Do not substitute a screenshot containing your real messages or an active pairing QR.

This workspace may not yet be an initialized Git repository. The documentation changes do not initialize a repository, stage files, create a remote or publish anything.

## 2. Choose a license

There is currently no project-wide `LICENSE`. Choose the terms you intend before offering general reuse rights. Preserve third-party notices, especially the Manrope OFL files. A public GitHub repository is not automatically MIT-licensed.

## 3. Prepare Android signing

`phonelink_android/android/app/build.gradle.kts` currently signs release builds using the debug signing configuration. Do not describe that as a production signing setup.

For a public release:

1. Generate and back up a private release keystore outside the repository, for example under your personal signing directory. Use `keytool` interactively so passwords do not end up in command history.
2. Supply its path, alias and passwords through a private `key.properties` file or your CI secret store.
3. Define a release signing configuration in Gradle and replace the existing `signingConfigs.getByName("debug")` reference for release builds.
4. Verify the resulting APK using the Android SDK's `apksigner verify --verbose --print-certs`.
5. Keep using that signing key for later updates. Do not commit it or print its passwords in CI logs.

Example *shape* of a private properties file, with placeholders only:

```properties
storeFile=/absolute/path/outside/the/repository/phonelink-release.jks
storePassword=YOUR_PRIVATE_STORE_PASSWORD
keyAlias=phonelink
keyPassword=YOUR_PRIVATE_KEY_PASSWORD
```

These ignore rules cover both the properties file and common keystore extensions, but still review your staged files. Signing alone does not establish Google Play policy compliance or prevent Play Protect from reviewing/blocking sensitive-permission sideloads.

## 4. Build from a clean checkout

Use the tested Flutter toolchain or deliberately test your chosen newer version. Increase the application version/build number for a new release, and keep the two apps' protocol compatibility clear in release notes.

```bash
# Linux bundle
(cd phonelink_desktop && flutter pub get && flutter analyze && flutter build linux --release)

# Android APK, after configuring release signing
(cd phonelink_android && flutter pub get && flutter analyze && flutter build apk --release)
```

Never package files from `~/.config/phonelink`; each user's identities must be generated locally. The runtime `openssl` command must remain available on the Linux PC.

## 5. Validate behavior

Run the tests described in the root README. Before claiming a release is validated, also check on real devices:

- New pairing and reconnect after restarting the PC.
- Live SMS and OTP extraction; non-OTP numeric messages should not create a code.
- PC clipboard copying while the window is in the tray; phone shade sending; no clipboard echo.
- Locked/off-screen phone rejecting incoming clipboard writes.
- Transfers in both directions, hidden-file behavior and the shared-root boundary.
- Recent-image refresh/pagination.
- Android service behavior after activity removal, notification dismissal, unlock and reboot; denied notification/storage permissions.
- Native Wayland/X11 behavior, close-to-tray, Open/Quit and quiet login startup.
- No unintended external destinations, insecure certificate fallbacks or accidentally included private credentials.

The dated security audit documents its original scope and limitations. It is not proof that every later build or dependency is secure.

## 6. Package and upload assets

The APK is under `phonelink_android/build/app/outputs/flutter-apk/app-release.apk`. The Linux application is the **entire** `phonelink_desktop/build/linux/x64/release/bundle/` directory, including `data/` and `lib/`; publishing only the executable will not work.

For a simple portable Linux archive:

```bash
mkdir -p dist
cp phonelink_android/build/app/outputs/flutter-apk/app-release.apk dist/PhoneLink-android.apk
tar -czf dist/PhoneLink-linux-x64.tar.gz -C phonelink_desktop/build/linux/x64/release bundle
(cd dist && sha256sum PhoneLink-android.apk PhoneLink-linux-x64.tar.gz > SHA256SUMS)
```

Users can extract that portable archive and run `./bundle/phonelink_desktop`. For menu/autostart integration from a source checkout, run `./scripts/install-desktop.sh /absolute/path/to/extracted/bundle`. The separately prepared personal-use archives in the current local `dist/` folder may also contain their own `install.sh`; only advertise that command if the uploaded archive actually includes it.

Attach the APK, archive and checksums to the GitHub Release. Include supported OS/architecture, build toolchain, signing/distribution status, version, protocol/re-pairing requirements and known limitations. Avoid claiming compatibility with every phone/distribution, zero security risk, or guaranteed immunity to Android background restrictions.
