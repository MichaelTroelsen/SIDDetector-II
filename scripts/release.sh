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
#   3. CI tests    — build and run test_suite in VICE; gate on pass count
#   4. Bump version — increment patch in all files, add debug.md changelog row
#   5. Final build  — rebuild siddetector.prg with new version string
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

# Warn about untracked/modified files that aren't ours to change
DIRTY=$(git status --porcelain | grep -v '^\?\?' | grep -v '^[ M]' || true)
if [ -n "$DIRTY" ]; then
    echo "WARNING: working tree has staged/untracked changes:"
    echo "$DIRTY"
    read -rp "Continue anyway? [y/N] " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 1
fi

# ---- 2. Clean build --------------------------------------------------------
echo "=== RELEASE: clean build ==="
make clean
make all

# ---- 3. CI tests -----------------------------------------------------------
echo "=== RELEASE: run tests ==="
bash scripts/ci_test.sh   # exits non-zero if any test fails

# ---- 4. Bump version -------------------------------------------------------
echo "=== RELEASE: bump version ==="
bash scripts/bump_version.sh "$DESCRIPTION"

NEW_VER=$(cat .version)
echo "New version: $NEW_VER"

# ---- 5. Final build (with new version string) ------------------------------
echo "=== RELEASE: final build ==="
make all

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
    docs/CHIPS.md \
    docs/debug.md \
    docs/teststatus.md

# Stage test outputs if they changed
git add tests/test_suite.prg tests/test_suite.dbg \
        tests/test_suite.sym tests/test_suite.vs 2>/dev/null || true

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
