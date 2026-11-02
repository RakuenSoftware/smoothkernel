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
zfs_installed() { dkms status -k "$KREL" | grep -Eq "^zfs/.*: installed"; }

# Show why a step failed: its apt/dpkg output, DKMS state and build logs.
diagnose() {
    echo "---- output of: $1" >&2
    cat /tmp/step.log >&2 || true
    if command -v dkms >/dev/null; then
        echo "---- dkms status" >&2
        dkms status >&2 || true
    fi
    for log in /var/lib/dkms/*/*/build/make.log /var/lib/dkms/*/*/*/*/log/make.log; do
        [ -f "$log" ] || continue
        echo "---- $log (last 80 lines)" >&2
        tail -n 80 "$log" >&2
    done
}
# Run a step quietly; on failure print everything above, then fail.
step() {
    local what="$1"; shift
    echo "==> $what"
    if ! "$@" > /tmp/step.log 2>&1; then
        diagnose "$what"
        echo "FAILED: $what" >&2
        exit 1
    fi
}

step "apt-get update" apt-get update
step "OpenZFS DKMS, before any SmoothKernel" apt-get install -y "$ZFS"
step "linux-image $KREL without its headers" apt-get install -y --no-install-recommends "$IMG"
if zfs_installed || [ -n "$(find "/lib/modules/$KREL" -name "zfs.ko*")" ]; then
    echo "ZFS was built before the headers were installed; this check proves nothing" >&2
    exit 1
fi

# The headers must bring the libraries their host tools need (objtool links
# libelf), so the container stays minimal on purpose.
step "linux-headers $KREL" apt-get install -y "$HDR"
if ! zfs_installed; then
    : > /tmp/step.log
    diagnose "linux-headers $KREL"
    echo "configuring linux-headers-$KREL did not build ZFS for it" >&2
    exit 1
fi
vermagic="$(modinfo -k "$KREL" -F vermagic zfs)"
case "$vermagic" in
    "$KREL "*) echo "==> zfs.ko built for $KREL: $vermagic" ;;
    *) echo "zfs.ko has the wrong vermagic: $vermagic" >&2; exit 1 ;;
esac
'
