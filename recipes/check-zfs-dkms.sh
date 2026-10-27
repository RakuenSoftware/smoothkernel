#!/usr/bin/env bash
# Rebuild the generated DKMS package against this build's kernel. No install/load.
set -euo pipefail
: "${KERNEL_VERSION:?KERNEL_VERSION required}"
: "${ZFS_VERSION:?ZFS_VERSION required}"
DEB_ARCH="${DEB_ARCH:-amd64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
BUILD_THREADS="${BUILD_THREADS:-$(nproc)}"
case "$DEB_ARCH" in
    amd64) kernel_arch=x86; native_arch=x86_64 ;;
    arm64) kernel_arch=arm64; native_arch=aarch64 ;;
    *) echo "Unsupported DEB_ARCH: $DEB_ARCH" >&2; exit 1 ;;
esac
[[ "$(uname -m)" == "$native_arch" ]] || {
    echo "DKMS validation requires a native $DEB_ARCH builder" >&2; exit 1;
}
kernel_src="$ROOT/build/kernel-$KERNEL_VERSION-$DEB_ARCH/linux-$KERNEL_VERSION"
[[ -s "$kernel_src/Module.symvers" ]] || {
    echo "Build the full kernel before checking ZFS DKMS" >&2; exit 1;
}
kernel_release=$(env -u LOCALVERSION -u MAKEFLAGS make -s -C "$kernel_src" ARCH="$kernel_arch" kernelrelease)
shopt -s nullglob
packages=("$OUT_DIR"/openzfs-zfs-dkms_*.deb)
[[ ${#packages[@]} -eq 1 ]] || {
    echo "Expected exactly one openzfs-zfs-dkms package in $OUT_DIR" >&2; exit 1;
}
check_dir=$(mktemp -d "$ROOT/build/zfs-dkms-check-$DEB_ARCH.XXXXXX")
dpkg-deb -x "${packages[0]}" "$check_dir/package"
source_dir="$check_dir/package/usr/src/zfs-$ZFS_VERSION"
[[ -f "$source_dir/dkms.conf" ]] || {
    echo "Packaged ZFS source or dkms.conf missing: $source_dir" >&2; exit 1;
}
if grep -q -- '--enable-linux-experimental' "$source_dir/dkms.conf"; then
    echo "DKMS source must support the kernel without experimental bypass" >&2; exit 1
fi
mkdir -p "$check_dir/dkms" "$check_dir/modules"
common=(--sourcetree "$check_dir/package/usr/src" --dkmstree "$check_dir/dkms" --installtree "$check_dir/modules")
echo "==> rebuilding packaged ZFS $ZFS_VERSION for $kernel_release"
dkms add -m zfs -v "$ZFS_VERSION" "${common[@]}"
if ! dkms build -m zfs -v "$ZFS_VERSION" -k "$kernel_release" -a "$native_arch" \
    --kernelsourcedir "$kernel_src" -j "$BUILD_THREADS" "${common[@]}"; then
    find "$check_dir/dkms" -name make.log -exec cat {} \;
    exit 1
fi
for name in zfs spl; do
    module="$check_dir/dkms/zfs/$ZFS_VERSION/$kernel_release/$native_arch/module/$name.ko"
    [[ -f "$module" ]] || { echo "Missing built module: $module" >&2; exit 1; }
    vermagic=$(modinfo -F vermagic "$module")
    [[ "$vermagic" == "$kernel_release "* ]] || {
        echo "Wrong $name vermagic: $vermagic" >&2; exit 1;
    }
    echo "==> $name.ko: $vermagic"
done
echo "==> packaged ZFS DKMS build passed; artifacts: $check_dir"
