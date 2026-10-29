#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# build-zfs.sh — fetch an OpenZFS source release and produce
# openzfs-zfs-dkms + userspace .deb files with OpenZFS' own Debian
# packaging (contrib/debian), so every package declares its real
# dependencies. The DKMS source package is kernel-version-independent;
# it rebuilds against whatever kernel headers are installed on the
# target appliance via the standard DKMS hook.
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
#   BUILD_NUMBER      default recipes/build-number.sh (commit count of HEAD)
#
# The build number is the package revision (openzfs-zfsutils_2.4.4-<N>),
# as for the kernel, so every build's packages have their own version and
# a patch change reaches systems as an upgrade. The DKMS module version
# stays ZFS_VERSION (the upstream part of the package version).

set -euo pipefail

: "${ZFS_VERSION:?ZFS_VERSION required (e.g. 2.4.1)}"
ZFS_PATCHSET="${ZFS_PATCHSET:-}"

DEB_ARCH="${DEB_ARCH:-$(dpkg --print-architecture 2>/dev/null || uname -m)}"
OUT_DIR="${OUT_DIR:-$(pwd)/out}"
BUILD_THREADS="${BUILD_THREADS:-$(nproc)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_NUMBER="$("$ROOT/recipes/build-number.sh")"
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

# configure reads the package revision from META. A reused tree configured
# for another build number has to be configured again.
# .nogitrelease: otherwise configure asks git (this repo, as the tree sits
# inside it) for a release before falling back to META.
touch .nogitrelease
if ! grep -qx "Release:[[:space:]]*${BUILD_NUMBER}" META; then
    sed -i "s/^Release:.*/Release:       ${BUILD_NUMBER}/" META
    rm -f Makefile
fi

if [[ ! -f Makefile ]]; then
    echo "==> autogen + configure"
    ./autogen.sh >/dev/null
    ./configure --with-config=user >/dev/null
fi

# The Debian version comes from the changelog configure generates, which
# upstream fixes at <version>-1.
pkg_version="${ZFS_VERSION}-${BUILD_NUMBER}"
sed -i -E "1s/^(openzfs-linux \([^-)]+)-[^)]*\)/\1-${BUILD_NUMBER})/" contrib/debian/changelog
got="$(dpkg-parsechangelog -l contrib/debian/changelog -S Version)"
[[ "$got" == "$pkg_version" ]] || {
    echo "ERROR: contrib/debian/changelog has version $got, expected $pkg_version" >&2; exit 1;
}

echo "==> building (-j${BUILD_THREADS})"
date
# native-deb-utils copies contrib/debian to debian/ only if debian/ does not
# exist, and dpkg-buildpackage leaves the packages in the parent directory:
# clear both so a rerun cannot pick up a previous build.
rm -rf debian ../*.deb
# Userspace + DKMS source; not native-deb-kmod, which would build modules
# for the build host's kernel. dpkg-buildpackage checks Build-Depends first
# and names whatever is missing.
DEB_BUILD_OPTIONS="nocheck parallel=${BUILD_THREADS}" make native-deb-utils || {
    echo "ERROR: zfs package build failed"; exit 1;
}
date

echo "==> collecting .debs into $OUT_DIR"
shopt -s nullglob
moved=()
for f in ../*.deb; do
    cp -v "$f" "$OUT_DIR/"
    moved+=("$f")
done
[[ ${#moved[@]} -gt 0 ]] || { echo "ERROR: zfs build produced no .debs"; exit 1; }
echo "==> done. Built ${#moved[@]} .debs in $OUT_DIR"
