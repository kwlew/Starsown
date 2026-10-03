#!/usr/bin/env bash

# Package Starsown as a portable .love archive on Linux. The resulting file
# requires LÖVE 11.5; use --verify to launch it from an otherwise empty
# directory and catch missing files or startup errors.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: tools/build-linux.sh [options]

Options:
  --verify              Run the packaged game and fail on startup errors.
  --verify-seconds N    Seconds the game must remain running (default: 12).
  --bytecode            Replace Lua sources with LuaJIT bytecode.
  --strip-debug         Strip debug information from bytecode.
  --compile-seconds N   Bytecode compilation timeout (default: 30).
  --output PATH         Output archive (default: dist/Starsown.love).
  --game-version TEXT   Version stamped into the archive's version.txt
                        (default: git describe --tags --always --dirty).
  --https-lib PATH      Bundle this Linux x64 lua-https (https.so) so world
                        stats work; the game extracts it at runtime, since
                        LÖVE can't load a C module from inside a .love.
                        With --verify, also checks the packaged copy loads.
  -h, --help            Show this help.

The Linux artifact is a .love file, not a fused native executable. Players can
run it with `love Starsown.love`; Fedora 44 provides the matching LÖVE 11.5.
EOF
}

verify=false
bytecode=false
strip_debug=false
verify_seconds=12
compile_seconds=30
output_path=''
https_lib=''
game_version=''

while (($# > 0)); do
    case "$1" in
        --verify)
            verify=true
            shift
            ;;
        --bytecode)
            bytecode=true
            shift
            ;;
        --strip-debug)
            strip_debug=true
            shift
            ;;
        --verify-seconds|--compile-seconds|--output|--https-lib|--game-version)
            if (($# < 2)); then
                printf 'Missing value for %s\n' "$1" >&2
                usage >&2
                exit 2
            fi
            case "$1" in
                --verify-seconds) verify_seconds=$2 ;;
                --compile-seconds) compile_seconds=$2 ;;
                --output) output_path=$2 ;;
                --https-lib) https_lib=$2 ;;
                --game-version) game_version=$2 ;;
            esac
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

for value_name in verify_seconds compile_seconds; do
    value=${!value_name}
    if [[ ! $value =~ ^[1-9][0-9]*$ ]]; then
        printf '%s must be a positive integer, got: %s\n' "$value_name" "$value" >&2
        exit 2
    fi
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$script_dir/.." && pwd)
src="$root/src"
dist="$root/dist"

if [[ ! -f "$src/main.lua" ]]; then
    printf 'No main.lua in %s - is this the right repository?\n' "$src" >&2
    exit 1
fi

for command_name in zip unzip; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$command_name" >&2
        exit 1
    fi
done

if [[ $verify == true || $bytecode == true ]]; then
    if ! command -v love >/dev/null 2>&1; then
        printf 'LÖVE was not found in PATH. Install LÖVE 11.5 first.\n' >&2
        exit 1
    fi
fi

if [[ -n $https_lib ]]; then
    if [[ ! -f $https_lib ]]; then
        printf 'No lua-https library at %s\n' "$https_lib" >&2
        exit 1
    fi
    if [[ $(head -c 4 -- "$https_lib" | od -An -tx1 | tr -d ' \n') != 7f454c46 ]]; then
        printf '%s is not an ELF shared library.\n' "$https_lib" >&2
        exit 1
    fi
fi

# safe.directory: CI checks out inside a container as a different user than
# the one running this, and git refuses to read such a repo without it.
if [[ -z $game_version ]]; then
    game_version=$(git -C "$root" -c safe.directory="$root" describe --tags --always --dirty 2>/dev/null || true)
fi
if [[ -z $game_version ]]; then
    game_version=dev
fi
if [[ ! $game_version =~ ^[[:graph:]]+$ ]]; then
    printf 'Game version must be one word, got: %s\n' "$game_version" >&2
    exit 2
fi

if [[ -z $output_path ]]; then
    output_path="$dist/Starsown.love"
