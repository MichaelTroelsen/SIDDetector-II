#!/usr/bin/env bash
# =============================================================================
# release.sh — Full CI/CD release pipeline.
#
# Usage:
#   bash scripts/release.sh "Short description of changes"
#
# Pipeline stages:
#   1. Pre-flight  — branch check, working tree check
#   2. Clean build — make clean + make all
#   3. CI tests    — test_suite in VICE + host tests, then the MEMORYMAP
#                    doc-drift gate.  Everything that can REJECT a release runs
#                    here, before anything is mutated: an abort after stage 4
#                    leaves a bumped-but-uncommitted tree, and re-running would
#                    bump twice (that is how V1.5.07 was created and discarded).
#   4. Bump version — increment patch in all files, add debug.md changelog row
#   5. Final build  — rebuild siddetector.prg with new version string, then
#                    regenerate docs/MEMORYMAP.md: the bump shifts every symbol
#                    after it, so the map is stale by definition at this point
#   6. Git release  — commit all changed files, tag, push
#   7. GitHub release — create release on GitHub with siddetector.prg asset
#                       (skipped if `gh` is not installed / not authenticated)
#
# Requirements:
#   - Git Bash (or WSL) on Windows
#   - Java (for KickAssembler)
#   - WinVICE x64sc at C:/winvice/bin/x64sc.exe
#   - GNU sed (bundled with Git for Windows)
#   - gh CLI, authenticated (optional — stage 7 is skipped if missing)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

DESCRIPTION="${1:-}"
if [ -z "$DESCRIPTION" ]; then
    echo "Usage: bash scripts/release.sh \"Description of changes\"" >&2
    exit 1
fi

# ---- 1. Pre-flight ---------------------------------------------------------
echo "=== RELEASE: pre-flight checks ==="

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "master" ]; then
    echo "ERROR: not on master branch (current: $BRANCH)" >&2
    exit 1
fi

# Warn about changes that this release will NOT carry.
#
# Stage 6 stages an explicit file list. Anything dirty outside that list is
# silently left behind, which is the failure worth catching here.
#
# The previous check was:
#     git status --porcelain | grep -v '^??' | grep -v '^[ M]'
# `^[ M]` drops every line whose first status column is a space or 'M' — that
# is both unstaged AND staged modifications — and `^??` drops untracked. The
# result was empty for essentially every real working tree, so this guard has
# never actually fired.
#
# An entry ending in '/' matches everything beneath that directory; anything
# else must match the path exactly.  The goldens need the prefix form because
# there is one file per variant case and the set grows whenever a case is added.
# `docs/` uses it too: the tree holds the whole reference set (CHIPS, debug,
# teststatus, MEMORYMAP, STORY, the proxy docs, images, …) and listing them
# one by one meant every new document silently blocked the next release.
RELEASE_PATHS=(
    siddetector.asm siddetector.prg siddetector.dbg siddetector.sym siddetector.vs
    Makefile README.md TODO.md
    CLAUDE.md CODE-REVIEW.md DOC-AUDIT.md whats-next.md
    docs/
    tests/test_suite.prg tests/test_suite.dbg tests/test_suite.sym tests/test_suite.vs
    tests/variant_goldens/
    .version
)

is_release_path() {
    local candidate="$1" rp
    for rp in "${RELEASE_PATHS[@]}"; do
        case "$rp" in
            */) [ "${candidate#"$rp"}" != "$candidate" ] && return 0 ;;
            *)  [ "$candidate" = "$rp" ] && return 0 ;;
        esac
    done
    return 1
}

DIRTY=""
while IFS= read -r line; do
    [ -z "$line" ] && continue
    path="${line:3}"          # porcelain v1: two status columns + a space
    path="${path##* -> }"     # renames render as "R  old -> new"
    path="${path%\"}"; path="${path#\"}"
    if ! is_release_path "$path"; then
        DIRTY="${DIRTY}${line}"$'\n'
    fi
done < <(git status --porcelain)

