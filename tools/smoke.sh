#!/usr/bin/env bash
# tools/smoke.sh -- boots the packaged game in a real LÖVE and fails if it
# doesn't survive a few seconds. See tests/smoke/main.lua for what it checks.
#
#   ./tools/smoke.sh                       # builds the .love first if needed
#   LOVE=/path/to/love ./tools/smoke.sh    # a specific binary (CI uses this)
#   SMOKE_SECONDS=10 ./tools/smoke.sh
#
# On a headless box, run it under xvfb-run and point OpenAL at its null device:
#   ALSOFT_DRIVERS=null xvfb-run -a ./tools/smoke.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOVE="${LOVE:-love}"
ARCHIVE="$ROOT/build/TDIdle.love"
RUNDIR="$ROOT/build/smoke"
# Hard ceiling: if the game hangs (a blocking request, a stuck loading screen),
# the harness never reaches its own exit, so something outside it has to.
TIMEOUT="${SMOKE_TIMEOUT:-90}"

command -v "$LOVE" >/dev/null 2>&1 || { echo "smoke: no LÖVE binary at '$LOVE'" >&2; exit 1; }

[ -f "$ARCHIVE" ] || "$ROOT/tools/package.sh" "$ARCHIVE"

rm -rf "$RUNDIR"
mkdir -p "$RUNDIR"
cp "$ROOT/tests/smoke/main.lua" "$ROOT/tests/smoke/conf.lua" "$RUNDIR/"
cp "$ARCHIVE" "$RUNDIR/game.love"

status=0
if command -v timeout >/dev/null 2>&1; then
    timeout --foreground "$TIMEOUT" "$LOVE" "$RUNDIR" || status=$?
else
    "$LOVE" "$RUNDIR" || status=$?
fi

if [ "$status" -eq 124 ]; then
    echo "smoke: the game never exited within ${TIMEOUT}s -- it is hung" >&2
    exit 1
fi
exit "$status"
