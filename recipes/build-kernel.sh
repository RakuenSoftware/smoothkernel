#!/usr/bin/env bash
# build-kernel.sh — fetch a kernel.org tarball and produce
# linux-image / linux-headers / linux-libc-dev .deb files via the
# in-tree `make bindeb-pkg` target.
#
# Required env (set in build.env or the calling shell):
#   KERNEL_VERSION    e.g. 6.18.22
#   LOCALVERSION      e.g. -smooth (must start with -)
#   CONFIG_SOURCE     path to seed .config (currently caller-supplied;
#                     usually copied from
#                     the running kernel of a known-good box)
#
# Optional env:
#   OUT_DIR           where the .debs land (default $(pwd)/out)
#   BUILD_THREADS     -j N for make (default $(nproc))
#   STRIP_DEBUG_INFO  if "1" (default), strip BTF/DWARF to slim the
#                     image and speed up packaging

set -euo pipefail

: "${KERNEL_VERSION:?KERNEL_VERSION required (e.g. 6.18.22)}"
: "${LOCALVERSION:?LOCALVERSION required (e.g. -smooth)}"
: "${CONFIG_SOURCE:?CONFIG_SOURCE required (path to seed .config)}"
[[ "$LOCALVERSION" == -* ]] || { echo "LOCALVERSION must start with '-'"; exit 1; }

OUT_DIR="${OUT_DIR:-$(pwd)/out}"
BUILD_THREADS="${BUILD_THREADS:-$(nproc)}"
STRIP_DEBUG_INFO="${STRIP_DEBUG_INFO:-1}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/kernel-$KERNEL_VERSION"
TARBALL="linux-$KERNEL_VERSION.tar.xz"
SHA_FILE="sha256sums.asc"
KERNEL_MAJOR="${KERNEL_VERSION%%.*}"

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
if [[ ! -d "$SRC_DIR" ]]; then
    echo "==> extracting"
    tar xf "$TARBALL"
fi

cd "$SRC_DIR"

echo "==> seeding .config from $CONFIG_SOURCE"
cp "$CONFIG_SOURCE" .config
make olddefconfig </dev/null >/dev/null

if [[ "$STRIP_DEBUG_INFO" = "1" ]]; then
    echo "==> stripping debug-info bloat"
    scripts/config --disable DEBUG_INFO_BTF \
                   --disable DEBUG_INFO_DWARF5 \
                   --disable DEBUG_INFO_DWARF4 \
                   --disable SYSTEM_TRUSTED_KEYS \
                   --disable SYSTEM_REVOCATION_KEYS
fi

# NAS / server network-path tuning. Debian's stock config builds
# TCP_CONG_BBR as a module and defaults to cubic; for the Smooth*
# appliance class we want BBR available + default, and a handful of
# latency-sensitive network-path knobs compiled in. Toggle with
# NET_TUNING=0 for a build that wants the upstream defaults (e.g. a
# dev kernel that reproduces a Debian-side bug).
NET_TUNING="${NET_TUNING:-1}"
if [[ "$NET_TUNING" = "1" ]]; then
    echo "==> applying NAS network-path tuning"
    # BBR + FQ built in so the boot-time net.core.default_qdisc=fq +
    # net.ipv4.tcp_congestion_control=bbr settings take effect before
    # any module load. NET_RX_BUSY_POLL enables SO_BUSY_POLL /
    # sysctl-driven busy polling for sub-ms latency on NFS/SMB
    # metadata ops. TCP_MD5SIG is cheap and routinely required.
    # TCP_CONG_DCTCP is a useful opt-in for LAN with ECN-capable
    # switches (selectable per-route via "ip route ... congctl dctcp").
    #
    # DEFAULT_TCP_CONG is derived from the DEFAULT_{BBR,CUBIC,...}
    # choice — flipping the choice is how you change the runtime
    # default; setting the string directly is overwritten by
    # olddefconfig. NF_FLOW_TABLE (HW-offloadable fast-path conntrack
    # for nftables flow offload) is already a module in Debian's
    # stock config; no override needed.
    # NET_SCH_DEFAULT exposes DEFAULT_{FQ,FQ_CODEL,PFIFO_FAST,...} as a
    # choice. Debian ships DEFAULT_FQ_CODEL=y; flip to DEFAULT_FQ so
    # the boot-time qdisc is the one BBR is designed to pace over,
    # without requiring the /etc/sysctl.d drop-in to take effect first.
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

# Server / appliance general tuning (not strictly network). Toggle
# with SERVER_TUNING=0 to reproduce upstream defaults.
SERVER_TUNING="${SERVER_TUNING:-1}"
if [[ "$SERVER_TUNING" = "1" ]]; then
    echo "==> applying server / appliance general tuning"
    # PREEMPT_DYNAMIC lets operators flip preempt=voluntary|full|none
    # via the kernel command line without a rebuild — useful for
    # triage runs against latency regressions.
    # RCU_NOCB_CPU enables 'rcu_nocbs=<cores>' on cmdline to isolate
    # RCU callback work from NIC-servicing / tierd cores. The feature
    # is opt-in at boot; compiling it in has negligible overhead.
    # BLK_WBT_MQ enables writeback throttling on the multi-queue
    # block layer, which real-world smooths tail latency under the
    # NAS pattern of concurrent writers + one latency-sensitive
    # reader (e.g. an SMB rename during a large rsync write).
    scripts/config --enable PREEMPT_DYNAMIC \
                   --enable RCU_NOCB_CPU \
                   --enable BLK_WBT_MQ
fi

