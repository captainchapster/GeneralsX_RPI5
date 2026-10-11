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

echo "== VK_ICD_FILENAMES=${VK_ICD_FILENAMES}"
echo "== DXVK_FILTER_DEVICE_NAME=${DXVK_FILTER_DEVICE_NAME}"
ls "${GAME_DIR}"/*.big >/dev/null 2>&1 || echo "WARNING: no .big files in ${GAME_DIR}"
ls "${HOME}/GeneralsX/Generals"/*.big >/dev/null 2>&1 || echo "WARNING: no base Generals .big files in ~/GeneralsX/Generals"

exec "${GAME_DIR}/run.sh" "$@"
