#!/usr/bin/env bash
# GeneralsX @build rpi5 12/10/2026
# Package a Raspberry Pi 5 build of Zero Hour, with its Mesa V3DV driver, into one tarball.
#
# Usage, from the repository root, after build-pi5-zh.sh and build-pi5-mesa.sh:
#   ./scripts/build/linux/bundle-pi5-zh.sh                       # Mesa from /opt/mesa-current
#   MESA_PREFIX=$HOME/mesa-pi5 ./scripts/build/linux/bundle-pi5-zh.sh
#
# Output: GeneralsXZH-pi5-aarch64.tar.gz in the repository root (OUTPUT_TARBALL to change), holding
#   GeneralsXZH-pi5/
#     game/                 GeneralsXZH, its libraries and run.sh (installed next to the game data)
#     mesa/                 V3DV Vulkan driver and an ICD JSON that points at it relatively
#     install-pi5-zh.sh     installer (see its header)
#     run-pi5-zh.sh         launcher
#     install-pi5-desktop.sh, generalsx-zh.png, README-PI5.txt, VERSION
# No game data is included.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
PRESET="linux-aarch64"
MESA_PREFIX="${MESA_PREFIX:-/opt/mesa-current}"
OUTPUT_TARBALL="${OUTPUT_TARBALL:-${PROJECT_ROOT}/GeneralsXZH-pi5-aarch64.tar.gz}"
STAGE_ROOT="$(mktemp -d)"
STAGE="${STAGE_ROOT}/GeneralsXZH-pi5"
trap 'rm -rf "${STAGE_ROOT}"' EXIT

icd_src="$(compgen -G "${MESA_PREFIX}/share/vulkan/icd.d/broadcom_icd*.json" | head -1 || true)"
driver_src="$(find -L "${MESA_PREFIX}" -name 'libvulkan_broadcom.so' -print -quit 2>/dev/null || true)"
if [[ -z "${icd_src}" || -z "${driver_src}" ]]; then
  echo "ERROR: no V3DV driver under ${MESA_PREFIX}; run build-pi5-mesa.sh or set MESA_PREFIX"
  exit 1
fi

echo "== Staging the game"
mkdir -p "${STAGE}/game"
GENERALSX_DEPLOY_DIR="${STAGE}/game" "${SCRIPT_DIR}/deploy-linux-zh.sh" "${PRESET}"

echo "== Staging the Mesa V3DV driver from ${MESA_PREFIX}"
mkdir -p "${STAGE}/mesa/lib" "${STAGE}/mesa/share/vulkan/icd.d"
cp -L "${driver_src}" "${STAGE}/mesa/lib/libvulkan_broadcom.so"
# The Vulkan loader resolves a library_path containing a slash relative to the JSON file.
sed -E 's#("library_path"[[:space:]]*:[[:space:]]*")[^"]*"#\1../../../lib/libvulkan_broadcom.so"#' \
  "${icd_src}" > "${STAGE}/mesa/share/vulkan/icd.d/$(basename "${icd_src}")"
mesa_version="$(basename "$(readlink -f "${MESA_PREFIX}")")"

echo "== Staging the launcher and installer"
cp "${SCRIPT_DIR}/install-pi5-zh.sh" "${SCRIPT_DIR}/run-pi5-zh.sh" "${SCRIPT_DIR}/install-pi5-desktop.sh" "${STAGE}/"
cp "${PROJECT_ROOT}/assets/generalsx-zh_icon.png" "${STAGE}/generalsx-zh.png"
cp "${PROJECT_ROOT}/docs/HOWTO/RASPBERRY_PI_5.md" "${STAGE}/README-PI5.txt"
{
  echo "commit=$(git -C "${PROJECT_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "mesa=${mesa_version}"
  echo "built=$(date -u +%Y-%m-%d)"
} > "${STAGE}/VERSION"

echo "== Writing ${OUTPUT_TARBALL}"
tar -C "${STAGE_ROOT}" -czf "${OUTPUT_TARBALL}" GeneralsXZH-pi5
ls -la "${OUTPUT_TARBALL}"
cat "${STAGE}/VERSION"
