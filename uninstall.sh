#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-audio-userspace}" in
	updates)
		exec "$SCRIPT_DIR/updates/uninstall.sh"
		;;
    audio-userspace)
        exec "$SCRIPT_DIR/userspace/uninstall.sh"
        ;;
    brightness)
        exec "$SCRIPT_DIR/brightness/uninstall.sh"
        ;;
    camera-rear)
        exec "$SCRIPT_DIR/cameras/kernel/uninstall.sh"
        ;;
    help|--help|-h)
        printf 'Usage: sudo ./uninstall.sh [audio-userspace|brightness|camera-rear|updates]\n'
        ;;
    *)
        printf 'Unknown component: %s\n' "$1" >&2
        printf 'Usage: sudo ./uninstall.sh [audio-userspace|brightness|camera-rear|updates]\n' >&2
        exit 2
        ;;
esac
