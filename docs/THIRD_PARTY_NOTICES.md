# Third-party notices and artwork

This repository does not currently include a project-wide software license. That choice belongs to the project owner. The following notes do not replace dependency license obligations or grant rights to third-party code.

## Font

The UI uses **Manrope**. Its SIL Open Font License notices are preserved at:

- [`phonelink_android/assets/fonts/OFL.txt`](../phonelink_android/assets/fonts/OFL.txt)
- [`phonelink_desktop/assets/fonts/OFL.txt`](../phonelink_desktop/assets/fonts/OFL.txt)

## Framework and packages

The apps use Flutter/Dart, Android platform APIs, GTK/GLib and the packages recorded in each application's `pubspec.yaml` and `pubspec.lock`. Consult those upstream projects for their licenses. Flutter build output includes generated package license notices; preserve relevant notices when distributing binaries.

The Linux tray integration dynamically uses an available AppIndicator library. Keep applicable third-party notices and distribution obligations in mind when packaging native libraries yourself; the current bundle relies on system GTK/AppIndicator libraries rather than copying the complete system runtime.

## Artwork and documentation

- The Fonelink icon is project-selected, AI-generated artwork stored under `assets/branding/`; launcher variants are derived from it.
- README gallery illustrations are procedural Flutter Canvas drawings made for the documentation.
- Public screenshots use fictional fixture data; see [SCREENSHOTS.md](SCREENSHOTS.md).
- Existing design-process attribution is retained in [`DESIGN.md`](../DESIGN.md), including the unslop skill attribution. Those design references are distinct from the software's project-wide licensing decision.
