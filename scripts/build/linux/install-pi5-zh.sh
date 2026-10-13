#!/usr/bin/env bash
# GeneralsX @build rpi5 12/10/2026
# Install Command & Conquer Generals Zero Hour (GeneralsX) on a Raspberry Pi 5.
#
# Most people double-click Setup in the GeneralsXZH-pi5 folder instead (setup-pi5-zh.py); it
# drives this script. From a terminal (64-bit Raspberry Pi OS, Debian bookworm/trixie, Twister OS):
#   curl -fsSL https://github.com/captainchapster/GeneralsX_RPI5/releases/latest/download/install-pi5-zh.sh | bash
# or from an unpacked GeneralsXZH-pi5-aarch64.tar.gz (the script is in its hidden .setup folder):
#   ./install-pi5-zh.sh [--zh-data DIR] [--generals-data DIR] [--no-desktop-icon] [--text]
#   ./install-pi5-zh.sh --uninstall
#
# Run without a package next to it, the script downloads the latest Pi package from the
# GitHub releases of GENERALSX_PI5_REPO (default captainchapster/GeneralsX_RPI5), then opens the
# Setup wizard when a desktop is available (--text keeps it in the terminal).
#
# Installs:
#   ~/GeneralsX/GeneralsZH   game program and libraries, next to your Zero Hour data
#   ~/GeneralsX/Generals     your base Generals data (Zero Hour needs both)
#   ~/GeneralsX/pi5          launcher, Setup and the bundled Mesa V3DV Vulkan driver
#   a "C&C Generals Zero Hour" menu entry and desktop icon
# The system's own Mesa is not touched. No game data is downloaded: bring your own copy. The
# installer finds the Generals and Zero Hour folders on USB sticks, other drives or in the home
# folder, and otherwise asks for them in the terminal.
#
# Options used by the Setup wizard:
#   --detect             print the game folders found (zh=DIR, generals=DIR) and exit
#   --missing-packages   print the system packages still to install and exit
#   --gui                no questions; report progress as "@@ PERCENT MESSAGE" lines
set -euo pipefail

REPO="${GENERALSX_PI5_REPO:-captainchapster/GeneralsX_RPI5}"
ASSET="GeneralsXZH-pi5-aarch64.tar.gz"
BASE_DIR="${HOME}/GeneralsX"
ZH_DIR="${BASE_DIR}/GeneralsZH"
GENERALS_DIR="${BASE_DIR}/Generals"
PI5_DIR="${BASE_DIR}/pi5"
MANIFEST="${PI5_DIR}/installed-files.txt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"

zh_src=""
generals_src=""
desktop_args=()
mode="install"
gui=0
text=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --zh-data) zh_src="$2"; shift 2 ;;
    --generals-data) generals_src="$2"; shift 2 ;;
    --no-desktop-icon) desktop_args+=(--no-desktop-icon); shift ;;
    --uninstall) mode="uninstall"; shift ;;
    --detect) mode="detect"; shift ;;
    --missing-packages) mode="packages"; shift ;;
    --gui) gui=1; shift ;;
    --text) text=1; shift ;;
    -h|--help) sed -n '2,29p' "${BASH_SOURCE[0]}" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

say() { printf '\n== %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
# progress PERCENT MESSAGE: a progress line for the wizard, a heading in the terminal.
progress() {
  if [[ "${gui}" == "1" ]]; then
    printf '@@ %s %s\n' "$1" "$2"
  else
    say "$2"
  fi
}

# --- Game data detection -----------------------------------------------------------------------
# A Zero Hour folder holds INIZH.big and a Generals folder INI.big (any letter case).
has_file() { [[ -n "$(find "$1" -maxdepth 1 -iname "$2" -print -quit 2>/dev/null)" ]]; }
is_zh_dir() { has_file "$1" 'INIZH.big'; }
is_generals_dir() { has_file "$1" 'INI.big' && ! is_zh_dir "$1"; }

# find_data_dir CHECK MARKER: look on USB sticks and other mounted drives, then in the home folder.
find_data_dir() {
  local check="$1" marker="$2" root found
  for root in "/media/${USER:-}" /media "/run/media/${USER:-}" /mnt "${HOME}"; do
    [[ -d "${root}" ]] || continue
    while IFS= read -r found; do
      if "${check}" "$(dirname "${found}")"; then
        dirname "${found}"
        return
      fi
    done < <(find "${root}" -maxdepth 5 -path "${BASE_DIR}" -prune -o -iname "${marker}" -print 2>/dev/null || true)
  done
}

# detect_data DEST CHECK MARKER: the installed folder if it already has the data, else a found one.
detect_data() {
  if "$2" "$1"; then echo "$1"; else find_data_dir "$2" "$3"; fi
}

# --- System libraries --------------------------------------------------------------------------
# The game bundles its own libraries; these are what the bundled Vulkan driver, SDL and the
# launcher use from the system. Package names differ between bookworm and trixie (t64).
pick() {
  local name
  for name in "$@"; do
    if apt-cache show "${name}" >/dev/null 2>&1; then echo "${name}"; return; fi
  done
}
is_installed() { [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]]; }
missing_packages() {
  local pkgs=(libvulkan1 libdrm2 libx11-xcb1 libxcb-dri3-0 libxcb-present0 libxcb-randr0 libxcb-sync1
              libxcb-xfixes0 libxshmfence1 libwayland-client0 libexpat1 libzstd1 x11-xserver-utils)
  local alt name
  for alt in "libasound2t64 libasound2" "libpulse0" "libudev1"; do
    name="$(pick ${alt})"
    [[ -n "${name}" ]] && pkgs+=("${name}")
  done
  for name in "${pkgs[@]}"; do
    is_installed "${name}" || printf '%s\n' "${name}"
  done
}