elif [[ $output_path != /* ]]; then
    output_path="$root/$output_path"
fi

output_dir=$(dirname -- "$output_path")
mkdir -p -- "$output_dir" "$dist"
output_dir=$(cd -- "$output_dir" && pwd)
output_path="$output_dir/$(basename -- "$output_path")"

work_dir=$(mktemp -d "$dist/.linux-build.XXXXXX")
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

package_src=$src
if [[ $bytecode == true ]]; then
    package_src="$work_dir/package"
    compiler_dir="$work_dir/compiler"
    mkdir -p -- "$package_src" "$compiler_dir/game"

    # Keep assets and directory structure intact, then overwrite Lua sources
    # with bytecode produced by the same LÖVE runtime used to run the game.
    cp -a -- "$src/." "$package_src/"
    cp -a -- "$script_dir/bytecode/." "$compiler_dir/"

    while IFS= read -r -d '' lua_file; do
        relative_path=${lua_file#"$src/"}
        destination="$compiler_dir/game/$relative_path"
        mkdir -p -- "$(dirname -- "$destination")"
        cp -- "$lua_file" "$destination"
    done < <(find "$src" -type f -name '*.lua' -print0)

    strip_value=0
    if [[ $strip_debug == true ]]; then
        strip_value=1
    fi

    printf 'Compiling Lua sources to bytecode...\n'
    set +e
    TDIDLE_COMPILE_OUT="$package_src" \
        TDIDLE_COMPILE_STRIP="$strip_value" \
        timeout --kill-after=2s "${compile_seconds}s" love "$compiler_dir"
    compile_status=$?
    set -e
    if [[ $compile_status -ne 0 ]]; then
        printf 'Bytecode compilation failed or timed out (status %s).\n' "$compile_status" >&2
        exit 1
    fi
fi

rm -f -- "$output_path"
(
    cd -- "$package_src"
    zip -q -9 -r "$output_path" .
)

# Read by src/core/app.lua.
version_stage="$work_dir/version"
mkdir -p -- "$version_stage"
printf '%s\n' "$game_version" >"$version_stage/version.txt"
(
    cd -- "$version_stage"
    zip -q -9 "$output_path" version.txt
)

# Must match BUNDLED in src/services/stats/https.lua.
if [[ -n $https_lib ]]; then
    native_stage="$work_dir/native"
    mkdir -p -- "$native_stage/native/linux-x64"
    cp -- "$https_lib" "$native_stage/native/linux-x64/https.so"
    (
        cd -- "$native_stage"
        zip -q -9 "$output_path" native/linux-x64/https.so
    )
fi

archive_list="$work_dir/archive-entries.txt"
unzip -Z1 "$output_path" >"$archive_list"

for required in main.lua conf.lua version.txt; do
    if ! grep -Fqx -- "$required" "$archive_list"; then
        printf '%s is not at the root of %s.\n' "$required" "$output_path" >&2
        exit 1
    fi
done

# Match the source-level require graph against the archive. LÖVE-provided
# modules are excluded because they are intentionally not packaged.
missing_modules=()
while IFS= read -r module; do
    case "$module" in
        https|ffi|bit|socket|love) continue ;;
    esac

    module_path=${module//.//}
    if ! grep -Fqx -- "$module_path.lua" "$archive_list" && \
       ! grep -Fqx -- "$module_path/init.lua" "$archive_list"; then
        missing_modules+=("$module")
    fi
done < <(
    grep -rhoE --include='*.lua' 'require[[:space:]]*\(?[[:space:]]*"[^"]+"' "$src" \
        | sed -E 's/.*"([^"]+)"/\1/' \
        | sort -u
)

if ((${#missing_modules[@]} > 0)); then
    printf 'Modules required by the source but missing from the archive:\n' >&2
    printf '  %s\n' "${missing_modules[@]}" >&2
    exit 1
fi

archive_kib=$((($(stat -c '%s' "$output_path") + 1023) / 1024))
entry_count=$(wc -l <"$archive_list")
bytecode_note=''
if [[ $bytecode == true ]]; then
    bytecode_note=', bytecode'
fi
if [[ -n $https_lib ]]; then
    bytecode_note="$bytecode_note, lua-https bundled"
fi
printf 'Built %s %s (%s KiB, %s entries%s)\n' \
    "$output_path" "$game_version" "$archive_kib" "$entry_count" "$bytecode_note"

if [[ $verify != true ]]; then
    exit 0
fi

verify_dir="$work_dir/verify"
mkdir -p -- "$verify_dir"
artifact_name=$(basename -- "$output_path")
cp -- "$output_path" "$verify_dir/$artifact_name"
verify_log="$work_dir/verify.log"

set +e
(
    cd -- "$verify_dir"
    timeout --kill-after=2s "${verify_seconds}s" love "$artifact_name"
) >"$verify_log" 2>&1
verify_status=$?
set -e

cat "$verify_log"
if [[ $verify_status -ne 124 ]]; then
    printf 'The packaged game exited before %s seconds (status %s).\n' \
        "$verify_seconds" "$verify_status" >&2
    exit 1
fi
if grep -Eq 'Error:|stack traceback' "$verify_log"; then
    printf 'The packaged game reported an error.\n' >&2
    exit 1
fi

printf 'Verified: ran %s seconds from a clean directory with no errors.\n' \
    "$verify_seconds"

if [[ -n $https_lib ]]; then
    https_log="$work_dir/check-https.log"
    set +e
    (
        cd -- "$verify_dir"
        timeout --kill-after=2s 30s love "$artifact_name" --check-https
    ) >"$https_log" 2>&1
    https_status=$?
    set -e
    cat "$https_log"
    if [[ $https_status -ne 0 ]] || ! grep -Fq '[check-https] ok' "$https_log"; then
        printf 'The packaged lua-https did not load (status %s).\n' "$https_status" >&2
        exit 1
    fi
    printf 'Verified: the bundled lua-https loads from the packaged game.\n'
fi
