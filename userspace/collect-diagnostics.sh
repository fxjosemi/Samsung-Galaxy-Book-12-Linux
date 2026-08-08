#!/bin/bash
# Read-only diagnostic collector for Samsung Galaxy Book 12 ALC298 audio.
set -euo pipefail

OUT_DIR="${1:-./diagnostics/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT_DIR"

cp /proc/asound/cards "$OUT_DIR/asound-cards.txt"
cp /proc/asound/card0/codec#0 "$OUT_DIR/codec-proc.txt"
{
    uname -a
    for name in sys_vendor product_name product_version board_name board_version bios_version; do
        printf '%s=' "$name"
        cat "/sys/class/dmi/id/$name" 2>/dev/null || printf 'unknown\n'
    done
} >"$OUT_DIR/system.txt"

{
    for node in /sys/class/sound/hwC*D*; do
        [ -r "$node/vendor_id" ] || continue
        printf '%s vendor=' "$(basename "$node")"
        cat "$node/vendor_id"
        printf '%s subsystem=' "$(basename "$node")"
        cat "$node/subsystem_id"
        printf '%s revision=' "$(basename "$node")"
        cat "$node/revision_id"
    done
} >"$OUT_DIR/codecs.txt"

amixer -c 0 contents >"$OUT_DIR/amixer-contents.txt" 2>&1 || true
pactl info >"$OUT_DIR/pactl-info.txt" 2>&1 || true
pactl list cards >"$OUT_DIR/pactl-cards.txt" 2>&1 || true
journalctl -b -k --no-pager | grep -Ei 'snd|sof|hda|codec|alc298' \
    >"$OUT_DIR/kernel-audio-log.txt" 2>&1 || true

printf 'Diagnóstico guardado en %s\n' "$OUT_DIR"
