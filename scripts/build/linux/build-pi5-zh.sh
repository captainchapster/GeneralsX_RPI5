#!/usr/bin/env bash
# GeneralsX @build rpi5 11/10/2026
# Native build of Zero Hour (GeneralsXZH) on a Raspberry Pi 5 (Linux aarch64).
#
# Usage, from the repository root:
#   ./scripts/build/linux/build-pi5-zh.sh 2>&1 | tee build.log
#
# What it does:
#   1. Installs build dependencies with apt (skip with SKIP_APT=1)
#   2. Uses $VCPKG_ROOT, or clones and bootstraps vcpkg into ~/vcpkg
#   3. Configures with the linux-aarch64 preset (DXVK is built from source)
#   4. Builds GeneralsXZH into build/linux-aarch64/
#
# The first run is slow: vcpkg compiles FFmpeg, curl and friends from source.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PRESET="linux-aarch64"
BUILD_DIR="${PROJECT_ROOT}/build/${PRESET}"
JOBS="${JOBS:-$(nproc)}"

cd "${PROJECT_ROOT}"
echo "== GeneralsX Pi 5 build at $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
uname -m

# libgbm-dev is left out on purpose: it must match the installed Mesa exactly, and
# Pi setups that pin Mesa (e.g. alongside armhf/box86 packages) cannot install it.
# SDL3 only needs it for its KMSDRM backend, which the desktop build doesn't use.
if [[ "${SKIP_APT:-0}" != "1" ]]; then
  echo "== Installing build dependencies"
  sudo apt-get update
  sudo apt-get install -y \
    build-essential git curl zip unzip tar pkg-config ninja-build meson \
    autoconf autoconf-archive automake libtool bison flex gperf nasm \
    python3 python3-venv python3-pip glslang-tools patchelf \
    libvulkan-dev vulkan-tools \
    libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxi-dev libxss-dev \
    libxfixes-dev libxtst-dev libxkbcommon-dev libwayland-dev wayland-protocols \
    libdrm-dev libegl-dev libgles-dev \
    libasound2-dev libpulse-dev libudev-dev libdbus-1-dev \
    libpng-dev libjpeg-dev libtiff-dev libwebp-dev  # SDL3_image links the system ones (cmake/sdl3.cmake)
  # Optional for SDL3; Raspberry Pi OS has it, plain Debian bookworm only in backports.
  if apt-cache show libdisplay-info-dev >/dev/null 2>&1; then
    sudo apt-get install -y libdisplay-info-dev
  fi
fi

# vcpkg and some ports need a newer CMake than Debian bookworm's 3.25.
need_cmake="3.30"
have_cmake="$(cmake --version 2>/dev/null | head -1 | awk '{print $3}' || true)"
if [[ -z "${have_cmake}" ]] || [[ "$(printf '%s\n%s\n' "${need_cmake}" "${have_cmake}" | sort -V | head -1)" != "${need_cmake}" ]]; then
  echo "== CMake ${have_cmake:-missing} is older than ${need_cmake}; installing a newer one into ~/.local/zh-venv"
  python3 -m venv "${HOME}/.local/zh-venv"
  "${HOME}/.local/zh-venv/bin/pip" install --upgrade "cmake>=${need_cmake}"
  export PATH="${HOME}/.local/zh-venv/bin:${PATH}"
fi
cmake --version | head -1

# vcpkg has no prebuilt tool binaries for aarch64 Linux; use the system ones.
export VCPKG_FORCE_SYSTEM_BINARIES=1
if [[ -z "${VCPKG_ROOT:-}" ]]; then
  export VCPKG_ROOT="${HOME}/vcpkg"
fi
if [[ ! -x "${VCPKG_ROOT}/vcpkg" ]]; then
  echo "== Bootstrapping vcpkg in ${VCPKG_ROOT}"
  [[ -d "${VCPKG_ROOT}/.git" ]] || git clone https://github.com/microsoft/vcpkg.git "${VCPKG_ROOT}"
  "${VCPKG_ROOT}/bootstrap-vcpkg.sh" -disableMetrics
fi

echo "== Configuring (${PRESET})"
cmake --preset "${PRESET}"

echo "== Building with ${JOBS} jobs"
cmake --build "${BUILD_DIR}" --target z_generals -j "${JOBS}"
cmake --build "${BUILD_DIR}" --target dxvk_d3d8_install

echo
echo "== Done"
ls -la "${BUILD_DIR}/GeneralsMD/GeneralsXZH" "${BUILD_DIR}"/libdxvk_d3d*.so*
echo
echo "Deploy with: ./scripts/build/linux/deploy-linux-zh.sh ${PRESET}"
echo "Then run:    ./scripts/build/linux/run-pi5-zh.sh -win"
echo "Menu entry:  ./scripts/build/linux/install-pi5-desktop.sh (once)"
