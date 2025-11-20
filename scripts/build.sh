#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULECACHE_PATH="$PROJECT_ROOT/.build/modulecache"

usage() {
    cat <<'EOF'
Usage: ./scripts/build.sh [--release] [-- <extra swift build args>]

Builds the iSwitch Swift package with local caches and sandbox disabled so it
works in restricted environments.

Options:
  --release   Build with -c release (defaults to debug)
  -h, --help  Show this help message

Any arguments after -- are passed directly to `swift build`.
EOF
}

CONFIG="debug"
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            CONFIG="release"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            EXTRA_ARGS+=("$@")
            break
            ;;
        *)
            EXTRA_ARGS+=("$1")
            ;;
    esac
    shift
done

# Keep caches inside the repo to avoid writing to the real home dir in sandboxes.
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULECACHE_PATH"
export HOME="$PROJECT_ROOT/.home"
mkdir -p "$MODULECACHE_PATH" "$HOME"

cd "$PROJECT_ROOT"

COMMON_ARGS=(
    --disable-sandbox
    -c "$CONFIG"
    -Xcc "-fmodules-cache-path=$MODULECACHE_PATH"
    -Xswiftc -module-cache-path
    -Xswiftc "$MODULECACHE_PATH"
)

if ((${#EXTRA_ARGS[@]})); then
    swift build "${COMMON_ARGS[@]}" "${EXTRA_ARGS[@]}"
else
    swift build "${COMMON_ARGS[@]}"
fi
