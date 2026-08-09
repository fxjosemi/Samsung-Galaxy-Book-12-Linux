#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-audio-userspace}" in
    audio-userspace)
        exec "$SCRIPT_DIR/userspace/install.sh"
        ;;
    brightness)
        exec "$SCRIPT_DIR/brightness/install.sh"
        ;;
    camera-rear)
        module="${2:-$SCRIPT_DIR/cameras/kernel/build/$(uname -r)/imx258.ko}"
        exec "$SCRIPT_DIR/cameras/kernel/install.sh" "$module"
        ;;
    help|--help|-h)
        printf 'Usage: sudo ./install.sh [audio-userspace|brightness|camera-rear]\n'
        printf 'Build native audio/camera modules before installing them.\n'
        ;;
    *)
        printf 'Unknown component: %s\n' "$1" >&2
        printf 'Usage: sudo ./install.sh [audio-userspace|brightness|camera-rear]\n' >&2
        exit 2
        ;;
esac
