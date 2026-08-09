#!/bin/bash
set -u

echo "Galaxy Book 12 camera status"
echo

if [ -e /sys/bus/acpi/devices/SONY258A:00 ]; then
	echo "Rear sensor:  Sony IMX258 (SONY258A) detected"
else
	echo "Rear sensor:  not detected"
fi
if [ -e /sys/bus/acpi/devices/INT347F:00 ]; then
	echo "Front sensor: Sony IMX241 (INT347F) detected"
else
	echo "Front sensor: not detected"
fi

if [ -L /sys/bus/i2c/drivers/imx241/i2c-INT347F:00 ]; then
	echo "Front driver: bound as a native V4L2 sensor"
elif [ -e /sys/module/imx241 ]; then
	echo "Front driver: loaded, but sensor not bound"
else
	echo "Front driver: not loaded"
fi

if [ -L /sys/bus/i2c/drivers/imx258/i2c-SONY258A:00 ]; then
	linked=false
	if command -v media-ctl >/dev/null 2>&1; then
		for media in /dev/media*; do
			[ -e "$media" ] || continue
			if media-ctl -d "$media" -p 2>/dev/null | \
			   grep -A10 'entity .*imx258' | grep -q -- '-> "ipu3-csi2'; then
				linked=true
				break
			fi
		done
	fi
	if "$linked"; then
		echo "Rear driver:  bound and linked to IPU3"
	else
		echo "Rear driver:  bound, but its IPU3 media link is incomplete"
	fi
else
	last_failure="$(journalctl -b -k --no-pager 2>/dev/null | \
		grep -E 'imx258.*(input clock frequency|Endpoint node not found|failed to read chip id)' | \
		tail -1)"
	case "$last_failure" in
		*"failed to read chip id"*)
			echo "Rear driver:  power/reset failed before chip identification"
			;;
		*"Endpoint node not found"*)
			echo "Rear driver:  IPU bridge endpoint is missing"
			;;
		*"input clock frequency"*)
			echo "Rear driver:  driver rejected Samsung's 26 MHz clock"
			;;
		*)
			echo "Rear driver:  not bound"
			;;
	esac
fi

if compgen -G '/sys/bus/i2c/drivers/dw9806b/[0-9i]*-*' >/dev/null; then
	echo "Autofocus:    DW9806B bound"
elif [ -e /sys/module/dw9806b ]; then
	echo "Autofocus:    driver loaded, but actuator not bound"
else
	echo "Autofocus:    DW9806B driver not loaded"
fi

override_dir="/usr/lib/modules/$(uname -r)/updates/galaxybook12-camera"
if [ -f "$override_dir/imx258.ko" ] && \
   [ -f "$override_dir/imx241.ko" ] && \
   [ -f "$override_dir/dw9806b.ko" ] && \
   [ -f "$override_dir/ipu-bridge.ko" ] && \
   [ -f "$override_dir/intel_skl_int3472_discrete.ko" ]; then
	echo "Overrides:    all five camera modules installed"
fi

if command -v cam >/dev/null 2>&1; then
	echo
	cam -l 2>&1 || true
else
	echo "Userspace:    libcamera tools are not installed (missing cam)"
fi

echo
echo "Media devices:"
for media in /dev/media*; do
	[ -e "$media" ] || continue
	if command -v media-ctl >/dev/null 2>&1; then
		model="$(media-ctl -d "$media" -p 2>/dev/null | sed -n 's/^model[[:space:]]*//p' | head -1)"
		echo "  $media ${model:-unknown}"
	else
		echo "  $media"
	fi
done