# Appliance driver trim — drop driver families that no Smooth* product
# (NAS or Router) ever uses on real hardware. Toggle with
# APPLIANCE_TRIM=0 to keep the upstream/Debian driver set, e.g. when
# bisecting a hardware-detection issue against a stock build.
#
# Selection method: walk the seed .config for every "=y" or "=m" symbol
# that maps to a desktop, laptop, embedded, or legacy-protocol use case
# we don't ship hardware for. Cascading is preferred over per-driver
# disables — disabling DRM cascades to AMDGPU/I915/NOUVEAU/RADEON,
# disabling MEDIA_SUPPORT cascades to V4L2/DVB/RC_CORE/LIRC, and so on.
#
# Net effect: substantially smaller linux-image .deb, faster builds,
# smaller initramfs. Re-enable a family by removing its line from this
# block, or set APPLIANCE_TRIM=0 wholesale.
APPLIANCE_TRIM="${APPLIANCE_TRIM:-1}"
if [[ "$APPLIANCE_TRIM" = "1" ]]; then
    echo "==> trimming appliance-irrelevant driver families"

    # GPU / display / audio — both products are headless. VGA_CONSOLE
    # and EFI/VESA framebuffer remain so the boot console works.
    # Dropping DRM cascades to AMDGPU/I915/NOUVEAU/RADEON/VMWGFX/...
    # ACPI_VIDEO is the laptop brightness/hotkey driver.
    scripts/config --disable DRM \
                   --disable AGP \
                   --disable ACPI_VIDEO \
                   --disable SOUND \
                   --disable SND

    # Wireless / RF — Smooth* devices are wired-only; Router uses
    # upstream Ethernet and SFP+. If a future SmoothROUTER variant adds
    # an internal Wi-Fi access-point mode, drop these or flip
    # APPLIANCE_TRIM=0. NFC is for tap-to-pair phones — not us.
    scripts/config --disable WLAN \
                   --disable CFG80211 \
                   --disable MAC80211 \
                   --disable BT \
                   --disable NFC

    # Capture / media / IR — no webcam, no DVB/ATSC tuner, no remote
    # control receiver. MEDIA_SUPPORT cascades to V4L2 / RC_CORE / LIRC
    # / DVB_CORE, but BATMAN_ADV (mesh) lives elsewhere.
    scripts/config --disable MEDIA_SUPPORT

    # Legacy / dead WAN and link-layer protocols.
    scripts/config --disable HAMRADIO \
                   --disable ISDN \
                   --disable ATM \
                   --disable LAPB \
                   --disable PHONET \
                   --disable SLIP \
                   --disable PARPORT

    # IoT / mesh networking we don't terminate.
    scripts/config --disable BATMAN_ADV \
                   --disable IEEE802154 \
                   --disable 6LOWPAN

    # Legacy buses — none of these have shipped on a server in years.
    # FIREWIRE = IEEE 1394; PCMCIA = laptop card slots; MTD = raw
    # NAND/NOR flash on embedded boards.
    scripts/config --disable FIREWIRE \
                   --disable PCMCIA \
                   --disable MTD

    # Input devices we'll never see on a headless box.
    scripts/config --disable GAMEPORT \
                   --disable INPUT_JOYSTICK \
                   --disable INPUT_TABLET \
                   --disable INPUT_TOUCHSCREEN

    # Exotic partition tables — keep MSDOS + EFI_PARTITION (default
    # =y, untouched). Drop Mac/Amiga/Atari/Sun.
    scripts/config --disable MAC_PARTITION \
                   --disable AMIGA_PARTITION \
                   --disable ATARI_PARTITION \
                   --disable SUN_PARTITION

    # Legacy / EOL storage HBAs.
    scripts/config --disable SCSI_AIC79XX \
                   --disable SCSI_AIC7XXX \
                   --disable SCSI_3W_9XXX \
                   --disable SCSI_QLOGIC_1280 \
                   --disable BLK_DEV_3W_XXXX_RAID

    # Toy / unused filesystems. Keep XFS, EXT4, BTRFS, F2FS, OVERLAY,
    # SQUASHFS, ISO9660, UDF, VFAT, NTFS3 (any of which may already be
    # =y/=m in the seed and are NOT touched here).
    scripts/config --disable MINIX_FS

    # Misc. ACCESSIBILITY = BRAILLE/speech for desktop a11y. COMEDI =
    # industrial data acquisition. STAGING = drivers still under dev.
    # SURFACE_AGGREGATOR = Microsoft Surface SoC. INTEL_MEI_{HDCP,PXP}
    # = DRM content protection over the management engine.
    scripts/config --disable ACCESSIBILITY \
                   --disable COMEDI \
                   --disable STAGING \
                   --disable SURFACE_AGGREGATOR \
                   --disable INTEL_MEI_HDCP \
                   --disable INTEL_MEI_PXP
fi

scripts/config --set-str LOCALVERSION "$LOCALVERSION"
make olddefconfig </dev/null >/dev/null

echo "==> building (-j${BUILD_THREADS})"
date
make -j"$BUILD_THREADS" bindeb-pkg LOCALVERSION="$LOCALVERSION"
date

echo "==> collecting .debs into $OUT_DIR"
shopt -s nullglob
moved=()
# bindeb-pkg produces linux-image / linux-image-dbg / linux-headers /
# linux-libc-dev for <UTS_RELEASE>, where UTS_RELEASE = <ver><LOCALVERSION>.
# Match each group explicitly so future renames don't silently drop one.
LOCAL_TAG="${LOCALVERSION#-}"  # strip leading '-' so "smoothnas-lts" anchors the glob cleanly
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
