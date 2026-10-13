#!/usr/bin/env bash
# GeneralsX @build rpi5 12/10/2026
# Records where the CPU time goes while Zero Hour runs on a Raspberry Pi 5, with Linux perf.
#
# Usage: start it in a terminal, then start the game and play as usual:
#   ./scripts/qa/profile-pi5-zh.sh
#
# It waits for the game, samples every thread about 200 times a second until the game exits,
# and writes a text report to ~/GeneralsX/logs/zh-profile.txt (send that file).
#
# Call graph mode shows which game functions the time is spent under (for example how much of
# the frame goes to particles, water or shadows), not only the function at the top of the stack:
#   ./scripts/qa/profile-pi5-zh.sh callgraph
# Start the game and a replay, press Enter in this terminal once the replay is playing, and it
# records the game's main thread for RECORD_SECONDS seconds (default 60). Call stacks are large, so keep
# the window short.
#
# If writing the call graph report is interrupted, rebuild it from the recorded data without
# playing again:
#   ./scripts/qa/profile-pi5-zh.sh report
#
# Installs perf (the linux-perf package) when it is missing. Needs sudo.
set -euo pipefail

MODE="${1:-flat}"
LOG_DIR="${HOME}/GeneralsX/logs"
DATA="${LOG_DIR}/zh-profile.data"
REPORT="${LOG_DIR}/zh-profile.txt"
FOLDED="${LOG_DIR}/zh-profile-folded.txt"
SECONDS_TO_RECORD="${RECORD_SECONDS:-60}"
if [[ "${MODE}" == "callgraph" ]]; then
  FREQUENCY="${FREQUENCY:-99}"
else
  FREQUENCY="${FREQUENCY:-199}"
fi
mkdir -p "${LOG_DIR}"

if ! command -v perf >/dev/null 2>&1 || ! perf --version >/dev/null 2>&1; then
  echo "== Installing perf"
  sudo apt-get install -y linux-perf
fi

# Unwinding DWARF call stacks is slow on the Pi. --no-inline skips perf's per-address addr2line
# lookups for inlined functions, which otherwise make the report take far longer than the recording.
write_callgraph_report() {
  echo "== Writing ${REPORT} (this can take a few minutes)"
  {
    echo "# Main thread: time spent inside each function, including everything it calls"
    perf report -i "${DATA}" --stdio --no-inline --children --sort sym -g none --percent-limit 0.5 2>/dev/null | grep -v "^$"
  } > "${REPORT}"
  echo "== Writing ${FOLDED}"
  perf report -i "${DATA}" --stdio --no-inline --no-children --sort sym -g folded,0,caller,function,count 2>/dev/null \
    | grep -v "^#" | grep -v "^$" > "${FOLDED}" || true
  echo "== Done: send ${REPORT} and ${FOLDED}"
}

if [[ "${MODE}" == "report" ]]; then
  if [[ ! -f "${DATA}" ]]; then
    echo "No recording at ${DATA}; run with callgraph first" >&2
    exit 1
  fi
  sudo chown "$(id -u):$(id -g)" "${DATA}"
  write_callgraph_report
  exit 0
fi

echo "== Waiting for the game to start (start it now)"
pid=""
while [[ -z "${pid}" ]]; do
  pid="$(pgrep -x GeneralsXZH | head -1 || true)"
  [[ -n "${pid}" ]] || sleep 1
done

if [[ "${MODE}" == "callgraph" ]]; then
  read -r -p "== Start a replay, then press Enter to record ${SECONDS_TO_RECORD} s of the main thread " _
  echo "== Recording GeneralsXZH main thread (pid ${pid}) with call stacks for ${SECONDS_TO_RECORD} s"
  # The main thread's id is the process id. Stacks are unwound from DWARF debug info (RelWithDebInfo).
  sudo perf record -F "${FREQUENCY}" -t "${pid}" --call-graph dwarf,16384 -o "${DATA}" -- sleep "${SECONDS_TO_RECORD}" 2>&1 \
    | grep -v "^\[ perf record: Woken up" || true
  sudo chown "$(id -u):$(id -g)" "${DATA}"
  write_callgraph_report
  exit 0
fi

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
