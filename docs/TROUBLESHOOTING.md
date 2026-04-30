# Troubleshooting

This guide covers common SmoothKernel build and install failures.

## `KERNEL_VERSION required`

`Makefile` did not load a build environment, or the selected env file is missing
`KERNEL_VERSION`.

Check:

```sh
ls build.env
make show
```

Fix:

```sh
cp examples/smooth.env build.env
$EDITOR build.env
```

## `LOCALVERSION must start with '-'`

`LOCALVERSION` becomes part of `uname -r`. It must begin with a dash:

```sh
LOCALVERSION=-smoothkernel
```

Changing this value changes package names and `/lib/modules/<release>`.
Coordinate any change with apt metadata and flavor meta-package dependencies.

## Kernel Download or Checksum Failure

The recipe downloads from kernel.org and checks the tarball against
`sha256sums.asc`.

Causes:

- Typo in `KERNEL_VERSION`.
- Kernel version not present in the expected kernel.org major-version directory.
- Interrupted download.
- Stale partial file in `build/kernel-<version>/`.

Fix:

```sh
rm -rf build/kernel-<version>
make kernel
```

If the version really does not exist on kernel.org, pick a released stable point
version. Do not build `-rc` or `-next` for Smooth* release candidates.

## Patch Does Not Apply

Patch failures usually mean the selected kernel version and patch lane do not
match.

Check:

```sh
make show
ls patches
```

Confirm that these directories exist and target the selected kernel:

```text
patches/cachyos-<KERNEL_VERSION>/
patches/post-nobara-<KERNEL_VERSION>/
```

If you are bumping the kernel, rebase or refresh the patch lanes before trying
to build. See [PATCHES.md](PATCHES.md).

## Config Update Produced a Large Diff

Large `.config` diffs can be valid on major bumps, but review carefully.

Focus on:

- `CONFIG_PREEMPT`
- `CONFIG_HZ`
- `CONFIG_SCHED_BORE`
- module-signing settings
- filesystems
- DRM/audio/input/wifi support
- netfilter/WireGuard support
- debug-info and BTF settings

Then compare against [kernel-config.md](kernel-config.md).

## Build Fails Late in `bindeb-pkg`

Late failures are often package dependency or resource issues.

Check:

- Free disk space.
- RAM and swap.
- Missing host packages from [BUILDING.md](BUILDING.md).
- Whether `BUILD_THREADS` is too high.

Try:

```sh
BUILD_THREADS=4 make kernel
```

If reducing parallelism fixes the failure, keep a lower value in `build.env` for
that host.

## Expected `.deb` Files Not Found

`build-kernel.sh` copies package names matching `KERNEL_VERSION` and
`LOCALVERSION`. If the script reports too few packages, check:

```sh
ls build/kernel-<version>/*.deb
make show
```

Common causes:

- `LOCALVERSION` changed but the output glob was not updated.
- `bindeb-pkg` failed before producing all packages.
- A previous partial build left confusing artifacts.

Start from a clean tree for that kernel:

```sh
rm -rf build/kernel-<version>
make kernel
```

## OpenZFS Build Fails

Most OpenZFS failures mean the selected kernel is outside the OpenZFS release's
supported range.

Check the OpenZFS `META` file for the configured release:

```sh
curl -fsSL https://github.com/openzfs/zfs/raw/zfs-$ZFS_VERSION/META | grep ^Linux
```

If `KERNEL_VERSION` is greater than `Linux-Maximum`, pick an older kernel or a
newer OpenZFS release. SmoothNAS support makes OpenZFS a kernel-selection gate.

## DKMS Module Builds But Does Not Load

Check:

```sh
dkms status
modinfo <module>
dmesg -T | tail -100
```

Likely causes:

- Missing runtime dependency.
- Kernel API mismatch hidden by a weak compat shim.
- Secure Boot rejected an unsigned module.
- Module was built for different headers than the running kernel.

Confirm:

```sh
uname -r
readlink -f /lib/modules/$(uname -r)/build
modinfo -F vermagic <module>
modinfo -F signer <module>
```

## Secure Boot Rejects a Module

Check the signer:

```sh
modinfo -F signer <module>
```

Expected:

- Release-built in-tree modules: Rakuen release signer.
- DKMS-built modules: enrolled host MOK signer.

If signer is empty, the module was not signed. If signer is present but rejected,
the key is not enrolled or has been revoked. Follow the `smooth-secureboot`
enrollment flow in [signing.md](signing.md).

## Boot Fails After Installing a Test Kernel

Use the bootloader menu to select the previous kernel if available.

From a rescue shell or older kernel:

```sh
dpkg -l | grep linux-image
sudo apt-mark hold linux-image-<bad-version>
sudo update-grub
```

For apt-promoted packages, rollback is handled by the apt repository policy in
[RELEASE_MODEL.md](RELEASE_MODEL.md). For local tests, keep the previous working
kernel installed until the new one has passed flavor smoke tests.

## Hardware Regression

Collect:

```sh
uname -a
lspci -nn
lsusb
dmesg -T
```

Then identify whether the regression is:

- Config: driver disabled or changed from built-in to module.
- Patch: behavior changed after a vendored patch.
- Firmware: hardware needs a newer blob.
- Userspace: tuning package or service issue, not kernel.

Do not add a per-flavor kernel fork as the first response. The one-kernel model
requires proving that the issue cannot be solved by config, firmware, runtime
tuning, or a narrow shared patch.
