# PhoneLink for Linux

Flutter Linux companion for messages, OTPs, clipboard sharing, file transfer and recent phone pictures. The GTK runner provides the tray, quiet login startup and a background clipboard bridge while keeping the window on the desktop's native rendering backend.

Start with the [root README](../README.md) for screenshots, pairing, requirements, permissions and security limits. The paired phone can read/write the shared PC home folder; see [SECURITY.md](../SECURITY.md).

```bash
flutter pub get
flutter analyze
flutter test
flutter build linux --release
cd ..
./scripts/install-desktop.sh
```

Keep the entire generated `build/linux/x64/release/bundle/` together. The installer adds the user application-menu entry and enables tray-only startup at desktop login. Quit the installed app from its tray before running a second development copy on TCP 8766.

On Wayland, XWayland/`DISPLAY` supports the current background clipboard bridge; the main window stays native Wayland. OpenSSL is required for local certificate generation. Tray support needs a compatible panel and AppIndicator runtime. See [INSTALL.md](../INSTALL.md) for details and [release preparation](../docs/RELEASING.md) before publishing binaries.
