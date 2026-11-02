#!/usr/bin/env bash
# Install this build's packages in a Debian 13 container in the order that
# left a SmoothNAS box without ZFS: OpenZFS DKMS first, then linux-image on
# its own (its DKMS hook skips a kernel without headers), then the headers.
# The headers' postinst must rerun the DKMS hook and build ZFS.
#
# Needs docker. The negative control (no zfs.ko after the image alone) makes
# sure the last check can't pass because something else built the module.
set -euo pipefail
DEB_ARCH="${DEB_ARCH:-amd64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
IMAGE="${CHECK_IMAGE:-debian:trixie}"

shopt -s nullglob
images=("$OUT_DIR"/linux-image-*-smoothkernel_*_"$DEB_ARCH".deb)
headers=("$OUT_DIR"/linux-headers-*-smoothkernel_*_"$DEB_ARCH".deb)
zfs=("$OUT_DIR"/openzfs-zfs-dkms_*.deb)
[[ ${#images[@]} -eq 1 && ${#headers[@]} -eq 1 && ${#zfs[@]} -eq 1 ]] || {
    echo "Expected one linux-image, one linux-headers and one openzfs-zfs-dkms .deb in $OUT_DIR" >&2
    ls -la "$OUT_DIR" >&2
    exit 1
}
krel="$(dpkg-deb -f "${headers[0]}" Package)"
krel="${krel#linux-headers-}"

docker run --rm -v "$OUT_DIR:/out:ro" -e KREL="$krel" \
    -e IMG="/out/$(basename "${images[0]}")" \
    -e HDR="/out/$(basename "${headers[0]}")" \
    -e ZFS="/out/$(basename "${zfs[0]}")" \
    "$IMAGE" bash -euo pipefail -c '
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
zfs_installed() { dkms status -k "$KREL" | grep -Eq "^zfs/.*: installed"; }

echo "==> OpenZFS DKMS, before any SmoothKernel"
apt-get install -y -qq "$ZFS" >/dev/null

echo "==> linux-image $KREL without its headers"
apt-get install -y -qq --no-install-recommends "$IMG" >/dev/null
if zfs_installed || [ -n "$(find "/lib/modules/$KREL" -name "zfs.ko*")" ]; then
    echo "ZFS was built before the headers were installed; this check proves nothing" >&2
    exit 1
fi

echo "==> linux-headers $KREL"
apt-get install -y -qq "$HDR" >/dev/null
if ! zfs_installed; then
    dkms status >&2
    find /var/lib/dkms -name make.log -exec tail -n 40 {} \; >&2
    echo "configuring linux-headers-$KREL did not build ZFS for it" >&2
    exit 1
fi
vermagic="$(modinfo -k "$KREL" -F vermagic zfs)"
case "$vermagic" in
    "$KREL "*) echo "==> zfs.ko built for $KREL: $vermagic" ;;
    *) echo "zfs.ko has the wrong vermagic: $vermagic" >&2; exit 1 ;;
esac
'
