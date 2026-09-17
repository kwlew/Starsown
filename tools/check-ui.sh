#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/.." && pwd)
review_dir=$(mktemp -d /tmp/starsown-ui-check.XXXXXX)
mkdir -p "$review_dir/game" "$review_dir/data"
cp -R "$project_dir/src/." "$review_dir/game/"
cp "$project_dir/tools/ui-check/main.lua" "$review_dir/game/main.lua"
printf 'UI check artifacts: %s\n' "$review_dir"
SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-offscreen}" XDG_DATA_HOME="$review_dir/data" \
    ALSOFT_DRIVERS=null timeout 60s love "$review_dir/game"
