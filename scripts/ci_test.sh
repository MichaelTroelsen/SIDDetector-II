#!/usr/bin/env bash
# =============================================================================
# ci_test.sh — Build test suite and run it headlessly in VICE.
#
# Usage:
#   bash scripts/ci_test.sh
#   (or: make ci)
#
# Exit codes:
#   0 — all 27 tests passed
#   1 — build failed, VICE did not exit cleanly, or pass count is wrong
#
# How it works:
#   VICE is launched with -remotemonitor on a dynamically chosen free port so
#   scripts/vice_monitor.py can connect, set a breakpoint at td_spin, wait for
#   it to fire, then save $07E8 (pass_count in off-screen RAM) to
#   tests/ci_result.bin.  A dynamic port avoids TCP TIME_WAIT collisions
#   between back-to-back runs.
#   This script reads byte 2 of that PRG file (past the 2-byte load-address
#   header) and compares it to the expected pass count.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

KICKASS="java -jar C:/debugger/kickasm/KickAss.jar"
VICE="C:/winvice/bin/x64sc.exe"
PYTHON="/c/Python314/python"
EXPECTED_PASS=27   # $1B hex

# ---- Build ----------------------------------------------------------------
echo "=== CI: build test_suite.prg ==="
$KICKASS tests/test_suite.asm -o tests/test_suite.prg

# ---- Kill any stale VICE processes ----------------------------------------
cmd //c "taskkill /F /IM x64sc.exe" 2>/dev/null || true

# ---- Pick a free TCP port for the remote monitor --------------------------
MONITOR_PORT=$("$PYTHON" -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")

# ---- Run VICE in background with remote monitor ---------------------------
echo "=== CI: run tests in VICE (remote monitor on port $MONITOR_PORT) ==="
rm -f tests/ci_result.bin

"$VICE" \
    -autostart tests/test_suite.prg \
    -remotemonitor \
    -remotemonitoraddress "ip4://127.0.0.1:${MONITOR_PORT}" \
    +confirmonexit \
    2>/dev/null &
VICE_PID=$!

# ---- Connect via Python monitor client ------------------------------------
TD_SPIN=$(grep ' \.td_spin$' tests/test_suite.vs | awk '{print $2}' | sed 's/C://')
if [ -z "$TD_SPIN" ]; then
    echo "ERROR: could not find td_spin in tests/test_suite.vs" >&2
    kill "$VICE_PID" 2>/dev/null || true
    cmd //c "taskkill /F /IM x64sc.exe" 2>/dev/null || true
    exit 1
fi

if ! "$PYTHON" scripts/vice_monitor.py "$TD_SPIN" "tests/ci_result.bin" "$MONITOR_PORT"; then
    echo "ERROR: vice_monitor.py failed" >&2
    kill "$VICE_PID" 2>/dev/null || true
    cmd //c "taskkill /F /IM x64sc.exe" 2>/dev/null || true
    exit 1
fi

# Give VICE a moment to process quit, then force-kill it
sleep 3
cmd //c "taskkill /F /IM x64sc.exe" 2>/dev/null || true
wait "$VICE_PID" 2>/dev/null || true

# ---- Check output file ----------------------------------------------------
if [ ! -f tests/ci_result.bin ]; then
    echo "ERROR: tests/ci_result.bin not found — VICE may not have exited cleanly" >&2
    exit 1
fi

# PRG file layout: byte 0-1 = load address ($07E8), byte 2 = pass_count value
PASS_HEX=$(od -An -tx1 -j2 -N1 tests/ci_result.bin | tr -d ' \n')

if [ -z "$PASS_HEX" ]; then
    echo "ERROR: could not read pass count from tests/ci_result.bin" >&2
    exit 1
fi

PASS_DEC=$((16#$PASS_HEX))

# ---- Gate -----------------------------------------------------------------
echo "=== CI: pass count = $PASS_DEC / $EXPECTED_PASS ==="

if [ "$PASS_DEC" -ne "$EXPECTED_PASS" ]; then
    echo "FAIL: expected $EXPECTED_PASS tests to pass, got $PASS_DEC" >&2
    echo "      Run 'make test_suite' and inspect the screen for which tests failed." >&2
    exit 1
fi

echo "PASS: all $EXPECTED_PASS tests passed."
