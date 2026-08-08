#!/bin/bash
set -u

product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || printf unknown)"
codec="not found"

for node in /sys/class/sound/hwC*D*; do
    [ -r "$node/vendor_id" ] || continue
    vendor="$(cat "$node/vendor_id")"
    subsystem="$(cat "$node/subsystem_id")"
    if [ "$vendor" = "0x10ec0298" ] && [ "$subsystem" = "0x144dc14f" ]; then
        codec="$(basename "$node") ($vendor/$subsystem)"
        break
    fi
done

audio_module="$(modinfo -n snd_hda_codec_alc269 2>/dev/null || printf unavailable)"
audio_userspace="$(systemctl is-enabled alc298-book12-init.service 2>/dev/null || true)"
brightness_service="$(systemctl is-active galaxybook12-brightness.service 2>/dev/null || true)"
brightness_program="missing"
[ -x /usr/local/sbin/galaxybook12-brightness ] && brightness_program="installed"
sensor_module="$(modinfo -n st_accel_i2c 2>/dev/null || printf unavailable)"
sensor_name="not found"
for name in /sys/bus/iio/devices/iio:device*/name; do
    [ -r "$name" ] || continue
    if [ "$(cat "$name")" = "lis2hh12" ]; then
        sensor_name="lis2hh12 ($(basename "$(dirname "$name")"))"
        break
    fi
done
sensor_proxy="$(systemctl is-active iio-sensor-proxy.service 2>/dev/null || true)"

printf 'System\n'
printf '  DMI product: %s\n' "$product"
printf '\nAudio\n'
printf '  Codec: %s\n' "$codec"
printf '  Realtek module: %s\n' "$audio_module"
printf '  Userspace fallback: %s\n' "${audio_userspace:-not installed}"
printf '\nAMOLED brightness\n'
printf '  Control program: %s\n' "$brightness_program"
printf '  Service: %s\n' "${brightness_service:-not installed}"

if [ -x /usr/local/sbin/galaxybook12-brightness ]; then
    /usr/local/sbin/galaxybook12-brightness check 2>&1 | sed 's/^/  /'
elif [ -x "$(dirname "$0")/brightness/galaxybook12-brightness" ]; then
    "$(dirname "$0")/brightness/galaxybook12-brightness" check 2>&1 | sed 's/^/  /'
fi

printf '\nOrientation sensor\n'
printf '  IIO device: %s\n' "$sensor_name"
printf '  ST I2C module: %s\n' "$sensor_module"
printf '  Sensor proxy: %s\n' "${sensor_proxy:-not installed}"
