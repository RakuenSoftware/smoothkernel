# SmoothKernel

SmoothKernel is the shared Linux kernel build harness for the Smooth* family:
SmoothNAS, SmoothRouter, SmoothHTPC, and SmoothDesktop. It builds one kernel
line, per-architecture canonical configs, and one ordered patch stack into
Debian packages that every flavor installs.

The project exists so the Smooth* products can ship a current, low-latency,
hardware-friendly kernel without maintaining four separate kernel pipelines.
Flavor differences stay in userspace: udev rules, sysctls, tuned profiles,
packages, services, and UI.

## Why You Would Use It

Use SmoothKernel if you want a Debian-based system family with:

- One reproducible kernel pipeline for storage, routing, media, and desktop
  workloads.
- A pristine kernel.org base plus vendored patch lanes, so every downstream
  change is visible in git.
- BORE scheduler support and latency-oriented defaults that still work for
  headless appliance workloads.
- Current hardware enablement for HTPC and desktop use, including controller
  and DRM/game compatibility patches carried in-tree.
- DKMS-friendly headers for OpenZFS, SmoothNAS `smoothfs`, and optional NVIDIA
  modules.
- A documented path for Secure Boot and module signing without storing private
  keys in the repository.

The intended users are Smooth* maintainers, downstream package builders, and
developers working on kernel-adjacent Smooth* components. End users normally
consume SmoothKernel through the Smooth* apt repository rather than building it
by hand.

## Current Scope

SmoothKernel owns:

- `configs/smooth-amd64.config`: the canonical amd64 kernel config.
- `configs/smooth-arm64.config`: the canonical arm64 kernel config.
- `patches/`: ordered, vendored patch lanes for the current kernel line.
- `recipes/build-kernel.sh`: kernel.org tarball -> patches -> config -> Debian
  kernel packages.
- `recipes/build-zfs.sh`: OpenZFS release tarball -> `zfs-dkms` and userspace
  Debian packages.
- `templates/`: DKMS packaging and kernel compatibility templates for
  out-of-tree modules in consuming repos.
- `docs/`: cross-repo technical documentation for the Smooth* base platform.

SmoothKernel does not own per-flavor services or UI, per-product CI pipelines,
private signing keys, or out-of-tree module source code. Those live in the
consuming product repositories.

## Repository Layout

```text
smoothkernel/
|-- README.md
|-- Makefile                     Top-level orchestration
|-- configs/
|   |-- smooth-amd64.config      Current canonical amd64 kernel config
|   |-- smooth-arm64.config      Current canonical arm64 kernel config
|   `-- <kernel-version>/        Archived config snapshots
|-- patches/
|   |-- cachyos-<version>/       Base patch lane applied first
|   |-- nobara-picks/            Narrow HID/controller cherry-picks
|   `-- post-nobara-<version>/   Local carry patches applied last
|-- recipes/
|   |-- build-kernel.sh          Kernel build recipe
|   |-- build-zfs.sh             OpenZFS package recipe
|   `-- stamp-version.sh         Version helper
|-- templates/
|   |-- dkms.conf.in             DKMS package template
|   |-- debian-postinst.in       DKMS register/build/install hook
|   |-- debian-prerm.in          DKMS remove/unload hook
|   `-- compat.h.in              Kernel API compatibility shim template
|-- docs/                        User, maintainer, and platform docs
`-- examples/
    |-- smooth.env               Canonical build.env example
    `-- smoothnas.env            Compatibility alias for older workflows
```

## Quick Start

Builds are driven by `build.env`. The example file tracks the current checked-in
kernel and patch lanes.

```sh
git clone git@github.com:RakuenSoftware/smoothkernel.git
cd smoothkernel
cp examples/smooth.env build.env
$EDITOR build.env              # set versions and patch lane names if overriding defaults
make show
make kernel DEB_ARCH=amd64
make kernel DEB_ARCH=arm64
make zfs DEB_ARCH=amd64
make zfs DEB_ARCH=arm64
```

Artifacts are copied to `out/<arch>/` when using the sample `build.env`.
GitHub releases publish both amd64 and arm64 assets; promote them into the
apt repo's `common` suite per [docs/RELEASE_MODEL.md](docs/RELEASE_MODEL.md).

Typical kernel outputs are versioned `bindeb-pkg` packages such as:

```text
linux-image-<kernel-version>-smoothkernel_*.deb
linux-headers-<kernel-version>-smoothkernel_*.deb
linux-libc-dev_*.deb
```

