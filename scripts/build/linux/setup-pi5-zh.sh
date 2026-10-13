#!/usr/bin/env bash
# GeneralsX @build rpi5 12/10/2026
# Start Setup for Zero Hour on a Raspberry Pi 5. The package's Setup program runs this
# (setup-pi5-launcher.c), since file managers open a double-clicked script in an editor.
#
# Usage:
#   ./Setup               the Setup wizard on a desktop, the text installer otherwise
#   ./Setup --uninstall   remove the game (asks first)
#   ./Setup --text        always use the text installer
#   ./Setup --can-show    exit 0 when the wizard can open here (used by install-pi5-zh.sh)
#
# The wizard needs Python's GTK 3 bindings (python3-gi, gir1.2-gtk-3.0), which Raspberry Pi OS
# and most desktops have. Without them, or without a desktop, the text installer runs in a
# terminal, opening a terminal window first when Setup was double-clicked.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

can_show() {
  [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || return 1
  python3 -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk' >/dev/null 2>&1
}

case "${1:-}" in
  --can-show) can_show; exit $? ;;
  --text) shift; text=1 ;;
  *) text=0 ;;
esac

if [[ "${text}" == "0" ]] && can_show; then
  exec python3 "${SCRIPT_DIR}/setup-pi5-zh.py" "$@"
fi

# Double-clicked without the wizard: carry on in a terminal window.
if [[ ! -t 0 && -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && command -v x-terminal-emulator >/dev/null 2>&1; then
  exec x-terminal-emulator -e bash -c '"$0" --text "$@"; echo; read -r -p "Press Enter to close this window. "' \
    "${BASH_SOURCE[0]}" "$@"
fi

exec bash "${SCRIPT_DIR}/install-pi5-zh.sh" --text "$@"
