#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-audio-userspace}" in
    audio-userspace)
        exec "$SCRIPT_DIR/userspace/uninstall.sh"
        ;;
    brightness)
        exec "$SCRIPT_DIR/brightness/uninstall.sh"
        ;;
    help|--help|-h)
        printf 'Usage: sudo ./uninstall.sh [audio-userspace|brightness]\n'
        ;;
    *)
        printf 'Unknown component: %s\n' "$1" >&2
        printf 'Usage: sudo ./uninstall.sh [audio-userspace|brightness]\n' >&2
        exit 2
        ;;
esac