Typical OpenZFS outputs include `zfs-dkms`, `zfsutils-linux`, and supporting
library packages produced by OpenZFS's Debian packaging.

For host package requirements, resource expectations, output details, and test
install commands, see [docs/BUILDING.md](docs/BUILDING.md).

## Build Model

`make kernel DEB_ARCH=<arch>` runs this flow:

```text
kernel.org tarball
  -> sha256 check against kernel.org sha256sums.asc
  -> apply patches/cachyos-<version>/
  -> apply patches/nobara-picks/
  -> apply patches/post-nobara-<version>/
  -> seed configs/smooth-<arch>.config
  -> make olddefconfig
  -> apply the SmoothKernel profile
  -> make bindeb-pkg
  -> copy .debs to out/<arch>/
```

`make kernel-config-update-all` runs the same setup path for each supported
architecture, then writes refreshed configs back to `configs/smooth-<arch>.config`
and `configs/<kernel-version>/smooth-<arch>.config`.

`make zfs` builds OpenZFS packages from the configured upstream OpenZFS release.
The DKMS package is kernel-version-independent at package build time; it builds
against installed SmoothKernel headers on the target system.

## Patch Policy

Patch order is part of the project contract:

1. `patches/cachyos-<version>/`: base lane, currently the pristine-kernel-safe
   BORE scheduler patch.
2. `patches/nobara-picks/`: narrow HID/controller improvements that apply cleanly
   on the base lane.
3. `patches/post-nobara-<version>/`: local carry patches and rebased follow-ons.

Every patch carried here should have a source, a reason, and a removal condition.
See [docs/PATCHES.md](docs/PATCHES.md) and the README in each patch directory.

## Documentation

Start with [docs/README.md](docs/README.md) for the full documentation map.

Core docs:

- [docs/BUILDING.md](docs/BUILDING.md): local build guide and build environment
  reference.
- [docs/KERNEL.md](docs/KERNEL.md): kernel design, one-kernel rationale, and
  build flow.
- [docs/kernel-config.md](docs/kernel-config.md): canonical `.config`
  invariants and update rules.
- [docs/PATCHES.md](docs/PATCHES.md): patch stack custody, refresh process, and
  review checklist.
- [docs/DKMS.md](docs/DKMS.md): out-of-tree module packaging contract.
- [docs/CI_RELEASES.md](docs/CI_RELEASES.md): GitHub release workflow and
  promotion boundaries.
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md): common build and runtime
  failures.

Platform docs:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): Smooth* platform architecture.
- [docs/APT_REPO.md](docs/APT_REPO.md): apt suite layout, pinning, and promotion.
- [docs/GRAPHICS.md](docs/GRAPHICS.md): Mesa, firmware, and GPU policy.
- [docs/INSTALLERS.md](docs/INSTALLERS.md): shared installer framework.
- [docs/RELEASE_MODEL.md](docs/RELEASE_MODEL.md): cadence, versioning, rollback.
- [docs/signing.md](docs/signing.md): Secure Boot and module-signing model.

Flavor contracts:

- [docs/SMOOTHNAS.md](docs/SMOOTHNAS.md)
- [docs/SMOOTHROUTER.md](docs/SMOOTHROUTER.md)
- [docs/SMOOTHHTPC.md](docs/SMOOTHHTPC.md)
- [docs/SMOOTHDESKTOP.md](docs/SMOOTHDESKTOP.md)

## Maintainer Workflow

For a kernel point release:

1. Pick the target kernel version using the OpenZFS compatibility floor and
   patch-lane availability.
2. Vendor or refresh patch lanes.
3. Run `make kernel-config-update-all`.
4. Review the `.config` diff.
5. Build kernel and ZFS packages for each supported architecture.
6. Install on representative NAS, router, HTPC, and desktop targets.
7. Promote CI-produced artifacts to the Smooth* apt repository.

The detailed runbook is [docs/bumping-kernel.md](docs/bumping-kernel.md).

## Support Boundaries

Current v1 assumptions:

- amd64 and arm64 package builds.
- Debian trixie base.
- One canonical kernel config per Debian architecture, shared by every Smooth* flavor.
- OpenZFS is the gating DKMS consumer for kernel version selection.
- Release-grade Secure Boot support requires signing-capable CI; no private key
  material belongs in this repository.

If a change requires per-flavor kernel variants, it is a platform architecture
change, not a routine config edit. Document the rationale in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[docs/kernel-config.md](docs/kernel-config.md).
