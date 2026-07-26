#!/bin/bash
set -euo pipefail

CONFIG=/config
WORKSPACE=/workspace
OUTPUT=/output

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
# Parse build.yaml into JSON entries using Python + PyYAML
# ---------------------------------------------------------------------------
parse_build_yaml() {
    python3 -c "
import yaml, sys, json

with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

for entry in data.get('include', []):
    print(json.dumps(entry))
" "$CONFIG/build.yaml"
}

# ---------------------------------------------------------------------------
# Initialise the west workspace (first run or missing .west/config)
# ---------------------------------------------------------------------------
init_workspace() {
    echo ">>> Initialising west workspace..."
    mkdir -p "$WORKSPACE"
    cp -R "$CONFIG/config" "$WORKSPACE/config"

    cd "$WORKSPACE"
    west init -l config
    west update --fetch-opt=--filter=tree:0
    west zephyr-export
    echo ">>> Workspace initialised."
}

# ---------------------------------------------------------------------------
# Update config files in the workspace (keymap / conf may have changed)
# ---------------------------------------------------------------------------
update_config() {
    echo ">>> Updating config files in workspace..."
    cp -R "$CONFIG/config/"* "$WORKSPACE/config/"
}

# ---------------------------------------------------------------------------
# Build a single target
# ---------------------------------------------------------------------------
build_target() {
    local board="$1"
    local artifact="$2"
    local shield="${3:-}"
    local cmake_args="${4:-}"

    local build_dir="$WORKSPACE/build/${artifact}"
    local extra_args=""

    if [ -n "$shield" ]; then
        extra_args="$extra_args -DSHIELD=$shield"
    fi

    echo ""
    echo "=== Building $artifact (board: $board) ==="
    west build \
        -s zmk/app \
        -d "$build_dir" \
        -b "$board" \
        -- -DZMK_CONFIG="$WORKSPACE/config" \
           $extra_args \
           $cmake_args

    local uf2="$build_dir/zephyr/zmk.uf2"
    if [ -f "$uf2" ]; then
        cp "$uf2" "$OUTPUT/${artifact}.uf2"
        echo ">>> $OUTPUT/${artifact}.uf2"
    else
        echo "ERROR: expected $uf2 not found" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    mkdir -p "$OUTPUT"

    if [ ! -f "$WORKSPACE/.west/config" ]; then
        init_workspace
    else
        update_config
    fi

    cd "$WORKSPACE"

    while IFS= read -r line; do
        board=$(echo "$line"   | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['board'])")
        artifact=$(echo "$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('artifact-name', d['board']))")
        shield=$(echo "$line"  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('shield',''))" 2>/dev/null || echo "")
        cmake=$(echo "$line"   | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cmake-args',''))" 2>/dev/null || echo "")

        build_target "$board" "$artifact" "$shield" "$cmake"
    done < <(parse_build_yaml)

    echo ""
    echo "=== Build complete ==="
    ls -lh "$OUTPUT"/*.uf2
}

main "$@"