if [ -n "$DIRTY" ]; then
    echo "WARNING: the following changes are NOT in the release commit list and"
    echo "         will be left out of ${0##*/}'s commit:"
    printf '%s' "$DIRTY"
    if [ -t 0 ]; then
        read -rp "Continue anyway? [y/N] " CONFIRM
        [[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 1
    else
        echo "ERROR: non-interactive shell — refusing to release with unrelated" >&2
        echo "       changes present. Commit, stash, or clean them first." >&2
        exit 1
    fi
fi

# ---- 2. Clean build --------------------------------------------------------
echo "=== RELEASE: clean build ==="
make clean
make all

# ---- 3. CI tests -----------------------------------------------------------
echo "=== RELEASE: run tests ==="
bash scripts/ci_test.sh   # exits non-zero if any test fails
make python_tests         # host-side tests; no emulator needed

# Doc-drift gate runs HERE, before anything is mutated, so a failure aborts a
# release that has not yet bumped or committed anything. Do not move it after
# stage 4: aborting post-bump leaves a bumped-but-uncommitted tree, and
# re-running this script would then bump a second time (that is how V1.5.07
# was created and had to be discarded).
echo "=== RELEASE: doc-drift gate ==="
python scripts/check_memorymap.py --strict

# ---- 4. Bump version -------------------------------------------------------
echo "=== RELEASE: bump version ==="
bash scripts/bump_version.sh "$DESCRIPTION"

NEW_VER=$(cat .version)
echo "New version: $NEW_VER"

# ---- 5. Final build (with new version string) ------------------------------
echo "=== RELEASE: final build ==="
make all

# The bump changes code size, so symbols shift and the segment extents in the
# MEMORYMAP header move with them. Regenerate here, after the final build and
# before staging, or the release ships a stale map: V1.5.09 went out with three
# rows drifted +3 bytes and a header two versions out of date, because nothing
# between the bump and the commit ever looked. --fix is mechanical (it only
# rewrites addresses the .sym/.dbg disagree with) and docs/ is already in
# RELEASE_PATHS, so the result is staged with everything else.
echo "=== RELEASE: refresh MEMORYMAP for the new build ==="
python scripts/check_memorymap.py --fix

# ---- 6. Git release --------------------------------------------------------
echo "=== RELEASE: git commit, tag, push ==="

git add \
    siddetector.asm \
    siddetector.prg \
    siddetector.dbg \
    siddetector.sym \
    siddetector.vs \
    Makefile \
    README.md \
    TODO.md \
    CLAUDE.md \
    CODE-REVIEW.md \
    DOC-AUDIT.md \
    docs \
    tests/variant_goldens

# The goldens certify the detection output this release ships.  Leaving them
# behind means a fresh clone fails `make ci-full` until someone regenerates
# them — so they belong in the release commit, not in a follow-up.

# Stage test outputs if they changed
git add tests/test_suite.prg tests/test_suite.dbg \
        tests/test_suite.sym tests/test_suite.vs 2>/dev/null || true

# whats-next.md is a per-session handoff, not a permanent project file — it may
# legitimately not exist at release time, so staging it must not abort the run.
git add whats-next.md 2>/dev/null || true

git commit -m "$(cat <<EOF
release: ${NEW_VER}

${DESCRIPTION}

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"

# Tag convention is lowercase-v (v1.4.27). `.version` contains an
# uppercase-V version string (e.g. V1.4.27) — strip and lowercase here.
TAG="v${NEW_VER#V}"
git tag -a "$TAG" -m "${NEW_VER}: ${DESCRIPTION}"

echo "=== RELEASE: pushing to origin ==="
git push origin master
git push origin "$TAG"

# ---- 7. GitHub release -----------------------------------------------------
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "=== RELEASE: creating GitHub release ==="
    gh release create "$TAG" \
        --title "SID Detector II ${TAG}" \
        --notes "${DESCRIPTION}" \
        siddetector.prg
else
    echo "=== RELEASE: skipping GitHub release (gh not installed or not authenticated) ==="
    echo "    Create manually with: gh release create ${TAG} --title \"SID Detector II ${TAG}\" --notes \"...\" siddetector.prg"
fi

rm -f .version

echo ""
echo "==================================================================="
echo "Released ${NEW_VER}: ${DESCRIPTION}"
echo "==================================================================="
