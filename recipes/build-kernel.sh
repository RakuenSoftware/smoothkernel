#!/usr/bin/env bash
# build-kernel.sh — fetch a kernel.org tarball, apply vendored patch
# lanes, seed the canonical .config, and either refresh configs/ or
# produce linux-image / linux-headers / linux-libc-dev .deb files via
# the in-tree `make bindeb-pkg` target.
#
# Required env (set in build.env or the calling shell):
#   KERNEL_VERSION    e.g. 6.18.22
#   LOCALVERSION      e.g. -smoothnas-lts (must start with -)
#   CONFIG_SOURCE     path to canonical .config seed
#
# Optional env:
#   OUT_DIR           where the .debs land (default $(pwd)/out)
#   BUILD_THREADS     -j N for make (default $(nproc))
#   CACHYOS_PATCHSET  default cachyos-$KERNEL_VERSION
#   NOBARA_PATCHSET   default nobara-picks
#   POST_NOBARA_PATCHSET default post-nobara-$KERNEL_VERSION
#   MODE              build (default) or update-config
#   STRIP_DEBUG_INFO  if "1" (default), strip BTF/DWARF to slim the
#                     image and speed up packaging

set -euo pipefail

: "${KERNEL_VERSION:?KERNEL_VERSION required (e.g. 6.18.22)}"
: "${LOCALVERSION:?LOCALVERSION required (e.g. -smoothnas-lts)}"
: "${CONFIG_SOURCE:?CONFIG_SOURCE required (path to seed .config)}"
[[ "$LOCALVERSION" == -* ]] || { echo "LOCALVERSION must start with '-'"; exit 1; }

OUT_DIR="${OUT_DIR:-$(pwd)/out}"
BUILD_THREADS="${BUILD_THREADS:-$(nproc)}"
CACHYOS_PATCHSET="${CACHYOS_PATCHSET:-cachyos-$KERNEL_VERSION}"
NOBARA_PATCHSET="${NOBARA_PATCHSET:-nobara-picks}"
POST_NOBARA_PATCHSET="${POST_NOBARA_PATCHSET:-post-nobara-$KERNEL_VERSION}"
MODE="${MODE:-build}"
STRIP_DEBUG_INFO="${STRIP_DEBUG_INFO:-1}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/kernel-$KERNEL_VERSION"
TARBALL="linux-$KERNEL_VERSION.tar.xz"
SHA_FILE="sha256sums.asc"
KERNEL_MAJOR="${KERNEL_VERSION%%.*}"
PATCH_ROOT="$ROOT/patches"
VERSIONED_CONFIG_DIR="$ROOT/configs/$KERNEL_VERSION"
VERSIONED_CONFIG="$VERSIONED_CONFIG_DIR/smooth-amd64.config"

apply_patch_stack() {
    local patch_dir="$1"
    local patch found=0

    [[ -d "$patch_dir" ]] || return 0

    while IFS= read -r patch; do
        [[ -n "$patch" ]] || continue
        if [[ $found -eq 0 ]]; then
            echo "==> applying patches from $patch_dir"
            found=1
        fi
        echo "    -> $(basename "$patch")"
        patch -Np1 < "$patch"
    done < <(find "$patch_dir" -maxdepth 1 -type f -name '*.patch' | sort)
}

