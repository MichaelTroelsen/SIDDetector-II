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
#   siddetector.asm    — screen title, file-header comment, debug-info title,
#                        README screen title, readme scroller (prepend new
#                        entry + age off oldest to keep rolling 5-entry
#                        window)
#   README.md          — heading + screenshot caption
#   docs/CHIPS.md      — intro paragraph
#   docs/debug.md      — new row at top of version history table
#   docs/teststatus.md — Version: header field
#
# The DESCRIPTION argument flows into the debug.md row AND the in-app
# scroller entry (uppercased for screencode_upper). Keep it ≤28 chars so
# the scroller line "  Vx.y.zz DESCRIPTION" stays within the C64's
# 40-column screen width.
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
# Screen title:      "SIDDETECTOR V1.2.4 FUNFUN/TRIANGLE 3532"
# Readme-page title: "SIDDETECTOR V1.2.4 README"
sed -i "s/SIDDETECTOR V${CURRENT}/SIDDETECTOR V${NEW_VER}/g" siddetector.asm
# Debug-info page title: "    SID DETECTOR - DEBUG INFO   V1.2.4 "
sed -i "s/DEBUG INFO   V${CURRENT}/DEBUG INFO   V${NEW_VER}/g" siddetector.asm
# File-header comment: // SID Detector v1.2.x
sed -i "s|// SID Detector v[0-9]*\.[0-9]*\.[0-9]*|// SID Detector v${NEW_VER}|" siddetector.asm

# Readme scroller: prepend new entry + age off oldest (rolling 5-entry window).
# Entry block format:
#     .byte $9E
#     .text "  V1.2.4 DESCRIPTION"
#     .byte 13
# The block is matched by the .text line carrying a version marker; the
# surrounding $9E and 13 bytes are handled via getline so we don't touch
# other $9E bytes elsewhere in the file.
DESC_UPPER=$(echo "${DESCRIPTION:-NO DESCRIPTION}" | tr '[:lower:]' '[:upper:]')
awk -v new="V${NEW_VER}" -v desc="${DESC_UPPER}" '
BEGIN { seen = 0 }
/^    \.byte \$9E$/ {
    saved = $0
    if ((getline text_line) <= 0) { print saved; exit }
    if (text_line ~ /^    \.text "  V[0-9]+\.[0-9]+\.[0-9]+ /) {
        if ((getline tail_line) <= 0) { print saved; print text_line; exit }
        seen++
        if (seen == 1) {
            print "    .byte $9E"
            printf "    .text \"  %s %s\"\n", new, desc
            print "    .byte 13"
        }
        if (seen < 5) {
            print saved
            print text_line
            print tail_line
        }
        next
    }
    print saved
    print text_line
    next
}
{ print }
' siddetector.asm > siddetector.asm.tmp && mv siddetector.asm.tmp siddetector.asm

# ---- README.md -------------------------------------------------------------
sed -i "s/# SID Detector v${CURRENT}/# SID Detector v${NEW_VER}/g" README.md
sed -i "s/SID Detector v${CURRENT} running in VICE/SID Detector v${NEW_VER} running in VICE/g" README.md
sed -i "s/siddetector v${CURRENT}/siddetector v${NEW_VER}/g" README.md
sed -i "s/(v${CURRENT})/(v${NEW_VER})/g" README.md

# ---- docs/CHIPS.md ---------------------------------------------------------
sed -i "s/SID Detector v${CURRENT}/SID Detector v${NEW_VER}/g" docs/CHIPS.md

# ---- docs/teststatus.md: version field -------------------------------------
sed -i "s/^\\*\\*Version:\\*\\* V${CURRENT}/\\*\\*Version:\\*\\* V${NEW_VER}/" docs/teststatus.md

# ---- docs/debug.md: insert new row after the table separator --------------
if [ -n "$DESCRIPTION" ]; then
    sed -i "/^|---------|/a | V${NEW_VER}  | ${DESCRIPTION} |" docs/debug.md
else
    sed -i "/^|---------|/a | V${NEW_VER}  | (no description provided) |" docs/debug.md
fi

# ---- Write version file for release.sh ------------------------------------
echo "V${NEW_VER}" > .version

echo "Done: v${CURRENT} → v${NEW_VER}"
