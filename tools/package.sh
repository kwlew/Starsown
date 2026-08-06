#!/usr/bin/env bash
# tools/package.sh -- builds the distributable TDIdle.love.
#
#   ./tools/package.sh [output.love]
#
# A .love is a zip with main.lua at its root. This project keeps the engine-side
# code in lib/ *outside* src/, which works when running `love src` from the repo
# root only because Lua's own package.path finds lib/ on the real filesystem.
# Inside a .love there is no real filesystem, so lib/ has to be packed alongside
# the contents of src/ at the archive root -- that is the whole job here, and
# getting it wrong produces an archive that runs fine from the repo and dies
# with "module 'lib.settings' not found" the moment it is shipped.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/build/TDIdle.love}"
STAGE="$ROOT/build/stage"

command -v zip >/dev/null 2>&1 || { echo "package: 'zip' is required" >&2; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE" "$(dirname "$OUT")"

cp -R "$ROOT/src/." "$STAGE/"
cp -R "$ROOT/lib" "$STAGE/lib"

# The two files LÖVE looks for at the archive root. Fail here rather than
# shipping an archive that only fails on a player's machine.
for required in main.lua conf.lua; do
    [ -f "$STAGE/$required" ] || { echo "package: $required missing from the archive root" >&2; exit 1; }
done

rm -f "$OUT"
# -X drops the platform-specific extra fields, so the same tree always produces
# the same archive.
( cd "$STAGE" && zip -qr9 -X "$OUT" . )
rm -rf "$STAGE"

echo "package: wrote $OUT ($(du -h "$OUT" | cut -f1))"
