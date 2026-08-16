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
#   DEB_ARCH          Debian architecture being built (default host arch)
#   OUT_DIR           where the .debs land (default $(pwd)/out)
#   BUILD_THREADS     -j N for make (default $(nproc))
#   ZFS_PATCHSET      patch lane applied to the extracted source before
#                     autogen, e.g. zfs-$ZFS_VERSION. Unset means no patches.

set -euo pipefail

: "${ZFS_VERSION:?ZFS_VERSION required (e.g. 2.4.1)}"
ZFS_PATCHSET="${ZFS_PATCHSET:-}"

DEB_ARCH="${DEB_ARCH:-$(dpkg --print-architecture 2>/dev/null || uname -m)}"
OUT_DIR="${OUT_DIR:-$(pwd)/out}"
BUILD_THREADS="${BUILD_THREADS:-$(nproc)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/zfs-$ZFS_VERSION-$DEB_ARCH"
TARBALL="zfs-$ZFS_VERSION.tar.gz"
URL="https://github.com/openzfs/zfs/releases/download/zfs-$ZFS_VERSION/$TARBALL"

mkdir -p "$BUILD_DIR" "$OUT_DIR"
cd "$BUILD_DIR"

if [[ ! -f "$TARBALL" ]]; then
    echo "==> downloading $TARBALL"
    curl -fsSL -O "$URL"
fi
SRC_DIR="zfs-$ZFS_VERSION"
FRESH_EXTRACT=0
if [[ ! -d "$SRC_DIR" ]]; then
    echo "==> extracting"
    tar xzf "$TARBALL"
    FRESH_EXTRACT=1
fi

cd "$SRC_DIR"

# Patches are applied only to a freshly extracted tree. Re-running the recipe
# against an existing build dir must not stack them a second time.
if [[ -n "$ZFS_PATCHSET" && "$FRESH_EXTRACT" -eq 1 ]]; then
    patch_dir="$ROOT/patches/$ZFS_PATCHSET"
    if [[ ! -d "$patch_dir" ]]; then
        echo "ERROR: ZFS_PATCHSET '$ZFS_PATCHSET' not found at $patch_dir" >&2
        exit 1
    fi
    echo "==> applying patches from $patch_dir"
    while IFS= read -r patch; do
        [[ -n "$patch" ]] || continue
        echo "    -> $(basename "$patch")"
        patch -Np1 < "$patch"
    done < <(find "$patch_dir" -maxdepth 1 -type f -name '*.patch' | sort)
fi

echo "==> build arch: DEB_ARCH=$DEB_ARCH"

if [[ ! -f Makefile ]]; then
    echo "==> autogen + configure"
    ./autogen.sh >/dev/null
    ./configure --with-config=user >/dev/null
fi

echo "==> building (-j${BUILD_THREADS})"
date
rpmbuild_cmd="rpmbuild --define '_binary_payload w9.gzdio'"

# OpenZFS' alien-based deb targets share the source tree and fakeroot/rpm
# tooling; run the target groups sequentially while preserving per-target
# parallelism.
make -j"$BUILD_THREADS" RPMBUILD="$rpmbuild_cmd" deb-utils || {
    echo "ERROR: zfs userspace package build failed"; exit 1;
}
make -j"$BUILD_THREADS" RPMBUILD="$rpmbuild_cmd" deb-dkms || {
    echo "ERROR: zfs dkms package build failed"; exit 1;
}
if ! compgen -G "*.deb" >/dev/null; then
    echo "ERROR: zfs build failed"; exit 1;
fi
date

echo "==> collecting .debs into $OUT_DIR"
shopt -s nullglob
moved=()
for f in *.deb; do
    cp -v "$f" "$OUT_DIR/"
    moved+=("$f")
done
echo "==> done. Built ${#moved[@]} .debs in $OUT_DIR"
