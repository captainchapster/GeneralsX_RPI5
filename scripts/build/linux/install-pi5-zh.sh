#!/usr/bin/env bash
# GeneralsX @build rpi5 12/10/2026
# Install Command & Conquer Generals Zero Hour (GeneralsX) on a Raspberry Pi 5.
#
# Usage, on the Pi (64-bit Raspberry Pi OS, Debian bookworm/trixie or Twister OS):
#   curl -fsSL https://github.com/captainchapster/GeneralsX_RPI5/releases/latest/download/install-pi5-zh.sh | bash
# or from an unpacked GeneralsXZH-pi5-aarch64.tar.gz:
#   ./install-pi5-zh.sh [--zh-data DIR] [--generals-data DIR] [--no-desktop-icon]
#   ./install-pi5-zh.sh --uninstall
#
# Run without a package next to it, the script downloads the latest Pi package from the
# GitHub releases of GENERALSX_PI5_REPO (default captainchapster/GeneralsX_RPI5).
#
# Installs:
#   ~/GeneralsX/GeneralsZH   game program and libraries, next to your Zero Hour data
#   ~/GeneralsX/Generals     your base Generals data (Zero Hour needs both)
#   ~/GeneralsX/pi5          launcher and the bundled Mesa V3DV Vulkan driver
#   a "C&C Generals Zero Hour" menu entry and desktop icon
# The system's own Mesa is not touched. No game data is downloaded: bring your own copy.
set -euo pipefail

REPO="${GENERALSX_PI5_REPO:-captainchapster/GeneralsX_RPI5}"
ASSET="GeneralsXZH-pi5-aarch64.tar.gz"
BASE_DIR="${HOME}/GeneralsX"
ZH_DIR="${BASE_DIR}/GeneralsZH"
GENERALS_DIR="${BASE_DIR}/Generals"
PI5_DIR="${BASE_DIR}/pi5"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"

zh_src=""
generals_src=""
desktop_args=()
uninstall=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --zh-data) zh_src="$2"; shift 2 ;;
    --generals-data) generals_src="$2"; shift 2 ;;
    --no-desktop-icon) desktop_args+=(--no-desktop-icon); shift ;;
    --uninstall) uninstall=1; shift ;;
    -h|--help) sed -n '2,21p' "${BASH_SOURCE[0]}" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

