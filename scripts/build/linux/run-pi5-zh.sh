#!/usr/bin/env bash
# GeneralsX @build rpi5 11/10/2026
# Launch the deployed Zero Hour build on a Raspberry Pi 5 with the V3DV Vulkan driver.
#
# Usage:
#   ./scripts/build/linux/run-pi5-zh.sh -win 2>&1 | tee run.log
#
# Expects:
#   - ./scripts/build/linux/deploy-linux-zh.sh linux-aarch64 has been run
#   - Zero Hour data (*.big) in ~/GeneralsX/GeneralsZH, base Generals data in ~/GeneralsX/Generals
#   - A Mesa 26+ V3DV driver in $MESA_PREFIX: the mesa/ folder next to this script when installed
#     from the Pi package, otherwise /opt/mesa-current (see build-pi5-mesa.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${MESA_PREFIX:-}" ]]; then
  MESA_PREFIX="/opt/mesa-current"
  [[ -d "${SCRIPT_DIR}/mesa" ]] && MESA_PREFIX="${SCRIPT_DIR}/mesa"
fi
GAME_DIR="${GAME_DIR:-${HOME}/GeneralsX/GeneralsZH}"

icd="$(compgen -G "${MESA_PREFIX}/share/vulkan/icd.d/broadcom_icd*.json" | head -1 || true)"
if [[ -z "${icd}" ]]; then
  echo "ERROR: no V3DV ICD JSON under ${MESA_PREFIX}/share/vulkan/icd.d (set MESA_PREFIX)"
  exit 1
fi
if [[ ! -x "${GAME_DIR}/run.sh" ]]; then
  echo "ERROR: ${GAME_DIR}/run.sh not found; run deploy-linux-zh.sh linux-aarch64 first"
  exit 1
fi

# Use only the Pi GPU. llvmpipe also reports Vulkan 1.3, and DXVK would quietly pick it
# if V3DV were rejected, so filtering by name makes that failure loud instead.
export VK_ICD_FILENAMES="${icd}"
export DXVK_FILTER_DEVICE_NAME="${DXVK_FILTER_DEVICE_NAME:-V3D}"
export DXVK_LOG_LEVEL="${DXVK_LOG_LEVEL:-info}"
# The V3DV driver is built for X11 only, so on a Wayland desktop run through XWayland.
if [[ -n "${DISPLAY:-}" && -z "${SDL_VIDEO_DRIVER:-}" ]]; then
  export SDL_VIDEO_DRIVER=x11
fi
# Fullscreen switches the display to the game's resolution instead of scaling every frame up to
# the desktop size, which costs the Pi's GPU a lot on large monitors. Set to 0 for desktop fullscreen.
export GENERALSX_EXCLUSIVE_FULLSCREEN="${GENERALSX_EXCLUSIVE_FULLSCREEN:-1}"

# Exclusive fullscreen keeps the picture's shape only if the monitor has a mode with its own aspect
# ratio near the game's height (the game then adds black bars). Ultrawide monitors often list only
# their native mode plus 4:3 ones, which they stretch, so add a reduced-blanking mode with the
# desktop's shape and the game's height to X11. It is gone after a reboot, so add it on every launch.
add_aspect_mode() {
  command -v xrandr >/dev/null 2>&1 && command -v cvt >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]] || return 0
  local options="${XDG_DATA_HOME:-${HOME}/.local/share}/GeneralsX/GeneralsZH/Options.ini"
  local height=768
  if [[ -f "${options}" ]]; then
    local res
    res="$(sed -n 's/^Resolution *= *[0-9][0-9]* \([0-9][0-9]*\).*/\1/p' "${options}" | head -1)"
    [[ -n "${res}" ]] && height="${res}"
  fi
  local output desktop dw dh
  read -r output desktop < <(xrandr --current | awk '/ connected/{for(i=3;i<=NF;i++) if($i ~ /^[0-9]+x[0-9]+\+/){sub(/\+.*/,"",$i); print $1, $i; exit}}')
  [[ -n "${output:-}" && -n "${desktop:-}" ]] || return 0
  dw="${desktop%x*}"; dh="${desktop#*x}"
  # Only monitors wider than 16:9 need it, and only below their native height.
  (( dw * 9 > dh * 16 + dh / 10 && height < dh )) || return 0
  local width=$(( (height * dw / dh + 4) / 8 * 8 ))
  local modeline name
  modeline="$(cvt -r "${width}" "${height}" 60 | sed -n 's/^Modeline //p' | tr -d '"')"
  name="${modeline%% *}"
  [[ -n "${name}" ]] || return 0
  if ! xrandr --current | grep -q "^ *${name} "; then
    xrandr --newmode ${modeline} 2>/dev/null || true
    xrandr --addmode "${output}" "${name}" 2>/dev/null || return 0
    echo "== Added display mode ${name} on ${output} for the ${dw}x${dh} desktop"
  fi
}
# Xfce's desktop moves icons that do not fit while the game has the display in a smaller mode, and
# keeps the new layout. Turn its icons off while the game runs and back on afterwards; it then lays
# them out again from the layout saved for the desktop resolution.
# xfconf only stores the icon style once it has been changed, so a missing property means the
# default (file icons); create it to hide them and remove it again afterwards.
ICONS_HIDDEN=0
ICON_STYLE_PREV=""
hide_desktop_icons() {
  command -v xfconf-query >/dev/null 2>&1 && pgrep -x xfdesktop >/dev/null 2>&1 || return 0
  local style=""
  if style="$(xfconf-query -c xfce4-desktop -p /desktop-icons/style 2>/dev/null)"; then
    [[ -n "${style}" && "${style}" != "0" ]] || return 0
    xfconf-query -c xfce4-desktop -p /desktop-icons/style -s 0 || return 0
    ICON_STYLE_PREV="${style}"
  else
    xfconf-query -c xfce4-desktop -p /desktop-icons/style -n -t int -s 0 || return 0
  fi
  ICONS_HIDDEN=1
  echo "== Hid desktop icons while the game runs"
}
restore_desktop_icons() {
  [[ "${ICONS_HIDDEN}" == "1" ]] || return 0
  if [[ -n "${ICON_STYLE_PREV}" ]]; then
    xfconf-query -c xfce4-desktop -p /desktop-icons/style -s "${ICON_STYLE_PREV}" || true
  else
    xfconf-query -c xfce4-desktop -p /desktop-icons/style -r || true
  fi
  ICONS_HIDDEN=0
}

if [[ "${GENERALSX_EXCLUSIVE_FULLSCREEN}" == "1" && " $* " != *" -win "* ]]; then
  add_aspect_mode || true
  hide_desktop_icons || true
fi

echo "== VK_ICD_FILENAMES=${VK_ICD_FILENAMES}"
echo "== DXVK_FILTER_DEVICE_NAME=${DXVK_FILTER_DEVICE_NAME}"
ls "${GAME_DIR}"/*.big >/dev/null 2>&1 || echo "WARNING: no .big files in ${GAME_DIR}"
ls "${HOME}/GeneralsX/Generals"/*.big >/dev/null 2>&1 || echo "WARNING: no base Generals .big files in ~/GeneralsX/Generals"

if [[ "${ICONS_HIDDEN}" != "1" ]]; then
  exec "${GAME_DIR}/run.sh" "$@"
fi
# Bring the desktop icons back however the game exits.
trap restore_desktop_icons EXIT
status=0
"${GAME_DIR}/run.sh" "$@" || status=$?
exit "${status}"
