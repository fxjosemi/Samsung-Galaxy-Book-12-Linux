#!/bin/bash
set -euo pipefail

expected_vendor="0x10ec0298"
expected_subsystem="0x144dc14f"
product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
codec="not found"

for node in /sys/class/sound/hwC*D*; do
    [ -r "$node/vendor_id" ] || continue
    vendor="$(cat "$node/vendor_id")"
    subsystem="$(cat "$node/subsystem_id")"
    if [ "$vendor" = "$expected_vendor" ] && \
       [ "$subsystem" = "$expected_subsystem" ]; then
        codec="$(basename "$node") ($vendor/$subsystem)"
        break
    fi
done

init_result="$(systemctl show alc298-book12-init.service -P Result 2>/dev/null || true)"
control_state="missing"
[ -x /usr/local/libexec/alc298-book12-control ] && control_state="installed"

printf 'DMI product: %s\n' "${product:-unknown}"
printf 'Codec: %s\n' "$codec"
printf 'Control program: %s\n' "$control_state"
printf 'Last initialization result: %s\n' "${init_result:-unknown}"

if [ "$product" != "Galaxy Book 12" ] || [ "$codec" = "not found" ]; then
    printf 'Result: unsupported or codec not ready\n' >&2
    exit 1
fi

if [ "$control_state" != "installed" ] || [ "$init_result" != "success" ]; then
    printf 'Result: hardware found, but speaker initialization is not healthy\n' >&2
    exit 1
fi

printf 'Result: userspace speaker fix is installed and initialized\n'
