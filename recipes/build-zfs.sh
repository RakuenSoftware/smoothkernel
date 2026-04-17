#!/usr/bin/env bash
# build-zfs.sh — fetch an OpenZFS source release and produce zfs-dkms
# + userspace .deb files. DKMS source package is kernel-version-
# independent; it rebuilds against whatever kernel headers are
# installed on the target appliance via the standard DKMS hook.
#
# Required env:
#   ZFS_VERSION       e.g. 2.4.1
#
# Optional env:
#   OUT_DIR           where the .debs land (default $(pwd)/out)
#   BUILD_THREADS     -j N for make (default $(nproc))

set -euo pipefail

: "${ZFS_VERSION:?ZFS_VERSION required (e.g. 2.4.1)}"

OUT_DIR="${OUT_DIR:-$(pwd)/out}"
BUILD_THREADS="${BUILD_THREADS:-$(nproc)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/zfs-$ZFS_VERSION"
TARBALL="zfs-$ZFS_VERSION.tar.gz"
URL="https://github.com/openzfs/zfs/releases/download/zfs-$ZFS_VERSION/$TARBALL"

mkdir -p "$BUILD_DIR" "$OUT_DIR"
cd "$BUILD_DIR"

if [[ ! -f "$TARBALL" ]]; then
    echo "==> downloading $TARBALL"
    curl -fsSL -O "$URL"
fi
SRC_DIR="zfs-$ZFS_VERSION"
if [[ ! -d "$SRC_DIR" ]]; then
    echo "==> extracting"
    tar xzf "$TARBALL"
fi

cd "$SRC_DIR"

if [[ ! -f Makefile ]]; then
    echo "==> autogen + configure"
    ./autogen.sh >/dev/null
    ./configure --with-config=user >/dev/null
fi

echo "==> building (-j${BUILD_THREADS})"
date
make -j"$BUILD_THREADS" deb-utils deb-dkms 2>&1 | tail -5 || {
    echo "ERROR: zfs build failed"; exit 1;
}
date

echo "==> collecting .debs into $OUT_DIR"
shopt -s nullglob
moved=()
for f in *.deb; do
    cp -v "$f" "$OUT_DIR/"
    moved+=("$f")
done
echo "==> done. Built ${#moved[@]} .debs in $OUT_DIR"
