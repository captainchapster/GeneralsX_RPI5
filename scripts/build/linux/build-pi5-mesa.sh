#!/usr/bin/env bash
# GeneralsX @build rpi5 12/10/2026
# Build the Mesa Vulkan driver for the Raspberry Pi 5 GPU (V3DV) that Zero Hour needs.
#
# Usage:
#   ./scripts/build/linux/build-pi5-mesa.sh                    # install into /opt/mesa-<version>
#   PREFIX=$HOME/mesa-pi5 ./scripts/build/linux/build-pi5-mesa.sh   # install anywhere else
#
# DXVK needs Vulkan 1.3 with VK_EXT_robustness2 null descriptors. V3DV has that from Mesa 26,
# while Debian bookworm ships 22.3 and trixie 25.0. Only the Vulkan driver is built and nothing
# system-wide is replaced: the desktop keeps its own Mesa, and the game opts in through
# VK_ICD_FILENAMES (run-pi5-zh.sh does that).
#
# With the default PREFIX, /opt/mesa-current is pointed at the new build. Set MESA_VER to build
# another release; 26.2.4 is the version the port was tested with.
set -euo pipefail

MESA_VER="${MESA_VER:-26.2.4}"
PREFIX="${PREFIX:-/opt/mesa-${MESA_VER}}"
WORK="${WORK:-${HOME}/src/mesa}"
JOBS="${JOBS:-$(nproc)}"
SUDO=""
[[ "$(id -u)" == "0" ]] || SUDO="sudo"

if [[ "${SKIP_APT:-0}" != "1" ]]; then
  echo "== Installing Mesa build dependencies"
  ${SUDO} apt-get update
  ${SUDO} apt-get install -y \
    build-essential ninja-build pkg-config bison flex glslang-tools wget xz-utils \
    python3 python3-venv \
    libdrm-dev libexpat1-dev zlib1g-dev libzstd-dev libudev-dev \
    libx11-dev libxext-dev libxfixes-dev libxdamage-dev libxrandr-dev libxxf86vm-dev x11proto-dev \
    libx11-xcb-dev libxcb1-dev libxcb-dri2-0-dev libxcb-dri3-dev libxcb-glx0-dev libxcb-keysyms1-dev \
    libxcb-present-dev libxcb-randr0-dev libxcb-shm0-dev libxcb-sync-dev libxcb-xfixes0-dev \
    libxshmfence-dev
fi

# Mesa 26 needs Meson 1.4 or newer, and bookworm ships 1.0. Use Meson and Mesa's Python build
# modules from a venv so the system's packages don't matter.
VENV="${MESA_VENV:-${HOME}/.local/mesa-venv}"
python3 -m venv "${VENV}"
"${VENV}/bin/pip" install --quiet --upgrade "meson>=1.4" mako pyyaml ply packaging
export PATH="${VENV}/bin:${PATH}"
meson --version

mkdir -p "${WORK}"
cd "${WORK}"
[[ -f "mesa-${MESA_VER}.tar.xz" ]] || wget "https://archive.mesa3d.org/mesa-${MESA_VER}.tar.xz"
[[ -d "mesa-${MESA_VER}" ]] || tar xf "mesa-${MESA_VER}.tar.xz"
cd "mesa-${MESA_VER}"

rm -rf build
meson setup build \
  -Dprefix="${PREFIX}" -Dbuildtype=release \
  -Dvulkan-drivers=broadcom -Dgallium-drivers= -Dllvm=disabled \
  -Dplatforms=x11 -Dopengl=false -Degl=disabled -Dgbm=disabled -Dglx=disabled \
  -Dgles1=disabled -Dgles2=disabled -Dvideo-codecs=
ninja -C build -j "${JOBS}"

# Install with sudo only when the prefix is not writable (e.g. under /opt).
install_sudo=""
mkdir -p "${PREFIX}" 2>/dev/null || true
[[ -w "${PREFIX}" ]] || install_sudo="${SUDO}"
${install_sudo} ninja -C build install
if [[ "${PREFIX}" == "/opt/mesa-${MESA_VER}" ]]; then
  ${install_sudo} ln -sfn "${PREFIX}" /opt/mesa-current
fi

icd="$(compgen -G "${PREFIX}/share/vulkan/icd.d/broadcom_icd*.json" | head -1 || true)"
if [[ -z "${icd}" ]]; then
  echo "ERROR: the build did not install a V3DV ICD JSON under ${PREFIX}/share/vulkan/icd.d"
  exit 1
fi
echo
echo "== Installed Mesa ${MESA_VER} V3DV into ${PREFIX}"
echo "ICD file: ${icd}"
if command -v vulkaninfo >/dev/null 2>&1 && [[ -e /dev/dri/renderD128 ]]; then
  VK_ICD_FILENAMES="${icd}" vulkaninfo --summary 2>&1 | grep -A4 "^GPU0" || true
fi
