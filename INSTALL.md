# Installing PhoneLink

Locally prepared personal-use builds may be available under `dist/`, including the updated icons and security fixes. That directory is ignored by Git and is not included in a source checkout. Build from the [root README](README.md), or use explicitly published GitHub Release assets if the repository maintainer provides them.

- Android: `dist/PhoneLink-1.0.0-android.apk`.
- Linux x64: extract `dist/PhoneLink-1.0.0-linux-x64.tar.gz`, then run `./install.sh` inside the extracted folder. No sudo is needed. Open PhoneLink from the application menu afterward.

Close any running desktop copy before installing. After updating both applications, scan the desktop pairing QR again. Checksums are in `dist/SHA256SUMS`.

## Android

Copy the APK to your phone and open it. Allow installation from your file manager if Android asks, then install/update PhoneLink. Installing the newly built APK applies the launcher/adaptive icon, notification icon and native clipboard overlay changes. Hot restart cannot update those resources.

This personal-use APK is built in release mode with the project's existing development signing key. Configure your private release keystore before distributing production APKs; no signing credentials were created or changed here.

## Linux desktop

Build the Linux release bundle from `phonelink_desktop` using your existing Flutter workflow, then run from the repository root:

```sh
./scripts/install-desktop.sh
```

For a bundle in a different location:

```sh
./scripts/install-desktop.sh /absolute/path/to/bundle
```

The script only installs an existing bundle; it never builds or launches the app. It copies the full bundle into `$XDG_DATA_HOME/phonelink` (default `~/.local/share/phonelink`) and adds the PhoneLink launcher and icon to the current user's application menu. It needs no administrator access. Close an already-running desktop instance before updating its installed files.

The GTK application ID and `.desktop` identity both use `dev.phonelink.PhoneLink`, so supported desktop environments can associate the running window with its launcher icon.

Closing the Linux window hides PhoneLink to its tray icon and keeps the connection alive. Use **Open PhoneLink** to restore the window and **Quit PhoneLink** to exit. Launching PhoneLink again also restores the existing window. This requires a StatusNotifier/AppIndicator-compatible tray host and either `libayatana-appindicator3.so.1` or `libappindicator3.so.1`. If no tray host is connected, the window closes normally instead of leaving an inaccessible hidden process.

The installer enables desktop-login autostart in `$XDG_CONFIG_HOME/autostart/dev.phonelink.PhoneLink.desktop` (default `~/.config/autostart/`). It runs `--start-in-tray`, which starts the connection without opening a window. A normal application-menu launch opens the existing window. Remove that autostart entry to disable login startup. This starts at desktop login, not before a user session exists.

On Wayland, PhoneLink keeps its window on native Wayland and uses a separate GTK/XWayland clipboard connection for background text sharing when `DISPLAY` is available. This avoids requiring the window to be focused for clipboard polling. It adds no network listener and does not open or focus a helper window. Without XWayland, it falls back to the normal foreground clipboard API; background clipboard access then depends on the compositor.

## Phone background connection

The Android foreground service owns a shared Flutter runtime; removing the phone window from Recents does not intentionally destroy the socket or file server. Reopening the app reattaches to that same runtime. SMS delivery and inbox reads no longer depend on an attached activity. A sticky service can restore saved pairing after an ordinary system process restart without showing permission prompts in the background.

On restrictive phones, allow PhoneLink's background battery usage. Android's **Force stop**, foreground task-manager **Stop**, and vendor battery restrictions can still stop or delay the app. These actions are not bypassed. This update needs the rebuilt APK; hot restart cannot apply it.

The ongoing Android notification updates to **PC connected**, **Waiting for PC**, or **Disconnected** when connection state changes. Reconnecting refreshes its shade entry without opening the phone app. In phone **Settings → Connection notification**, check whether Android allows the notification; tap the row to change it. Permission or channel blocking cannot be overridden by the app. The app does not pull open the notification panel.

While a saved connection is enabled, the running foreground service checks its own active notifications every 5 seconds and on screen-on/unlock. If its controls notification has disappeared, it silently posts that notification again without reconnecting or opening the app. It does not continually repost an existing notification. Disabled notifications/channels, manual disconnect, Force stop and Android's task-manager Stop remain respected. This restores a missing entry; Android 14+ can still allow individual dismissal, and system scheduling or process termination can delay restoration.

After phone reboot (once unlocked) or an APK update, the service attempts to restore an enabled, valid saved pairing. It does not start for a new/unpaired install or a pairing that was manually disconnected. A PC starting cannot wake a force-stopped phone app; open the phone app once in that case. No cloud push or public network endpoint is added.

## Artwork

- Selected source artwork: `assets/branding/concepts/selected-device-link.png`
- Master PNG: `assets/branding/phonelink-1024.png`
- Desktop PNG: `phonelink_desktop/assets/branding/`
- Android density variants and adaptive/monochrome layers: `phonelink_android/android/app/src/main/res/`

## Security protocol update

The encrypted protocol requires both apps to be updated and paired again. Keep OpenSSL installed on the Linux PC; local certificate generation uses it without contacting a network service. Old eight-character pairings no longer connect. Android needs a full native rerun/reinstall, not hot restart, for the secure background clipboard sender and backup protections. See [SECURITY.md](SECURITY.md) for the trust model and verification limits.
