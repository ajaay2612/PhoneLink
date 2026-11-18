# Public preview images

All images in `docs/images/` are safe-to-publish documentation fixtures, not captures of the developer's live devices.

## Sources and provenance

- Desktop messages, clipboard, phone device and phone settings previews are rendered from the current Flutter widgets with fictional fixture state.
- The file preview assembles the application's actual file-browser and recent-image components with fictional folders, documents and an in-memory `RemoteFs` stub.
- Gallery artwork is generated locally with Flutter Canvas (colored skies, hills and circles). It is not a photo from a real phone or an external stock-image service.
- `overview.png` is composed from those renders and the existing project icon by a local Pillow script.
- Names, addresses, messages and codes are fictional. The displayed code `482913` is a static example and is not tied to an account. No working pairing QR, private key or valid pairing token is rendered.
- The phone renderer enables actual elevation shadows instead of Flutter test-mode shadow outlines.
- Android system chrome is omitted. These previews illustrate the app; they do not demonstrate a tested connection to the fictional devices.

## Regeneration

Use the same Flutter version as the application builds for stable layout and font output. From the repository root:

```bash
(cd phonelink_desktop && flutter test tool/readme_screenshots_test.dart)
(cd phonelink_android && flutter test tool/readme_screenshots_test.dart)
python3 scripts/compose-readme-preview.py
```

The last command requires Pillow (`python3 -m pip install Pillow` in your preferred virtual environment). With uv, you can instead run `uv run --with pillow python scripts/compose-readme-preview.py` from the repository root. The Flutter renderers use `Home(initialize: false)` and an injected desktop hub. They do not start app services, request permissions, load a real pairing or access the actual home/phone file servers. The gallery stub serves generated PNG bytes in memory.

By default, renders go to `../docs/images` relative to each application. Set `PHONELINK_SCREENSHOT_DIR` to an alternate output directory if needed. The renderer files live under `tool/`, so ordinary `flutter test` runs do not regenerate documentation images.

Inspect the output before committing. Keep the current fixtures or replace them with equally fictional data; never use a live pairing QR or screenshots of real conversations/clipboard text. Do not change the app's production behavior just to make a screenshot look more complete.
