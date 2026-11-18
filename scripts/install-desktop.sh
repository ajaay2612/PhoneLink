#!/usr/bin/env bash
# Install an already-built Linux bundle for the current user. Does not build or launch.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bundle_dir="${1:-$project_dir/phonelink_desktop/build/linux/x64/release/bundle}"
if [[ ! -x "$bundle_dir/phonelink_desktop" || ! -d "$bundle_dir/data" || ! -d "$bundle_dir/lib" ]]; then
  echo "A built Linux release bundle is required: $bundle_dir" >&2
  exit 1
fi
app_dir="${XDG_DATA_HOME:-$HOME/.local/share}/phonelink"
launcher_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
icon_dir="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/512x512/apps"
mkdir -p -- "$app_dir" "$launcher_dir" "$icon_dir"
# Preserve the complete Flutter bundle, including its local libraries and resources.
cp -a --remove-destination -- "$bundle_dir/." "$app_dir/"
cp -- "$project_dir/phonelink_desktop/assets/branding/phonelink.png" "$icon_dir/dev.phonelink.PhoneLink.png"
python3 - "$app_dir" "$launcher_dir/dev.phonelink.PhoneLink.desktop" "$icon_dir/dev.phonelink.PhoneLink.png" "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/dev.phonelink.PhoneLink.desktop" <<'PY'
import pathlib, sys
app = pathlib.Path(sys.argv[1])
# Desktop Exec is not shell syntax: quote and escape its reserved characters.
executable = str(app / 'phonelink_desktop')
quoted = '"' + executable.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%') + '"'
pathlib.Path(sys.argv[2]).write_text(
    '[Desktop Entry]\nType=Application\nName=PhoneLink\n'
    'Comment=Local messages, clipboard and files between your devices\n'
    f'Exec={quoted}\nIcon={sys.argv[3]}\nTerminal=false\n'
    'Categories=Utility;\nStartupWMClass=dev.phonelink.PhoneLink\n')
autostart = pathlib.Path(sys.argv[4])
autostart.parent.mkdir(parents=True, exist_ok=True)
autostart.write_text(
    '[Desktop Entry]\nType=Application\nName=PhoneLink\n'
    f'Exec={quoted} --start-in-tray\nIcon={sys.argv[3]}\n'
    'Terminal=false\nX-GNOME-Autostart-enabled=true\n')
PY
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$launcher_dir" || true
fi
echo "Installed PhoneLink in $app_dir"
