# Fonelink for Android

Android companion for the local Android/Linux Fonelink pair. It provides QR pairing, recent SMS forwarding, a phone file server, PC home-folder browsing, system/light/dark appearance and the notification-shade clipboard action.

Start with the [root README](../README.md) for screenshots, setup, permissions, architecture and security limits. See [INSTALL.md](../INSTALL.md) for background behavior and [release preparation](../docs/RELEASING.md) before distributing APKs.

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.

The current release build uses development signing. Configure a private release key for public distribution; never commit signing properties, keys, runtime pairing data or real message screenshots. Native Kotlin/manifest/icon changes require a rebuilt/reinstalled APK, not just hot restart.

Runtime requires Android API 24 or newer with the currently tested build. USB debugging is only needed for developer installation/testing; it is not needed for normal local communication.
