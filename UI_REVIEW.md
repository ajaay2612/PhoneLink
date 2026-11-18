# Interface finish pass

Applied [unslop by Damir Sokolovsky](https://heydamir.design/unslop), CC BY 4.0, to the existing Flutter apps. The direction stays calm and exact: charcoal/white surfaces, Manrope, green connection and selection cues, and the same link mark on both installed apps.

| Audit finding | Change |
| --- | --- |
| Settings, manual pairing and appearance were mixed into the device home | Dedicated phone Settings destination; home keeps device status and recent activity |
| Appearance dropdown hid the three choices | Direct System / Light / Dark options; system remains the default |
| Large stock switches differed from other controls | Compact shared visual switch with keyboard semantics and a full touch target |
| Buttons, inputs, icon buttons and action rows used unrelated sizes | Shared control radius, spacing, typography, focus styles and platform-appropriate heights |
| Container cards could let ink paint on the wrong Material or outside corners | Clipped Material card surfaces; full-width interactive rows; separately clipped navigation targets |
| Photo thumbnails obscured their own ripple feedback | Transparent ink layer above each image, inside its clipped border |
| App dialogs and menus inherited differing defaults | Shared dialog/menu themes; app-owned confirmation/detail dialogs use AppDialog |
| Native clipboard overlay ignored dark appearance | Small native sending window follows the saved/System theme |
| Flutter launcher artwork and Linux launcher identity were placeholders | Shared editable link mark, Android legacy/adaptive/monochrome assets, notification symbol, Linux window icon and desktop entry |

## Validation completed

- Dart static analysis across both projects, including updated test sources.
- Android manifest/resource XML parsing and launcher PNG dimensions/format checks.
- Linux desktop entry validation and installer shell syntax validation.
- Isolated installer check with a dummy bundle and a path containing spaces. No application was launched or installed into the real user profile.
- Visual inspection of the generated launcher artwork.

The phone navigation/control checks and desktop interaction checks were updated for the new interface. Flutter widget tests, native compilation, device checks, and runtime light/dark visual checks were not run, following the instruction not to build or launch the apps. These are still required before calling a distributable release verified.

System-owned Android permission screens and its file chooser intentionally retain their native UI. The existing transport, pairing protocol and local-only architecture remain intact.
