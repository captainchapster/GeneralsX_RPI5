#!/usr/bin/env bash
# GeneralsX @build rpi5 12/10/2026
# Records where the CPU time goes while Zero Hour runs on a Raspberry Pi 5, with Linux perf.
#
# Usage: start it in a terminal, then start the game and play as usual:
#   ./scripts/qa/profile-pi5-zh.sh
#
# It waits for the game, samples every thread about 200 times a second until the game exits,
# and writes a text report to ~/GeneralsX/logs/zh-profile.txt (send that file).
# Installs perf (the linux-perf package) when it is missing. Needs sudo.
set -euo pipefail

LOG_DIR="${HOME}/GeneralsX/logs"
DATA="${LOG_DIR}/zh-profile.data"
REPORT="${LOG_DIR}/zh-profile.txt"
FREQUENCY="${FREQUENCY:-199}"
mkdir -p "${LOG_DIR}"

if ! command -v perf >/dev/null 2>&1 || ! perf --version >/dev/null 2>&1; then
  echo "== Installing perf"
  sudo apt-get install -y linux-perf
fi

echo "== Waiting for the game to start (start it now)"
pid=""
while [[ -z "${pid}" ]]; do
  pid="$(pgrep -x GeneralsXZH | head -1 || true)"
  [[ -n "${pid}" ]] || sleep 1
done
echo "== Recording GeneralsXZH (pid ${pid}) until it exits"
sudo perf record -F "${FREQUENCY}" -p "${pid}" -o "${DATA}" 2>&1 | grep -v "^\[ perf record: Woken up" || true

echo "== Writing ${REPORT}"
sudo chown "$(id -u):$(id -g)" "${DATA}"
{
  echo "# CPU time by thread"
  perf report -i "${DATA}" --stdio --no-children --sort comm --percent-limit 0.5 2>/dev/null | grep -v "^$"
  echo
  echo "# CPU time by library"
  perf report -i "${DATA}" --stdio --no-children --sort comm,dso --percent-limit 0.5 2>/dev/null | grep -v "^$"
  echo
  echo "# CPU time by function"
  perf report -i "${DATA}" --stdio --no-children --sort comm,dso,sym --percent-limit 0.2 2>/dev/null | grep -v "^$"
} > "${REPORT}"
echo "== Done: ${REPORT}"
