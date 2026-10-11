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
#   - A Mesa with V3DV Vulkan 1.3 in $MESA_PREFIX (default /opt/mesa-current, see phase0/build-mesa.sh)
set -euo pipefail

MESA_PREFIX="${MESA_PREFIX:-/opt/mesa-current}"
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
# Fullscreen switches the display to the game's resolution instead of scaling every frame up to
# the desktop size, which costs the Pi's GPU a lot on large monitors. Set to 0 for desktop fullscreen.
export GENERALSX_EXCLUSIVE_FULLSCREEN="${GENERALSX_EXCLUSIVE_FULLSCREEN:-1}"

# Exclusive fullscreen keeps the picture's shape only if the monitor has a mode with its own aspect
# ratio near the game's height (the game then adds black bars). Ultrawide monitors often list only
# their native mode plus 4:3 ones, which they stretch, so add a reduced-blanking mode with the
# desktop's shape and the game's height to X11. It is gone after a reboot, so add it on every launch.
# Switch to it before the game starts and back afterwards: a monitor takes a second or two to re-sync
# after a mode change, which hid the EA logo movie when the game switched modes itself.
ASPECT_OUTPUT=""
ASPECT_RESTORE_MODE=""
ASPECT_RESTORE_RATE=""
ICON_LAYOUT_BACKUP=""
# Xfce's desktop moves icons that no longer fit when the screen shrinks and saves the new layout, so
# keep a copy of its icon layout files and put them back once the desktop mode is restored.
XFDESKTOP_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/xfce4/desktop"
backup_icon_layout() {
  compgen -G "${XFDESKTOP_DIR}/icons.screen*.rc" >/dev/null || return 0
  ICON_LAYOUT_BACKUP="$(mktemp -d)"
  cp -p "${XFDESKTOP_DIR}"/icons.screen*.rc "${ICON_LAYOUT_BACKUP}/"
}
restore_icon_layout() {
  [[ -n "${ICON_LAYOUT_BACKUP}" ]] || return 0
  # Let xfdesktop finish reacting to the mode change before the layout goes back.
  sleep 2
  cp -p "${ICON_LAYOUT_BACKUP}"/icons.screen*.rc "${XFDESKTOP_DIR}/"
  rm -rf "${ICON_LAYOUT_BACKUP}"
  ICON_LAYOUT_BACKUP=""
  if pgrep -x xfdesktop >/dev/null 2>&1; then
    xfdesktop --reload >/dev/null 2>&1 || true
  fi
}
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
  local current_mode current_rate
  read -r current_mode current_rate < <(xrandr --current | awk '/^ +[0-9]/{for(i=2;i<=NF;i++) if($i ~ /\*/){r=$i; gsub(/[*+]/,"",r); print $1, r; exit}}')
  [[ -n "${current_mode:-}" ]] || return 0
  backup_icon_layout
  if xrandr --output "${output}" --mode "${name}"; then
    ASPECT_OUTPUT="${output}"
    ASPECT_RESTORE_MODE="${current_mode}"
    ASPECT_RESTORE_RATE="${current_rate}"
    echo "== Switched ${output} to ${name} for the game"
  else
    rm -rf "${ICON_LAYOUT_BACKUP}"
    ICON_LAYOUT_BACKUP=""
  fi
}
restore_desktop_mode() {
  [[ -n "${ASPECT_OUTPUT}" ]] || return 0
  xrandr --output "${ASPECT_OUTPUT}" --mode "${ASPECT_RESTORE_MODE}" ${ASPECT_RESTORE_RATE:+--rate "${ASPECT_RESTORE_RATE}"} || true
  ASPECT_OUTPUT=""
  restore_icon_layout
}
if [[ "${GENERALSX_EXCLUSIVE_FULLSCREEN}" == "1" && " $* " != *" -win "* ]]; then
  add_aspect_mode || true
fi

echo "== VK_ICD_FILENAMES=${VK_ICD_FILENAMES}"
echo "== DXVK_FILTER_DEVICE_NAME=${DXVK_FILTER_DEVICE_NAME}"
ls "${GAME_DIR}"/*.big >/dev/null 2>&1 || echo "WARNING: no .big files in ${GAME_DIR}"
ls "${HOME}/GeneralsX/Generals"/*.big >/dev/null 2>&1 || echo "WARNING: no base Generals .big files in ~/GeneralsX/Generals"

if [[ -z "${ASPECT_OUTPUT}" ]]; then
  exec "${GAME_DIR}/run.sh" "$@"
fi
# Restore the desktop mode however the game exits.
trap restore_desktop_mode EXIT INT TERM
status=0
"${GAME_DIR}/run.sh" "$@" || status=$?
exit "${status}"
