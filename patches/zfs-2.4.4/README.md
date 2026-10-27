# zfs-2.4.4

Carry patches applied to the pristine OpenZFS `2.4.4` release tarball before
`autogen.sh` runs. Applied by `recipes/build-zfs.sh` via `ZFS_PATCHSET`, under
the rules in [`../../docs/PATCHES.md`](../../docs/PATCHES.md).

Current contents:

- `0001-debian-conflict-with-alien-built-packages.patch`

## Why this lane exists

Up to build 71, SmoothKernel built OpenZFS with its alien targets
(`make deb-utils deb-dkms`), which convert RPMs and drop their dependencies:
`zfs-dkms` did not depend on `dkms`, and the libraries declared no shared
library dependencies. It now builds OpenZFS's own Debian packaging
(`make native-deb-utils`), whose packages are named `openzfs-*` and carry
real dependencies.

The native packages already conflict with most old names (`zfs`,
`zfs-initramfs`, `zfs-dracut`, `zfs-test`, `python3-pyzfs`). For the rest
upstream only declares `Replaces`, which lets apt overwrite their files but
leaves the old package installed. On a box that had the alien packages, that
leaves `zfs-dkms` and `openzfs-zfs-dkms` both registering `zfs/2.4.4` with
DKMS. The patch adds `Conflicts` for those names: `zfs-dkms`, `libnvpair3`,
`libuutil3`, `libzfs7`, `libzpool7`, `libzfs7-devel`, `pam-zfs-key`.

## Removal condition

Once no installed system can still carry the alien-built packages, i.e. every
SmoothKernel consumer has moved to the `openzfs-*` packages. Carry the patch
forward on each OpenZFS bump until then (`contrib/debian/control` rarely
changes, so it should apply as is).