say() { printf '\n== %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

if [[ "${uninstall}" == "1" ]]; then
  [[ -x "${PI5_DIR}/install-pi5-desktop.sh" ]] && "${PI5_DIR}/install-pi5-desktop.sh" --remove
  rm -rf "${PI5_DIR}"
  rm -f "${ZH_DIR}/GeneralsXZH" "${ZH_DIR}/run.sh"
  echo "Removed GeneralsX. Your game data in ${ZH_DIR} and ${GENERALS_DIR} was left in place."
  exit 0
fi

# --- The machine -------------------------------------------------------------------------------
[[ "$(uname -m)" == "aarch64" ]] || die "this needs a 64-bit Pi OS (uname -m says $(uname -m))"
if command -v dpkg >/dev/null 2>&1 && [[ "$(dpkg --print-architecture)" != "arm64" ]]; then
  die "the system is $(dpkg --print-architecture) userland on a 64-bit kernel; install the 64-bit OS"
fi
model="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || true)"
if [[ "${model}" != *"Raspberry Pi 5"* ]]; then
  echo "WARNING: this was made for the Raspberry Pi 5; this machine is '${model:-unknown}'."
fi

# --- The package -------------------------------------------------------------------------------
pkg_dir=""
if [[ -d "${SCRIPT_DIR}/game" && -d "${SCRIPT_DIR}/mesa" ]]; then
  pkg_dir="${SCRIPT_DIR}"
else
  say "Downloading the latest Pi package from github.com/${REPO}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT
  curl -fL --progress-bar "https://github.com/${REPO}/releases/latest/download/${ASSET}" -o "${tmp}/${ASSET}" \
    || die "could not download ${ASSET} from the ${REPO} releases"
  tar -C "${tmp}" -xzf "${tmp}/${ASSET}"
  pkg_dir="${tmp}/GeneralsXZH-pi5"
fi
[[ -x "${pkg_dir}/game/GeneralsXZH" ]] || die "the package in ${pkg_dir} has no game/GeneralsXZH"
echo "Package: $(tr '\n' ' ' < "${pkg_dir}/VERSION" 2>/dev/null || echo unknown)"

# --- System libraries --------------------------------------------------------------------------
# The game bundles its own libraries; these are what the bundled Vulkan driver, SDL and the
# launcher use from the system. Package names differ between bookworm and trixie (t64).
pick() {
  local name
  for name in "$@"; do
    if apt-cache show "${name}" >/dev/null 2>&1; then echo "${name}"; return; fi
  done
}
if [[ "${SKIP_APT:-0}" == "1" ]]; then
  echo "Skipping system libraries (SKIP_APT=1)"
elif command -v apt-get >/dev/null 2>&1; then
  say "Installing the system libraries the game uses (needs sudo)"
  pkgs=(libvulkan1 libdrm2 libx11-xcb1 libxcb-dri3-0 libxcb-present0 libxcb-randr0 libxcb-sync1
        libxcb-xfixes0 libxshmfence1 libwayland-client0 libexpat1 libzstd1 x11-xserver-utils)
  for alt in "libasound2t64 libasound2" "libpulse0" "libudev1"; do
    name="$(pick ${alt})"
    [[ -n "${name}" ]] && pkgs+=("${name}")
  done
  sudo apt-get update
  sudo apt-get install -y "${pkgs[@]}"
else
  echo "WARNING: no apt-get; make sure Vulkan loader, X11/xcb and ALSA/PulseAudio libraries are installed."
fi

# --- Game data ---------------------------------------------------------------------------------
has_big() { [[ -n "$(compgen -G "$1/*.big" 2>/dev/null)" || -n "$(compgen -G "$1/*.BIG" 2>/dev/null)" ]]; }
ask_dir() {
  local prompt="$1" answer=""
  [[ -r /dev/tty ]] || return 0
  printf '%s\n> ' "${prompt}" > /dev/tty
  IFS= read -r answer < /dev/tty || true
  answer="${answer/#\~/${HOME}}"
  echo "${answer}"
}
copy_data() {
  local label="$1" src="$2" dest="$3"
  if [[ -z "${src}" ]] && ! has_big "${dest}"; then
    src="$(ask_dir "Where is your ${label} folder (the one with the .big files)? Leave empty to skip.")"
  fi
  [[ -n "${src}" ]] || return 0
  has_big "${src}" || die "${src} has no .big files; point at the ${label} install folder"
  say "Copying ${label} data from ${src} to ${dest}"
  mkdir -p "${dest}"
  cp -r "${src}/." "${dest}/"
}
copy_data "Zero Hour" "${zh_src}" "${ZH_DIR}"
copy_data "Generals (base game)" "${generals_src}" "${GENERALS_DIR}"

# --- Install -----------------------------------------------------------------------------------
say "Installing the game into ${ZH_DIR}"
mkdir -p "${ZH_DIR}" "${PI5_DIR}"
cp -r "${pkg_dir}/game/." "${ZH_DIR}/"

say "Installing the launcher and Vulkan driver into ${PI5_DIR}"
rm -rf "${PI5_DIR}/mesa"
cp -r "${pkg_dir}/mesa" "${PI5_DIR}/"
for f in run-pi5-zh.sh install-pi5-desktop.sh install-pi5-zh.sh generalsx-zh.png README-PI5.txt VERSION; do
  [[ -e "${pkg_dir}/${f}" ]] && cp "${pkg_dir}/${f}" "${PI5_DIR}/"
done
chmod +x "${PI5_DIR}"/*.sh
"${PI5_DIR}/install-pi5-desktop.sh" "${desktop_args[@]}"

# --- Done --------------------------------------------------------------------------------------
missing=()
has_big "${ZH_DIR}" || missing+=("Zero Hour data in ${ZH_DIR}")
has_big "${GENERALS_DIR}" || missing+=("Generals data in ${GENERALS_DIR}")
say "Installed"
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Still needed before the game can start:"
  printf '  - %s\n' "${missing[@]}"
  echo "Copy them in (see ${PI5_DIR}/README-PI5.txt), or re-run this script with --zh-data and --generals-data."
else
  echo "Start it from Games > C&C Generals Zero Hour, or the desktop icon."
fi
echo "Each run logs to ~/GeneralsX/logs/zh-last-run.log. To update, run this script again."
