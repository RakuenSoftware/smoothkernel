#!/usr/bin/env bash
# build-kernel.sh — fetch a kernel.org tarball, apply vendored patch
# lanes, seed the canonical .config, and either refresh configs/ or
# produce linux-image / linux-headers / linux-libc-dev .deb files via
# the in-tree `make bindeb-pkg` target.
#
# Required env (set in build.env or the calling shell):
#   KERNEL_VERSION    e.g. 6.18.22
#   LOCALVERSION      e.g. -smoothkernel (must start with -)
#
# Optional env:
#   DEB_ARCH          Debian architecture: amd64 or arm64 (default amd64)
#   CONFIG_SOURCE     path to canonical .config seed
#   KERNEL_ARCH       kernel ARCH override (default mapped from DEB_ARCH)
#   CROSS_COMPILE     kernel cross-compiler prefix, if not building native
#   KERNEL_DEFCONFIG  defconfig target used when creating a new config
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
: "${LOCALVERSION:?LOCALVERSION required (e.g. -smoothkernel)}"
[[ "$LOCALVERSION" == -* ]] || { echo "LOCALVERSION must start with '-'"; exit 1; }

DEB_ARCH="${DEB_ARCH:-amd64}"
OUT_DIR="${OUT_DIR:-$(pwd)/out}"
BUILD_THREADS="${BUILD_THREADS:-$(nproc)}"
CACHYOS_PATCHSET="${CACHYOS_PATCHSET:-cachyos-$KERNEL_VERSION}"
NOBARA_PATCHSET="${NOBARA_PATCHSET:-nobara-picks}"
POST_NOBARA_PATCHSET="${POST_NOBARA_PATCHSET:-post-nobara-$KERNEL_VERSION}"
MODE="${MODE:-build}"
STRIP_DEBUG_INFO="${STRIP_DEBUG_INFO:-1}"
KERNEL_DEFCONFIG="${KERNEL_DEFCONFIG:-defconfig}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_SOURCE="${CONFIG_SOURCE:-$ROOT/configs/smooth-$DEB_ARCH.config}"