apply_smoothkernel_profile() {
    echo "==> applying SmoothKernel profile"

    scripts/config --disable PREEMPT_NONE \
                   --disable PREEMPT_VOLUNTARY \
                   --enable PREEMPT \
                   --enable PREEMPT_DYNAMIC \
                   --disable HZ_100 \
                   --disable HZ_250 \
                   --disable HZ_300 \
                   --disable HZ_500 \
                   --enable HZ_1000 \
                   --enable SCHED_BORE

    if [[ "$STRIP_DEBUG_INFO" = "1" ]]; then
        echo "==> stripping debug-info bloat"
        scripts/config --disable DEBUG_INFO_BTF \
                       --disable DEBUG_INFO_DWARF5 \
                       --disable DEBUG_INFO_DWARF4 \
                       --disable SYSTEM_TRUSTED_KEYS \
                       --disable SYSTEM_REVOCATION_KEYS
    fi

    # NAS / server network-path tuning.
    NET_TUNING="${NET_TUNING:-1}"
    if [[ "$NET_TUNING" = "1" ]]; then
        echo "==> applying NAS network-path tuning"
        scripts/config --enable TCP_CONG_BBR \
                       --disable DEFAULT_CUBIC \
                       --enable DEFAULT_BBR \
                       --enable NET_SCH_FQ \
                       --disable DEFAULT_FQ_CODEL \
                       --enable DEFAULT_FQ \
                       --enable NET_RX_BUSY_POLL \
                       --enable TCP_MD5SIG \
                       --module TCP_CONG_DCTCP
    fi

    # Server / appliance general tuning.
    SERVER_TUNING="${SERVER_TUNING:-1}"
    if [[ "$SERVER_TUNING" = "1" ]]; then
        echo "==> applying server / appliance general tuning"
        scripts/config --enable PREEMPT_DYNAMIC \
                       --enable RCU_NOCB_CPU \
                       --enable BLK_WBT_MQ
    fi

    # Appliance driver trim.
    APPLIANCE_TRIM="${APPLIANCE_TRIM:-1}"
    if [[ "$APPLIANCE_TRIM" = "1" ]]; then
        echo "==> trimming cross-flavor-irrelevant legacy / appliance hardware"

        # Keep HTPC / Desktop paths intact in the shared kernel.
        scripts/config --module DRM \
                       --enable SOUND \
                       --module SND \
                       --enable WLAN \
                       --module CFG80211 \
                       --module MAC80211 \
                       --enable MEDIA_SUPPORT \
                       --module GAMEPORT \
                       --enable INPUT_JOYSTICK \
                       --enable INPUT_TABLET \
                       --enable INPUT_TOUCHSCREEN \
                       --enable ACCESSIBILITY
        scripts/config --disable HAMRADIO \
                       --disable ISDN \
                       --disable ATM \
                       --disable LAPB \
                       --disable PHONET \
                       --disable SLIP \
                       --disable PARPORT
        scripts/config --disable BATMAN_ADV \
                       --disable IEEE802154 \
                       --disable 6LOWPAN
        scripts/config --disable PCMCIA \
                       --disable MTD
        scripts/config --disable MAC_PARTITION \
                       --disable AMIGA_PARTITION \
                       --disable ATARI_PARTITION \
                       --disable SUN_PARTITION
        scripts/config --disable SCSI_AIC79XX \
                       --disable SCSI_AIC7XXX \
                       --disable SCSI_3W_9XXX \
                       --disable SCSI_QLOGIC_1280 \
                       --disable BLK_DEV_3W_XXXX_RAID
        scripts/config --disable MINIX_FS
        scripts/config --disable COMEDI
    fi

    # Keep the minimal Bluetooth HID path needed for Nobara's controller picks.
    scripts/config --module BT \
                   --module BT_HIDP
    if [[ -f drivers/hid/xpadneo/Kconfig ]]; then
        scripts/config --module HID_XPADNEO
    fi

    scripts/config --set-str LOCALVERSION "$LOCALVERSION"
    make olddefconfig </dev/null >/dev/null
}

mkdir -p "$BUILD_DIR" "$OUT_DIR"
cd "$BUILD_DIR"

if [[ ! -f "$TARBALL" ]]; then
    echo "==> downloading $TARBALL"
    curl -fsSL -O "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/$TARBALL"
fi
if [[ ! -f "$SHA_FILE" ]]; then
    curl -fsSL -O "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/$SHA_FILE"
fi
echo "==> verifying sha256"
grep "$TARBALL" "$SHA_FILE" | sha256sum -c -

SRC_DIR="linux-$KERNEL_VERSION"
rm -rf "$SRC_DIR"
echo "==> extracting"
tar xf "$TARBALL"

cd "$SRC_DIR"

apply_patch_stack "$PATCH_ROOT/$CACHYOS_PATCHSET"
apply_patch_stack "$PATCH_ROOT/$NOBARA_PATCHSET"
apply_patch_stack "$PATCH_ROOT/$POST_NOBARA_PATCHSET"

echo "==> seeding .config from $CONFIG_SOURCE"
cp "$CONFIG_SOURCE" .config
make olddefconfig </dev/null >/dev/null

apply_smoothkernel_profile

if [[ "$MODE" == "update-config" ]]; then
    echo "==> writing refreshed configs"
    mkdir -p "$VERSIONED_CONFIG_DIR"
    cp .config "$CONFIG_SOURCE"
    cp .config "$VERSIONED_CONFIG"
    echo "==> wrote $CONFIG_SOURCE"
    echo "==> wrote $VERSIONED_CONFIG"
    exit 0
fi

echo "==> building (-j${BUILD_THREADS})"
date
# Recursive make must not inherit LOCALVERSION from the top-level wrapper,
# or bindeb-pkg appends the suffix on top of CONFIG_LOCALVERSION again.
env -u LOCALVERSION -u MAKEFLAGS make -j"$BUILD_THREADS" bindeb-pkg
date

echo "==> collecting .debs into $OUT_DIR"
shopt -s nullglob
moved=()
# bindeb-pkg produces linux-image / linux-image-dbg / linux-headers /
# linux-libc-dev for <UTS_RELEASE>, where UTS_RELEASE comes from the
# checked-in .config LOCALVERSION.
LOCAL_TAG="${LOCALVERSION#-}"  # strip leading '-' so "smooth" anchors the glob cleanly
for f in "../linux-image-${KERNEL_VERSION}-${LOCAL_TAG}"*"_${KERNEL_VERSION}-"*"_"*.deb \
         "../linux-headers-${KERNEL_VERSION}-${LOCAL_TAG}"*"_${KERNEL_VERSION}-"*"_"*.deb \
         "../linux-libc-dev_${KERNEL_VERSION}-"*"_"*.deb; do
    cp -v "$f" "$OUT_DIR/"
    moved+=("$f")
done
if [[ ${#moved[@]} -lt 3 ]]; then
    echo "ERROR: expected image + headers + libc-dev .debs, got ${#moved[@]}" >&2
    ls -la ../ | grep '\.deb$' >&2
    exit 1
fi
echo "==> done. Built ${#moved[@]} .debs in $OUT_DIR"
