#!/usr/bin/env bash
# build-kernel.sh — fetch a kernel.org tarball and produce
# linux-image / linux-headers / linux-libc-dev .deb files via the
# in-tree `make bindeb-pkg` target.
#
# Required env (set in build.env or the calling shell):
#   KERNEL_VERSION    e.g. 6.18.22
#   LOCALVERSION      e.g. -smoothnas-lts (must start with -)
#   CONFIG_SOURCE     path to seed .config (per-OS; usually copied from
#                     the running kernel of a known-good box)
#
# Optional env:
#   OUT_DIR           where the .debs land (default $(pwd)/out)
#   BUILD_THREADS     -j N for make (default $(nproc))
#   STRIP_DEBUG_INFO  if "1" (default), strip BTF/DWARF to slim the
#                     image and speed up packaging

set -euo pipefail

: "${KERNEL_VERSION:?KERNEL_VERSION required (e.g. 6.18.22)}"
: "${LOCALVERSION:?LOCALVERSION required (e.g. -smoothnas-lts)}"
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
yes "" | make olddefconfig >/dev/null

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
    scripts/config --enable TCP_CONG_BBR \
                   --set-str DEFAULT_TCP_CONG "bbr" \
                   --enable NET_SCH_FQ \
                   --enable NET_RX_BUSY_POLL \
                   --enable TCP_MD5SIG
fi

scripts/config --set-str LOCALVERSION "$LOCALVERSION"
yes "" | make olddefconfig >/dev/null

echo "==> building (-j${BUILD_THREADS})"
date
make -j"$BUILD_THREADS" bindeb-pkg LOCALVERSION="$LOCALVERSION"
date

echo "==> collecting .debs into $OUT_DIR"
shopt -s nullglob
moved=()
for f in ../linux-*_*"$LOCALVERSION"*"$KERNEL_VERSION"*_*.deb \
         ../linux-libc-dev_${KERNEL_VERSION}*.deb; do
    cp -v "$f" "$OUT_DIR/"
    moved+=("$f")
done
echo "==> done. Built ${#moved[@]} .debs in $OUT_DIR"