case "$DEB_ARCH" in
    amd64)
        KERNEL_ARCH="${KERNEL_ARCH:-x86}"
        if [[ -z "${CROSS_COMPILE+x}" && "$(uname -m)" != "x86_64" ]]; then
            CROSS_COMPILE="x86_64-linux-gnu-"
        else
            CROSS_COMPILE="${CROSS_COMPILE:-}"
        fi
        ;;
    arm64)
        KERNEL_ARCH="${KERNEL_ARCH:-arm64}"
        if [[ -z "${CROSS_COMPILE+x}" && "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
            CROSS_COMPILE="aarch64-linux-gnu-"
        else
            CROSS_COMPILE="${CROSS_COMPILE:-}"
        fi
        ;;
    *)
        echo "ERROR: unsupported DEB_ARCH '$DEB_ARCH' (expected amd64 or arm64)" >&2
        exit 1
        ;;
esac

BUILD_DIR="$ROOT/build/kernel-$KERNEL_VERSION-$DEB_ARCH"
TARBALL="linux-$KERNEL_VERSION.tar.xz"
SHA_FILE="sha256sums.asc"
KERNEL_MAJOR="${KERNEL_VERSION%%.*}"
PATCH_ROOT="$ROOT/patches"
VERSIONED_CONFIG_DIR="$ROOT/configs/$KERNEL_VERSION"
VERSIONED_CONFIG="$VERSIONED_CONFIG_DIR/smooth-$DEB_ARCH.config"

kernel_make_args=(ARCH="$KERNEL_ARCH" KBUILD_DEBARCH="$DEB_ARCH")
if [[ -n "$CROSS_COMPILE" ]]; then
    kernel_make_args+=(CROSS_COMPILE="$CROSS_COMPILE")
fi

kernel_make() {
    make "${kernel_make_args[@]}" "$@"
}

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

    scripts/config --enable MODULES \
                   --enable MODULE_SIG \
                   --enable MODULE_SIG_ALL \
                   --enable MODULE_SIG_SHA256 \
                   --disable MODULE_SIG_SHA1 \
                   --disable MODULE_SIG_SHA384 \
                   --disable MODULE_SIG_SHA512 \
                   --disable MODULE_SIG_SHA3_256 \
                   --disable MODULE_SIG_SHA3_384 \
                   --disable MODULE_SIG_SHA3_512

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
        scripts/config --enable NET_SCHED \
                       --enable TCP_CONG_ADVANCED \
                       --enable TCP_CONG_BBR \
                       --disable DEFAULT_CUBIC \
                       --enable DEFAULT_BBR \
                       --set-str DEFAULT_TCP_CONG "bbr" \
                       --enable NET_SCH_FQ \
                       --disable DEFAULT_FQ_CODEL \
                       --enable DEFAULT_FQ \
                       --set-str DEFAULT_NET_SCH "fq" \
                       --enable NET_RX_BUSY_POLL \
                       --enable TCP_MD5SIG \
                       --module TCP_CONG_DCTCP
        scripts/config --enable NET_SCH_DEFAULT \
                       --enable DEFAULT_FQ \
                       --set-str DEFAULT_NET_SCH "fq"
    fi

    # Server / appliance general tuning.
    SERVER_TUNING="${SERVER_TUNING:-1}"
    if [[ "$SERVER_TUNING" = "1" ]]; then
        echo "==> applying server / appliance general tuning"
        scripts/config --enable PREEMPT_DYNAMIC \
                       --enable RCU_NOCB_CPU \
                       --enable BLK_WBT_MQ
    fi

    echo "==> applying shared storage / network / workstation support"
    scripts/config --module EXT4_FS \
                   --module XFS_FS \
                   --module BTRFS_FS \
                   --module BCACHEFS_FS \
                   --module NTFS3_FS \
                   --module F2FS_FS \
                   --module EXFAT_FS \
                   --module VFAT_FS \
                   --module MSDOS_FS \
                   --module NFS_FS \
                   --module NFSD \
                   --module CIFS
    scripts/config --enable NETFILTER \
                   --module NF_TABLES \
                   --module NFT_CT \
                   --module NFT_MASQ \
                   --module NFT_NAT \
                   --module NFT_REJECT \
                   --module NFT_LOG \
                   --module NFT_LIMIT \
                   --module NFT_COUNTER \
                   --module NFT_FIB \
                   --module NFT_FIB_INET \
                   --module NFT_REDIR \
                   --module NFT_FLOW_OFFLOAD \
                   --module WIREGUARD
    scripts/config --module BLK_DEV_NVME \
                   --module ATA \
                   --module SATA_AHCI \
                   --module BLK_DEV_DM \
                   --enable MD \
                   --module USB_STORAGE
    scripts/config --module E1000E \
                   --module IGC \
                   --module IXGBE \
                   --module I40E \
                   --module R8169 \
                   --module ATLANTIC \
                   --module MLX4_EN \
                   --module MLX5_CORE \
                   --module BNXT

    # Appliance driver trim.
    APPLIANCE_TRIM="${APPLIANCE_TRIM:-1}"
    if [[ "$APPLIANCE_TRIM" = "1" ]]; then
        echo "==> trimming cross-flavor-irrelevant legacy / appliance hardware"

        # Keep HTPC / Desktop paths intact in the shared kernel.
        # Real GPU drivers for bare-metal installs; VM display drivers
        # (virtio-vga, QEMU std/bochs, EFI simpledrm) so the installer
        # kernel can drive Xorg in KVM/QEMU/PVE guests.
        scripts/config --module DRM \
                       --module DRM_RADEON \
                       --module DRM_AMDGPU \
                       --module DRM_NOUVEAU \
                       --module DRM_I915 \
                       --module DRM_XE \
                       --module DRM_VMWGFX \
                       --module DRM_QXL \
                       --module DRM_VBOXVIDEO \
                       --module DRM_VIRTIO_GPU \
                       --enable DRM_VIRTIO_GPU_KMS \
                       --module DRM_BOCHS \
                       --module DRM_SIMPLEDRM \
                       --enable SYSFB_SIMPLEFB \
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
    kernel_make olddefconfig </dev/null >/dev/null
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

echo "==> build arch: DEB_ARCH=$DEB_ARCH ARCH=$KERNEL_ARCH"
if [[ -n "$CROSS_COMPILE" ]]; then
    echo "==> cross compiler prefix: $CROSS_COMPILE"
fi

if [[ -f "$CONFIG_SOURCE" ]]; then
    echo "==> seeding .config from $CONFIG_SOURCE"
    cp "$CONFIG_SOURCE" .config
    kernel_make olddefconfig </dev/null >/dev/null
elif [[ "$MODE" == "update-config" ]]; then
    echo "==> no config at $CONFIG_SOURCE; seeding from $KERNEL_DEFCONFIG"
    kernel_make "$KERNEL_DEFCONFIG" </dev/null >/dev/null
else
    echo "ERROR: CONFIG_SOURCE does not exist: $CONFIG_SOURCE" >&2
    echo "Run 'make kernel-config-update DEB_ARCH=$DEB_ARCH' to create it." >&2
    exit 1
fi

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
env -u LOCALVERSION -u MAKEFLAGS make "${kernel_make_args[@]}" -j"$BUILD_THREADS" bindeb-pkg
date

echo "==> collecting .debs into $OUT_DIR"
shopt -s nullglob
moved=()
# bindeb-pkg produces linux-image / linux-image-dbg / linux-headers /
# linux-libc-dev for <UTS_RELEASE>, where UTS_RELEASE comes from the
# checked-in .config LOCALVERSION.
LOCAL_TAG="${LOCALVERSION#-}"  # strip leading '-' so "smooth" anchors the glob cleanly
for f in "../linux-image-${KERNEL_VERSION}-${LOCAL_TAG}"*"_${KERNEL_VERSION}-"*"_${DEB_ARCH}.deb" \
         "../linux-headers-${KERNEL_VERSION}-${LOCAL_TAG}"*"_${KERNEL_VERSION}-"*"_${DEB_ARCH}.deb" \
         "../linux-libc-dev_${KERNEL_VERSION}-"*"_${DEB_ARCH}.deb"; do
    cp -v "$f" "$OUT_DIR/"
    moved+=("$f")
done
if [[ ${#moved[@]} -lt 3 ]]; then
    echo "ERROR: expected image + headers + libc-dev .debs, got ${#moved[@]}" >&2
    ls -la ../ | grep '\.deb$' >&2
    exit 1
fi
echo "==> done. Built ${#moved[@]} .debs in $OUT_DIR"
