# Building SmoothKernel

This guide covers local builds of the kernel and OpenZFS packages. It is written
for maintainers and downstream package builders; normal Smooth* users consume
these packages through apt.

## Build Host

The supported build host is Debian or Ubuntu with a modern toolchain. The GitHub
release workflow currently runs on `ubuntu-24.04`, so that is the reference CI
environment.

Install the same dependency set used by CI:

```sh
sudo apt-get update
sudo apt-get install -y \
  build-essential bc bison flex libelf-dev libssl-dev libncurses-dev \
  libdw-dev pahole rsync debhelper kmod fakeroot dpkg-dev cpio xz-utils \
  autoconf automake libtool gawk alien dh-python po-debconf \
  uuid-dev libudev-dev libblkid-dev libtirpc-dev libcurl4-openssl-dev \
  libaio-dev libattr1-dev libffi-dev zlib1g-dev libpam0g-dev \
  python3 python3-dev python3-cffi python3-setuptools python3-packaging \
  python3-distlib parted
```

Expect a kernel build to need many GB of disk and substantial CPU time. Keep
`BUILD_THREADS` below the point where the machine swaps; a slow no-swap build is
better than a highly parallel build that OOMs.

## Build Environment

Copy the example environment and review it before building:

```sh
cp examples/smooth.env build.env
$EDITOR build.env
make show
```

`Makefile` includes `build.env` by default. To use a different file:

```sh
make ENV_FILE=/path/to/my-build.env show
make ENV_FILE=/path/to/my-build.env kernel
```

## Environment Variables

| Variable | Required | Default | Meaning |
|---|---:|---|---|
| `KERNEL_VERSION` | yes | none | Kernel.org stable version to build, for example `6.19.12`. |
| `LOCALVERSION` | yes | none | Kernel release suffix. The checked-in examples use `-smoothkernel`, producing package names such as `linux-image-6.19.12-smoothkernel`. |
| `ZFS_VERSION` | yes for `make zfs` | none | OpenZFS release version, for example `2.4.1`. |
| `CONFIG_SOURCE` | yes for `make kernel` | `configs/smooth-amd64.config` in the example | Seed `.config`. |
| `CACHYOS_PATCHSET` | no | `cachyos-$(KERNEL_VERSION)` | First patch lane under `patches/`. |
| `NOBARA_PATCHSET` | no | `nobara-picks` | Second patch lane under `patches/`. |
| `POST_NOBARA_PATCHSET` | no | `post-nobara-$(KERNEL_VERSION)` | Final patch lane under `patches/`. |
| `OUT_DIR` | no | `$(pwd)/out` | Where finished `.deb` files are copied. |
| `BUILD_THREADS` | no | `$(nproc)` | Parallelism for kernel and ZFS builds. |
| `STRIP_DEBUG_INFO` | no | `1` | Disables BTF/DWARF debug info to reduce build size and package size. |
| `NET_TUNING` | no | `1` | Enables BBR/FQ and related network-path options in the build profile. |
| `SERVER_TUNING` | no | `1` | Enables general appliance/server config toggles. |
| `APPLIANCE_TRIM` | no | `1` | Trims hardware families outside the Smooth* support target while preserving desktop/HTPC basics. |

## Kernel Build

```sh
make kernel
```

The recipe:

1. Downloads `linux-$KERNEL_VERSION.tar.xz` from kernel.org.
2. Downloads kernel.org `sha256sums.asc`.
3. Checks the tarball hash against that file.
4. Extracts a clean source tree under `build/kernel-$KERNEL_VERSION/`.
5. Applies the three ordered patch lanes.
6. Seeds `.config` from `CONFIG_SOURCE`.
7. Runs `make olddefconfig`.
8. Applies the SmoothKernel profile.
9. Runs `make bindeb-pkg`.
10. Copies matching `.deb` files to `OUT_DIR`.

Current hash checking verifies the downloaded tarball against kernel.org's
checksum file. If you need full provenance verification, add GPG verification of
`sha256sums.asc` before treating the build as release-grade.

## Kernel Outputs

`bindeb-pkg` produces versioned Debian package names based on the kernel release
string. With:

```sh
KERNEL_VERSION=6.19.12
LOCALVERSION=-smoothkernel
```

expect names in this shape:

```text
linux-image-6.19.12-smoothkernel_*.deb
linux-headers-6.19.12-smoothkernel_*.deb
linux-libc-dev_*.deb
```

The Smooth* apt layer may add stable meta-package names such as
`linux-image-smoothkernel` that depend on the current versioned package. This
repository builds the versioned packages.

## Refreshing Config

Use this when bumping kernel versions or when a patch lane adds/removes config
symbols:

```sh
make kernel-config-update
```

The target performs the same source/patch/config setup as `make kernel`, then
writes the resulting config to:

```text
configs/smooth-amd64.config
configs/<kernel-version>/smooth-amd64.config
```

Always review the diff. New symbols can silently add unwanted drivers, disable
needed support, or drift from the invariants in [kernel-config.md](kernel-config.md).

## OpenZFS Build

```sh
make zfs
```

The recipe downloads the configured OpenZFS release, runs its packaging build,
and copies resulting `.deb` files to `OUT_DIR`. The `zfs-dkms` package is not
tied to one kernel at package build time; it builds on the target machine
against installed SmoothKernel headers.

Kernel selection is still gated by OpenZFS compatibility. See
[bumping-kernel.md](bumping-kernel.md) for the `Linux-Maximum` rule.

## Test Install

On a disposable test machine:

```sh
scp out/*.deb test-box:/tmp/
ssh test-box 'sudo dpkg -i /tmp/*.deb'
ssh test-box 'sudo reboot'
```

After reboot:

```sh
uname -r
dpkg -l | grep -E 'linux-image|linux-headers|zfs'
dkms status
```

For Secure Boot tests, also check module signers as described in
[signing.md](signing.md).

## Clean Builds

Remove build trees and output packages:

```sh
make clean
```

This removes `build/` and `OUT_DIR`. It does not remove `build.env`.

## Local vs Promotable Artifacts

Local builds are useful for patch bring-up, config review, and smoke testing.
Promotable Smooth* artifacts should come from the release path that has the
required provenance, signing, and validation gates. See
[CI_RELEASES.md](CI_RELEASES.md) and [signing.md](signing.md).
