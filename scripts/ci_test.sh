#!/usr/bin/env bash
# =============================================================================
# ci_test.sh — Build test suite and run it headlessly in VICE.
#
# Usage:
#   bash scripts/ci_test.sh
#   (or: make ci)
#
# Exit codes:
#   0 — every test in the suite passed
#   1 — build failed, VICE did not exit cleanly, or a test failed
#
# How it works:
#   VICE is launched with -remotemonitor on a dynamically chosen free port so
#   scripts/vice_monitor.py can connect, set a breakpoint at td_spin, wait for
#   it to fire, then save $07E8-$07E9 (pass_count and the suite's own
#   TEST_TOTAL, both in off-screen RAM) to tests/ci_result.bin.  A dynamic port
#   avoids TCP TIME_WAIT collisions between back-to-back runs.
#   This script reads bytes 2 and 3 of that PRG file (past the 2-byte
#   load-address header) and requires them to be equal, so the expected count
#   lives in exactly one place: TEST_TOTAL in tests/test_suite.asm.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

# Tool locations come from the single source of truth shared with the Makefile
# and scripts/toolpaths.py.  Keeping a private copy here is what produced commit
# 63659cd ("fix: correct stale Python path in ci_test.sh").
# shellcheck disable=SC1091
. "$ROOT/toolpaths.env"
KICKASS="java -jar $KICKASS_JAR"
VICE="$VICE_X64SC"
PYTHON="python"

for _tool in "$KICKASS_JAR" "$VICE"; do
    if [ ! -f "$_tool" ]; then
        echo "ERROR: required tool not found:" >&2
        echo "         $_tool" >&2
        echo "       Fix the path in $ROOT/toolpaths.env" >&2
        exit 1
    fi
done
# No EXPECTED_PASS constant here any more: the suite reports its own total at
# $07E9 alongside the pass count at $07E8, and we compare the two. Adding a
# test used to require editing this number, the `cmp` in test_suite.asm and the
# summary string; missing one produced a confusing mismatch.

# ---- Build ----------------------------------------------------------------
echo "=== CI: build test_suite.prg ==="
$KICKASS tests/test_suite.asm -o tests/test_suite.prg

# ---- Helper: stop only the VICE this script started ------------------------
# This script used to run `taskkill /F /IM x64sc.exe`, which kills EVERY x64sc
# on the machine — including an interactive `make run-*` session the user has
# open in another window.  A free monitor port is chosen below, so a stale VICE
# cannot interfere with this run and there is no reason to reap other people's
# processes.  $! is the Git Bash pid; /proc/<pid>/winpid maps it to the Windows
# pid that taskkill understands.
kill_our_vice() {
    [ -n "${VICE_PID:-}" ] || return 0
    local winpid
    winpid=$(cat "/proc/${VICE_PID}/winpid" 2>/dev/null || true)
    if [ -n "$winpid" ]; then
        cmd //c "taskkill /F /PID $winpid" >/dev/null 2>&1 || true
    else
        kill "$VICE_PID" 2>/dev/null || true
    fi
}

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
    kill_our_vice
    exit 1
fi

if ! "$PYTHON" scripts/vice_monitor.py "$TD_SPIN" "tests/ci_result.bin" "$MONITOR_PORT"; then
    echo "ERROR: vice_monitor.py failed" >&2
    kill_our_vice
    exit 1
fi

# Give VICE a moment to process quit, then force-kill it
sleep 3
kill_our_vice
wait "$VICE_PID" 2>/dev/null || true

# ---- Check output file ----------------------------------------------------
if [ ! -f tests/ci_result.bin ]; then
    echo "ERROR: tests/ci_result.bin not found — VICE may not have exited cleanly" >&2
    exit 1
fi

# PRG file layout: bytes 0-1 = load address ($07E8),
#                  byte 2   = pass_count  ($07E8)
#                  byte 3   = TEST_TOTAL  ($07E9)
PASS_HEX=$(od -An -tx1 -j2 -N1 tests/ci_result.bin | tr -d ' \n')
TOTAL_HEX=$(od -An -tx1 -j3 -N1 tests/ci_result.bin | tr -d ' \n')

if [ -z "$PASS_HEX" ] || [ -z "$TOTAL_HEX" ]; then
    echo "ERROR: could not read pass/total bytes from tests/ci_result.bin" >&2
    exit 1
fi

PASS_DEC=$((16#$PASS_HEX))
TOTAL_DEC=$((16#$TOTAL_HEX))

# ---- Gate -----------------------------------------------------------------
echo "=== CI: pass count = $PASS_DEC / $TOTAL_DEC ==="

if [ "$TOTAL_DEC" -eq 0 ]; then
    echo "FAIL: suite reported a total of 0 tests — it did not reach the end." >&2
    exit 1
fi

if [ "$PASS_DEC" -ne "$TOTAL_DEC" ]; then
    echo "FAIL: $((TOTAL_DEC - PASS_DEC)) of $TOTAL_DEC tests failed (passed $PASS_DEC)." >&2
    echo "      Run 'make test_suite' and inspect the screen for which tests failed." >&2
    exit 1
fi

echo "PASS: all $TOTAL_DEC tests passed."