case "${mode}" in
  detect)
    echo "zh=$(detect_data "${ZH_DIR}" is_zh_dir 'INIZH.big')"
    echo "generals=$(detect_data "${GENERALS_DIR}" is_generals_dir 'INI.big')"
    exit 0 ;;
  packages)
    command -v dpkg-query >/dev/null 2>&1 && missing_packages | tr '\n' ' '
    echo
    exit 0 ;;
  uninstall)
    [[ -x "${PI5_DIR}/install-pi5-desktop.sh" ]] && "${PI5_DIR}/install-pi5-desktop.sh" --remove
    if [[ -f "${MANIFEST}" ]]; then
      while IFS= read -r f; do
        [[ -n "${f}" && "${f}" != *..* ]] && rm -f "${ZH_DIR}/${f}"
      done < "${MANIFEST}"
    else
      rm -f "${ZH_DIR}/GeneralsXZH" "${ZH_DIR}/run.sh"
    fi
    rm -rf "${PI5_DIR}"
    echo "Removed GeneralsX. Your game data in ${ZH_DIR} and ${GENERALS_DIR} was left in place."
    exit 0 ;;
esac

# --- The machine -------------------------------------------------------------------------------
[[ "$(uname -m)" == "aarch64" ]] || die "this needs a 64-bit Pi OS (uname -m says $(uname -m))"
if command -v dpkg >/dev/null 2>&1 && [[ "$(dpkg --print-architecture)" != "arm64" ]]; then
  die "the system is $(dpkg --print-architecture) userland on a 64-bit kernel; install the 64-bit OS"
fi
model="$(tr -d '\0' 2>/dev/null < /proc/device-tree/model || true)"
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
  pkg_dir="${tmp}/GeneralsXZH-pi5/.setup"
  # On a desktop, carry on in the Setup wizard. It runs from the download, which is removed after.
  if [[ "${text}" == "0" && "${gui}" == "0" ]] && bash "${pkg_dir}/setup-pi5-zh.sh" --can-show; then
    bash "${pkg_dir}/setup-pi5-zh.sh"
    exit $?
  fi
fi
[[ -x "${pkg_dir}/game/GeneralsXZH" ]] || die "the package in ${pkg_dir} has no game/GeneralsXZH"
echo "Package: $(tr '\n' ' ' < "${pkg_dir}/VERSION" 2>/dev/null || echo unknown)"

# --- System libraries --------------------------------------------------------------------------
if [[ "${SKIP_APT:-0}" == "1" ]]; then
  echo "Skipping system libraries (SKIP_APT=1)"
