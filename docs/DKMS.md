# DKMS Consumer Contract

SmoothKernel provides the headers and templates that out-of-tree modules use to
build against the shared kernel. Module source code lives in consuming repos,
not here.

Current or expected consumers:

- OpenZFS through `zfs-dkms`.
- SmoothNAS `smoothfs`.
- Optional NVIDIA modules from Debian's `nvidia-driver-*` packages.

## Package Shape

A Smooth* out-of-tree module should package as DKMS unless there is a strong
reason to ship a prebuilt module. DKMS keeps the module coupled to the target
kernel headers and avoids one binary package per kernel version.

The minimum package contents are:

```text
/usr/src/<module>-<version>/
  dkms.conf
  Makefile
  source files
debian/postinst
debian/prerm
```

Use the templates in this repository:

- [../templates/dkms.conf.in](../templates/dkms.conf.in)
- [../templates/debian-postinst.in](../templates/debian-postinst.in)
- [../templates/debian-prerm.in](../templates/debian-prerm.in)
- [../templates/compat.h.in](../templates/compat.h.in)

## `dkms.conf`

`BUILD_EXCLUSIVE_KERNEL` is required. It prevents a module from trying to build
against a kernel below its supported API floor.

Example floor for 6.18+:

```text
^(6\.(1[8-9]|[2-9][0-9])|[7-9]\.).*
```

Keep this regex in lockstep with the module's `compat.h` floor.

## Maintainer Scripts

The `postinst` template:

1. Checks that `dkms` exists.
2. Adds the module/version.
3. Builds it.
4. Installs it.
5. Attempts `modprobe` if the module is not already loaded.

The `prerm` template:

1. Refuses to unload a filesystem module while matching mounts are active.
2. Attempts module unload for removable modules.
3. Removes the DKMS module/version.

Do not hide DKMS build failures in production packages. A module package that
installs but cannot build leaves the appliance in a partially functional state.

## Compatibility Header Pattern

Every module should centralize kernel API drift in one header derived from
[../templates/compat.h.in](../templates/compat.h.in).

Rules:

- Other `.c` files should not contain scattered `#if LINUX_VERSION_CODE` blocks.
- Call sites should use unconditional `<prefix>_compat_*()` helpers.
- Bumping the kernel floor means updating the floor macros, deleting dead
  pre-floor branches, and updating `BUILD_EXCLUSIVE_KERNEL`.

This keeps kernel bumps reviewable. The maintainer should be able to audit API
drift by reading one compatibility header, not searching every source file.

## Kernel Headers

Consumers build against the installed SmoothKernel headers package. With the
current localversion convention, the versioned header package has a name like:

```text
linux-headers-<kernel-version>-smoothkernel
```

Flavor meta packages may expose stable dependencies, but DKMS ultimately uses:

```text
/lib/modules/$(uname -r)/build
```

## Secure Boot

DKMS-built modules are signed on the target machine by the
`smooth-secureboot` flow described in [signing.md](signing.md).

Package scripts should not generate their own unrelated signing keys. They
should rely on the shared DKMS signing hooks so ZFS, `smoothfs`, and optional
NVIDIA modules all follow the same trust model.

## Smoke Test

For every DKMS consumer:

```sh
dkms status
modinfo <module>
sudo modprobe <module>
lsmod | grep '^<module>'
```

For filesystem modules, also mount and unmount a real test filesystem. For
Secure Boot validation:

```sh
modinfo -F signer <module>
```

The signer should be the enrolled host MOK for DKMS-built modules.

## Kernel Bump Duties

When SmoothKernel moves to a new kernel line:

1. Build and install the new headers.
2. Rebuild every DKMS consumer.
3. Update `compat.h` floors only after deciding the old floor is no longer
   supported.
4. Delete dead compatibility branches.
5. Update `BUILD_EXCLUSIVE_KERNEL`.
6. Run the module's real workload smoke test.

For SmoothNAS, this means ZFS pool import/export and `smoothfs` mount behavior,
not just a successful compile.
