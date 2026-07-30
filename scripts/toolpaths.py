#!/usr/bin/env python3
"""Tool locations for the Python harnesses, read from ../toolpaths.env.

One file holds the paths; the Makefile `include`s it, ci_test.sh `.`-sources it,
and this module parses it. See toolpaths.env for why the format is constrained.

Import-time behaviour is deliberately side-effect free: `VICE` and `KICKASS_JAR`
are plain strings and nothing is validated. That matters because host-only tests
(tests/test_variant_render.py) import variant_smoke, which imports this module —
they must keep working on a machine with no emulator installed. Validate at the
point of use instead:

    from toolpaths import vice
    subprocess.Popen([vice(), "-autostart", prg])   # exits with a clear message
                                                    # if the binary is missing

An environment variable of the same name overrides the file, for a one-off run
against a different build.
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = ROOT / "toolpaths.env"


def _load(path=ENV_FILE):
    """Parse the shared KEY=value file. Missing file -> empty, not an error."""
    values = {}
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return values
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        values[key.strip()] = val.strip()
    return values


_VALUES = _load()

VICE = os.environ.get("VICE_X64SC") or _VALUES.get("VICE_X64SC", "")
KICKASS_JAR = os.environ.get("KICKASS_JAR") or _VALUES.get("KICKASS_JAR", "")


def _require(path, what):
    if not path:
        sys.exit(f"ERROR: {what} is not configured.\n"
                 f"       Set it in {ENV_FILE}")
    if not Path(path).is_file():
        # Plain ASCII: this text goes to a Windows console whose codepage
        # mangles em-dashes into replacement characters.
        sys.exit(f"ERROR: {what} not found at:\n"
                 f"         {path}\n"
                 f"       Fix the path in {ENV_FILE} - it is the single\n"
                 f"       source of truth shared by the Makefile and every script.")
    return path


def vice():
    """Absolute path to the patched x64sc, validated."""
    return _require(VICE, "VICE x64sc (patched, with -sidvariant)")


def kickass_jar():
    """Absolute path to KickAss.jar, validated."""
    return _require(KICKASS_JAR, "KickAssembler jar")


def kickass_cmd():
    """Command prefix for assembling, e.g. ['java', '-jar', '<jar>']."""
    return ["java", "-jar", kickass_jar()]


if __name__ == "__main__":          # `python scripts/toolpaths.py` to inspect
    print(f"toolpaths.env : {ENV_FILE}")
    print(f"VICE_X64SC    : {VICE}"
          f"{'' if Path(VICE).is_file() else '   <-- MISSING'}")
    print(f"KICKASS_JAR   : {KICKASS_JAR}"
          f"{'' if Path(KICKASS_JAR).is_file() else '   <-- MISSING'}")