elif command -v apt-get >/dev/null 2>&1; then
  mapfile -t pkgs < <(missing_packages)
  if [[ ${#pkgs[@]} -gt 0 ]]; then
    progress 2 "Installing system components (needs sudo)"
    sudo apt-get update
    sudo apt-get install -y "${pkgs[@]}"
  fi
else
  echo "WARNING: no apt-get; make sure Vulkan loader, X11/xcb and ALSA/PulseAudio libraries are installed."
fi

# --- Copying with progress ---------------------------------------------------------------------
# copy_tree SRC DEST FROM TO MESSAGE [LIST]: copy SRC into DEST file by file, reporting progress
# from FROM to TO percent, and append each copied path (relative to DEST) to LIST when given.
copy_tree() {
  local src="$1" dest="$2" from="$3" to="$4" message="$5" list="${6:-}"
  local total done_bytes=0 last=-1 pct rel size
  total="$(du -sb "${src}" 2>/dev/null | cut -f1)"
  [[ "${total:-0}" -gt 0 ]] || total=1
  progress "${from}" "${message}"
  mkdir -p "${dest}"
  while IFS= read -r -d '' rel; do
    rel="${rel#./}"
    if [[ -d "${src}/${rel}" ]]; then
      mkdir -p "${dest}/${rel}"
      continue
    fi
    [[ "${gui}" == "1" ]] && printf 'Copying: %s\n' "${rel}"
    cp -a "${src}/${rel}" "${dest}/${rel}"
    [[ -n "${list}" ]] && printf '%s\n' "${rel}" >> "${list}"
    size="$(stat -c %s "${src}/${rel}" 2>/dev/null || echo 0)"
    done_bytes=$((done_bytes + size))
    pct=$((from + (to - from) * done_bytes / total))
    if [[ "${pct}" != "${last}" ]]; then
      [[ "${gui}" == "1" ]] && printf '@@ %s %s\n' "${pct}" "${message}"
      last="${pct}"
    fi
  done < <(cd "${src}" && find . -mindepth 1 \( -type d -o -type f -o -type l \) -print0 | sort -z)
}

# --- Game data ---------------------------------------------------------------------------------
ask_dir() {
  local label="$1" answer=""
  [[ "${gui}" == "0" && -r /dev/tty ]] || return 0
  printf 'Where is your %s folder (the one with the .big files)? Leave empty to skip.\n> ' "${label}" > /dev/tty
  IFS= read -r answer < /dev/tty || true
  echo "${answer/#\~/${HOME}}"
}

# copy_data LABEL SOURCE DEST CHECK MARKER FROM TO
copy_data() {
  local label="$1" src="$2" dest="$3" check="$4" marker="$5"
  if [[ -z "${src}" ]]; then
    if "${check}" "${dest}"; then
      echo "${label} data is already in ${dest}"
      return 0
    fi
    src="$(find_data_dir "${check}" "${marker}")"
    [[ -n "${src}" ]] && echo "Found ${label} data in ${src}"
  fi
  [[ -n "${src}" ]] || src="$(ask_dir "${label}")"
  [[ -n "${src}" ]] || return 0
  "${check}" "${src}" || die "${src} has no ${marker}; choose the ${label} install folder"
  if [[ "$(realpath "${src}")" == "$(realpath -m "${dest}")" ]]; then
    echo "${label} data is already in ${dest}"
    return 0
  fi
  copy_tree "${src}" "${dest}" "$6" "$7" "Copying ${label} files"
}
copy_data "Zero Hour" "${zh_src}" "${ZH_DIR}" is_zh_dir 'INIZH.big' 5 45
copy_data "Generals" "${generals_src}" "${GENERALS_DIR}" is_generals_dir 'INI.big' 45 80

# --- Install -----------------------------------------------------------------------------------
mkdir -p "${PI5_DIR}"
manifest_new="$(mktemp)"
copy_tree "${pkg_dir}/game" "${ZH_DIR}" 80 92 "Installing the game" "${manifest_new}"

progress 93 "Installing the graphics driver"
rm -rf "${PI5_DIR}/mesa"
cp -r "${pkg_dir}/mesa" "${PI5_DIR}/"
# The package keeps Setup one folder up, next to its hidden .setup folder.
for f in "../Setup" "Setup"; do
  [[ -x "${pkg_dir}/${f}" ]] && cp "${pkg_dir}/${f}" "${PI5_DIR}/Setup"
done
for f in setup-pi5-zh.sh setup-pi5-zh.py run-pi5-zh.sh install-pi5-desktop.sh install-pi5-zh.sh \
         generalsx-zh.png README-PI5.txt LICENSE.txt VERSION; do
  [[ -e "${pkg_dir}/${f}" ]] && cp "${pkg_dir}/${f}" "${PI5_DIR}/"
done
chmod +x "${PI5_DIR}"/*.sh
[[ -e "${PI5_DIR}/Setup" ]] && chmod +x "${PI5_DIR}/Setup"
mv "${manifest_new}" "${MANIFEST}"

progress 97 "Creating shortcuts"
"${PI5_DIR}/install-pi5-desktop.sh" "${desktop_args[@]}"

# --- Done --------------------------------------------------------------------------------------
progress 100 "Done"
missing=()
is_zh_dir "${ZH_DIR}" || missing+=("Zero Hour data in ${ZH_DIR}")
is_generals_dir "${GENERALS_DIR}" || missing+=("Generals data in ${GENERALS_DIR}")
say "Installed"
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Still needed before the game can start:"
  printf '  - %s\n' "${missing[@]}"
  echo "Copy them in (see ${PI5_DIR}/README-PI5.txt), or re-run this script with --zh-data and --generals-data."
else
  echo "Start it from Games > C&C Generals Zero Hour, or the desktop icon."
fi
echo "Each run logs to ~/GeneralsX/logs/zh-last-run.log. To update, run this script again."
