#!/usr/bin/env bash
# =============================================================================
# bump_version.sh — Increment the patch version across all project files.
#
# Usage:
#   bash scripts/bump_version.sh "Short description for changelog"
#
# What it does:
#   1. Reads current version from the SIDDETECTOR screen text in siddetector.asm
#      (the canonical source, e.g. "SIDDETECTOR V1.2.4")
#   2. Increments the patch number (1.2.4 → 1.2.5)
#   3. Updates all version references across the codebase
#   4. Appends a new row to the debug.md version history table
#   5. Writes the new version string to .version for use by release.sh
#
# Files updated:
#   siddetector.asm  — screen text (V1.2.X uppercase) + top comment (v1.2.X lowercase)
#   README.md        — heading, screen layout section
#   CHIPS.md         — intro paragraph
#   debug.md         — new row in version history table
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

DESCRIPTION="${1:-}"

# ---- Extract current version (canonical: screen text in siddetector.asm) --
CURRENT=$(grep -o 'SIDDETECTOR V[0-9]*\.[0-9]*\.[0-9]*' siddetector.asm \
    | grep -o '[0-9]*\.[0-9]*\.[0-9]*' | head -1)

if [ -z "$CURRENT" ]; then
    echo "ERROR: could not find version in siddetector.asm screen text" >&2
    exit 1
fi

MAJOR=$(echo "$CURRENT" | cut -d. -f1)
MINOR=$(echo "$CURRENT" | cut -d. -f2)
PATCH=$(echo "$CURRENT" | cut -d. -f3)
NEW_PATCH=$(printf "%02d" $((10#${PATCH} + 1)))
NEW_VER="${MAJOR}.${MINOR}.${NEW_PATCH}"

echo "Bumping v${CURRENT} → v${NEW_VER}"

# ---- siddetector.asm -------------------------------------------------------
# Screen text: "           SIDDETECTOR V1.2.4           "
sed -i "s/SIDDETECTOR V${CURRENT}/SIDDETECTOR V${NEW_VER}/g" siddetector.asm
# Top comment: // SID Detector v1.2.x
sed -i "s|// SID Detector v[0-9]*\.[0-9]*\.[0-9]*|// SID Detector v${NEW_VER}|" siddetector.asm

# ---- README.md -------------------------------------------------------------
sed -i "s/# SID Detector v${CURRENT}/# SID Detector v${NEW_VER}/g" README.md
sed -i "s/siddetector v${CURRENT}/siddetector v${NEW_VER}/g" README.md
sed -i "s/(v${CURRENT})/(v${NEW_VER})/g" README.md

# ---- CHIPS.md --------------------------------------------------------------
sed -i "s/SID Detector v${CURRENT}/SID Detector v${NEW_VER}/g" CHIPS.md

# ---- debug.md: insert new row after the table separator -------------------
if [ -n "$DESCRIPTION" ]; then
    sed -i "/^|---------|/a | V${NEW_VER}  | ${DESCRIPTION} |" debug.md
else
    sed -i "/^|---------|/a | V${NEW_VER}  | (no description provided) |" debug.md
fi

# ---- Write version file for release.sh ------------------------------------
echo "V${NEW_VER}" > .version

echo "Done: v${CURRENT} → v${NEW_VER}"
