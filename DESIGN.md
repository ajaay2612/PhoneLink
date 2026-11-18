# PhoneLink interface

PhoneLink links an Android phone and a Linux PC directly for SMS, clipboard text and files.

The Android interface uses a warm neutral palette with green connection surfaces and bottom navigation. The desktop uses the same warm white, sage and forest-green palette as Android, while preserving its layered panels, compact top navigation and device sidebar. The user explicitly chose this shared green palette over the charcoal/orange variation. Manrope is bundled locally under its SIL Open Font License; no font service is used at runtime.

The desktop keeps real app content in the foreground. No simulated charts, fabricated metrics or decorative online assets are included. Its phone-to-PC motif reflects connection state. Windows at least 960 logical pixels wide include a device panel and quick actions; narrow windows retain the same four pages without a sidebar. File operations, pairing, SMS and clipboard transport retain their existing direct-device protocols.

Design guidance: [Unslop](https://github.com/heydamir/unslop) by Damir Sokolovsky ([@heydamir](https://x.com/heydamir)), CC BY 4.0; [Emil Kowalski's design engineering skills](https://github.com/emilkowalski/skills); [Taste skill](https://github.com/leonxlnx/taste-skill). Website-specific tooling is not used in these native Flutter apps.

# Scanner

Android uses flutter_zxing with a bundled ZXing-C++ decoder. The gallery action is disabled and its transitive image-picker Play Services module-download declaration is removed in the app manifest. ML Kit is no longer a dependency. The desktop QR encoder and pairing payload format are unchanged.

Build tooling may download packages. Runtime packet capture and camera/pairing validation on physical devices remain separate from source, dependency and widget checks.

App-owned icons are drawn with bundled Dart vector paths to avoid icon-font loading failures. No photo backdrop is included.

The Files tab splits the phone browser and a recent-images grid into equal panes (stacked in narrow windows). Dot-prefixed entries are hidden by default; the folder's three-dot menu toggles them and holds Refresh and Send files. Recent photos are listed by modification time from DCIM, Pictures, Download and supported messaging-media folders, with local authenticated thumbnails. Originals can be previewed and saved to PhoneLink downloads. Linux uploads use an in-app chooser so external desktop dialog failures cannot silently cancel selection.

The desktop uses the full window without decorative outer frames. Page headings have compact spacing, with All downloads next to Files. Image grids contain square thumbnails without filename captions; filenames remain available in accessible labels and the preview dialog. Standalone instructional note panels are removed. The connected-device card uses a single phone mockup, the phone-reported name, live battery/network/Wi-Fi values, and a status refresh action. Status updates travel over the existing authenticated local WebSocket every 15 seconds. Unknown Android identifiers remain unavailable rather than being fabricated. The required telephony SMS broadcast receiver is declared for immediate foreground/background SMS forwarding; Android-native changes require a full user-run Android launch/build once.

The desktop shell follows the provided Phone Link layout: compact phone identity/status at the top of a persistent left sidebar, quick actions beneath it, and a separate tabbed workspace on the right. Messages use a sender list and conversation pane on wide windows; narrow windows open conversations in a dialog. Network/Wi-Fi indicators reveal actual phone-reported values in tooltips, beside battery percentage and connection refresh. Only existing app features are exposed; no call, app-streaming or notification-mirroring controls are simulated.

The widened desktop sidebar combines the larger phone identity/status and quick actions in one card. A real phone-notification list fills the space below it. Android's notification-listener service requires explicit notification-access approval, excludes this app's own notifications and group summaries, streams posted/removed events over the paired local connection, and sends an active snapshot on connection. A native local-socket fallback handles listener events without a Flutter activity. Forwarding stops when disconnected or access is revoked; the desktop stores at most 50 items in memory. Clear affects only the desktop list. Network/Wi-Fi readings are available in icon tooltips, the battery glyph reflects its actual reported level, and unavailable native status is marked explicitly. In-app wordmark/logo headers are removed from phone and desktop.

- Clipboard notification action uses a small translucent native activity, waits for window focus, reads text once, and finishes before sending over the paired LAN socket. No Flutter screen or draw-over-apps permission. Android native rerun required; device behavior unverified without build.

- Desktop navigation uses left-aligned icon/text tabs with a 3px green active underline, no enclosing pill border. Messages badge counts live arrivals while another workspace is selected and clears on opening Messages. Right-aligned sun/moon control switches and persists the desktop light/dark palette.

- Dark mode uses neutral charcoal surfaces and gray text/borders; reserve green for active controls and connection status rather than tinting the entire workspace.

- Phone Appearance defaults to the OS theme, follows system brightness live, and offers saved System default / Light / Dark choices. Dark surfaces match desktop neutral charcoal. Phone mockup has no internal battery progress bar; battery remains beside the device name.

## Final interface system

Direction: a calm, exact local-device utility. Keep Manrope, neutral surfaces and restrained green connection cues. The link stroke is the shared app mark. Design review uses [unslop by Damir Sokolovsky](https://heydamir.design/unslop), CC BY 4.0.

- Phone: My devices / PC files / Settings. Settings owns appearance, clipboard sync, permissions, manual pairing and forgetting the PC. Home owns the paired device and recent activity.
- Theme selection uses three direct choices: System, Light, Dark. System is the default. No appearance dropdown.
- Controls: 10px radius; 44px phone buttons and 40px desktop buttons. The compact switch track is 36×22 within a 48×44 keyboard/touch target. Inputs, buttons and popup actions use the same typography and spacing.
- Cards: 16px radius, 1px border, clipped Material. Padded content belongs inside the Material; interactive row backgrounds reach its edge. Photo ink sits above the image, so feedback stays visible.
- App-owned dialogs: 20px radius, 20px content padding, 12px title-to-content gap, 24px action separation, matching light/dark surface and barrier. File pickers and system permissions owned by Android retain the native OS UI.
- Icons: local vector strokes at 18–20px for controls; no icon-font dependence. Launcher assets use the selected device-link artwork under assets/branding/concepts, with mask-safe Android foregrounds. Never reintroduce in-app branding headers.
- Navigation remains flat and left aligned, with an active underline and an edge-to-edge separator. Badges mean new arrivals, not arbitrary totals.

- Page rhythm: desktop tab bar has no outer top/side padding; workspace content starts 16px below its full-width divider. Desktop page headings share a 44px minimum row and 16px bottom gap. Phone pages all start at 20px, use 30px page titles and a 24px heading-to-content gap.

- Desktop tab controls respect the content's 16px horizontal inset while the navigation strip and divider stay edge-to-edge. Messages has no local refresh; use the connected-device refresh, which also requests SMS history.
- Phone navigation is a floating, clipped 3-destination bar. Manual pairing uses permanent labels above inputs. Storage access displays its real native permission state and opens the app-specific All files access settings, refreshing status on resume.
- Recent images uses 64-item pages with Load more, not a 48-photo cap. Refresh resets to the newest page and scroll position; versioned image URLs prevent old thumbnails from being reused after refresh. The main device refresh reloads messages, status, the current file folder and recent images; the gallery has no separate refresh button. File-menu Refresh also reloads both file sections.

- Desktop device sidebar starts 16px below the title bar; keep its card inset consistent rather than using a 4px top gap.

- Selected device-link icon is used for Linux, Android legacy/adaptive/themed launchers and the notification symbol. Keep the original artwork under assets/branding/concepts; resized app assets are prepared in the workspace.
- Phone nav icons are 24px. Files content ends 12px above the floating bar, accounting for the native gesture inset rather than reserving an arbitrary 112px.
- Separators use quieter gray tones in both apps. Desktop sidebar uses the deeper page background behind raised cards.
- Code banner has no section label; use 20px vertical padding with a quieter sender/time caption.

- Security v2 keeps home sharing and adds pinned HTTPS/WSS, a 256-bit QR pairing secret, and literal-LAN-only endpoints. Manual pairing includes the PC certificate fingerprint. Reset pairing is an explicit confirmed action under the desktop manual-connection details. No plaintext fallback or remote-service UI is introduced.

- Phone clipboard sending is notification-action only. There is no phone Clipboard sync setting or clipboard polling; receiving PC clipboard text still respects the native lock check.
