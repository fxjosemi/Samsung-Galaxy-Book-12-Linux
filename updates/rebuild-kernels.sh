#!/bin/bash
set -euo pipefail

SOURCE_ROOT="${GALAXYBOOK12_SOURCE_ROOT:-/usr/local/src/galaxybook12-linux}"
CONFIG_FILE="${GALAXYBOOK12_CONFIG:-/etc/galaxybook12-update.conf}"
STATE_ROOT="/var/lib/galaxybook12-update"
LOCK_FILE="/run/lock/galaxybook12-update.lock"
MODE="${1:---all}"

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: run this command with sudo" >&2
	exit 1
fi
if [ ! -r "$CONFIG_FILE" ]; then
	echo "ERROR: update configuration is missing: $CONFIG_FILE" >&2
	exit 1
fi
if [ ! -x "$SOURCE_ROOT/kernel/build-module.sh" ]; then
	echo "ERROR: installed driver sources are missing: $SOURCE_ROOT" >&2
	exit 1
fi

# This file is installed by this project and only contains shell assignments.
# shellcheck source=/dev/null
source "$CONFIG_FILE"
: "${COMPONENTS:=audio brightness cameras sensors}"
: "${KERNEL_PACKAGES:=linux-cachyos}"
: "${JOBS:=2}"

case "$JOBS" in
	"" | *[!0-9]* | 0) echo "ERROR: invalid JOBS value" >&2; exit 1 ;;
esac

exec 9>"$LOCK_FILE"
flock 9

declare -A requested=()
case "$MODE" in
	--pacman-targets)
		while IFS= read -r target; do
			case "$target" in
				usr/lib/modules/*/pkgbase|usr/lib/modules/*/build/Makefile)
					release="${target#usr/lib/modules/}"
					release="${release%%/*}"
					requested["$release"]=1
					;;
			esac
		done
		;;
	--all)
		for build_dir in /usr/lib/modules/*/build; do
			[ -d "$build_dir" ] || continue
			requested["$(basename "$(dirname "$build_dir")")"]=1
		done
		;;
	*)
		echo "Usage: $0 [--all|--pacman-targets]" >&2
		exit 2
		;;
esac

contains_word() {
	case " $1 " in *" $2 "*) return 0 ;; *) return 1 ;; esac
}

rebuild_initramfs() {
	if command -v mkinitcpio >/dev/null 2>&1; then
		mkinitcpio -P
	elif command -v update-initramfs >/dev/null 2>&1; then
		for release in "$@"; do update-initramfs -u -k "$release"; done
	elif command -v dracut >/dev/null 2>&1; then
		for release in "$@"; do dracut --force --kver "$release"; done
	else
		echo "ERROR: no supported initramfs generator was found" >&2
		return 1
	fi
}

selected=()
missing_headers=()
for release in "${!requested[@]}"; do
	case "$release" in
		"" | *[![:alnum:]._+-]*) continue ;;
	esac
	pkgbase="$(cat "/usr/lib/modules/$release/pkgbase" 2>/dev/null || true)"
	contains_word "$KERNEL_PACKAGES" "$pkgbase" || continue
	if [ ! -d "/usr/lib/modules/$release/build" ]; then
		echo "ERROR: $release is managed but its matching headers are not installed" >&2
		missing_headers+=("$release")
		continue
	fi
	selected+=("$release")
done

if [ "${#missing_headers[@]}" -ne 0 ]; then
	echo "Install the matching header package before booting the new kernel." >&2
	exit 1
fi

if [ "${#selected[@]}" -eq 0 ]; then
	echo "Galaxy Book 12: no managed kernel with matching headers changed."
	exit 0
fi

# Compile every component before replacing any module. A patch failure therefore
# leaves the new kernel untouched and the recovery kernel remains available.
for release in "${selected[@]}"; do
	echo "Galaxy Book 12: compiling drivers for $release"
	if contains_word "$COMPONENTS" audio; then
		KERNEL_RELEASE="$release" JOBS="$JOBS" "$SOURCE_ROOT/kernel/build-module.sh"
	fi
	if contains_word "$COMPONENTS" brightness; then
		KERNEL_RELEASE="$release" JOBS="$JOBS" "$SOURCE_ROOT/brightness/kernel/build-module.sh"
	fi
	if contains_word "$COMPONENTS" cameras; then
		KERNEL_RELEASE="$release" JOBS="$JOBS" "$SOURCE_ROOT/cameras/kernel/build-module.sh"
	fi
	if contains_word "$COMPONENTS" sensors; then
		KERNEL_RELEASE="$release" JOBS="$JOBS" "$SOURCE_ROOT/sensors/kernel/build-module.sh"
	fi
done

for release in "${selected[@]}"; do
	echo "Galaxy Book 12: installing drivers for $release"
	if contains_word "$COMPONENTS" audio; then
		KERNEL_RELEASE="$release" "$SOURCE_ROOT/kernel/install-native.sh" \
			"$SOURCE_ROOT/kernel/build/$release/snd-hda-codec-alc269.ko"
	fi
	if contains_word "$COMPONENTS" brightness; then
		KERNEL_RELEASE="$release" SKIP_INITRAMFS=1 \
			"$SOURCE_ROOT/brightness/kernel/install-native.sh" \
			"$SOURCE_ROOT/brightness/kernel/build/$release/i915.ko"
	fi
	if contains_word "$COMPONENTS" cameras; then
		KERNEL_RELEASE="$release" "$SOURCE_ROOT/cameras/kernel/install.sh" \
			"$SOURCE_ROOT/cameras/kernel/build/$release/imx258.ko"
	fi
	if contains_word "$COMPONENTS" sensors; then
		KERNEL_RELEASE="$release" SKIP_INITRAMFS=1 \
			"$SOURCE_ROOT/sensors/kernel/install.sh" \
			"$SOURCE_ROOT/sensors/kernel/build/$release"
	fi
done

rebuild_initramfs "${selected[@]}"
install -d -m 755 "$STATE_ROOT"
for release in "${selected[@]}"; do
	printf '%s\n' "$(date --iso-8601=seconds)" > "$STATE_ROOT/$release.ok"
done

echo "Galaxy Book 12: kernel update integration completed successfully."
echo "Reboot only after this message appears."
