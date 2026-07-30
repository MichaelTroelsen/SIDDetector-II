#!/usr/bin/env python3
"""Start and stop VICE without collateral damage.

The ad-hoc probe scripts in this directory all used to clean up with

    subprocess.run(["taskkill", "/F", "/IM", "x64sc.exe"])

which kills **every** x64sc on the machine - including an interactive
`make run-armsid` session the user has open in another window. None of them kept
the handle `subprocess.Popen` returned, so they had nothing more precise to aim
at. `scripts/ci_test.sh` and `scripts/variant_smoke.py` were fixed first
(CODE-REVIEW.md P2-1); this module is what the rest use.

Two entry points, deliberately named so the dangerous one is obvious at the call
site:

    terminate(proc)   stop only the process this script started - the normal case
    sweep_stale()     the old global kill, kept because these scripts bind a
                      fixed monitor port and a leftover VICE would block it, but
                      it now announces itself instead of doing it silently
"""
import subprocess
import sys

__all__ = ["terminate", "sweep_stale"]


def terminate(proc):
    """Stop the VICE this script launched. Safe to call twice, or with None."""
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass


def sweep_stale(reason="a leftover VICE would hold the fixed monitor port"):
    """Kill EVERY x64sc on the machine, after saying so.

    Only for the pre-launch slot, where by definition we have no handle of our
    own yet. If you are writing something new, give it an ephemeral port (see
    variant_smoke._free_port) and you will not need this at all.
    """
    print(f"[viceproc] killing ALL x64sc.exe processes: {reason}.", file=sys.stderr)
    print("[viceproc] close any interactive VICE you want to keep first.",
          file=sys.stderr)
    subprocess.run(["taskkill", "/F", "/IM", "x64sc.exe"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
