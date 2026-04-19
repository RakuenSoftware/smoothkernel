# smoothkernel

Kernel build harness and canonical `.config` for the Smooth* family of Debian-based appliance OSes (SmoothNAS, SmoothRouter, SmoothHTPC, SmoothDesktop). Produces **one** `linux-smoothkernel` .deb set installed identically on every flavor.

For the architectural rationale — why one kernel across four flavors, why CachyOS patches, why BORE — see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`docs/KERNEL.md`](docs/KERNEL.md).

## What's here

```
smoothkernel/
├── README.md
├── Makefile                       Top-level orchestration (make kernel / make zfs / etc.)
├── configs/
│   └── smooth-amd64.config        Canonical kernel .config — one for all flavors
├── patches/
│   ├── cachyos-<version>/         Vendored CachyOS patch series per kernel version
│   └── nobara-picks/              Cherry-picked Nobara HID/controller patches
├── recipes/
│   ├── build-kernel.sh            kernel.org tarball → patches → .config → bindeb-pkg
│   ├── build-zfs.sh               OpenZFS source → DKMS .deb recipe
│   └── stamp-version.sh           Compute KDEB_PKGVERSION + LOCALVERSION
├── templates/
│   ├── dkms.conf.in               DKMS config skeleton (MODULE_NAME / KERNEL_FLOOR)
│   ├── debian-postinst.in         Debian postinst hook (DKMS register + autoload)
│   ├── debian-prerm.in            Debian prerm hook (DKMS deregister + unload)
│   └── compat.h.in                Kernel-version shim header skeleton
├── docs/
│   ├── ARCHITECTURE.md            Top-level system architecture for the Smooth* family
│   ├── APT_REPO.md                Suite layout, pinning, promotion
│   ├── KERNEL.md                  linux-smoothkernel design + patch sources
│   ├── kernel-config.md           The canonical .config: invariants and rationale
│   ├── GRAPHICS.md                smooth-gfx / smooth-mesa / linux-firmware-smooth
│   ├── INSTALLERS.md              Shared installer framework
│   ├── RELEASE_MODEL.md           Versioning, cadence, promotion
│   ├── SMOOTHNAS.md               NAS flavor spec (pointer + packaging)
│   ├── SMOOTHROUTER.md            Router flavor spec (greenfield)
│   ├── SMOOTHHTPC.md              HTPC flavor + smoothtv shell spec
│   ├── SMOOTHDESKTOP.md           Desktop flavor + Windows compat spec
│   ├── bumping-kernel.md          Kernel-bump runbook
│   └── signing.md                 Module signing / MOK enrollment (placeholder)
└── examples/
    └── smooth.env                 Sample env file consumed by the recipes
```

## What this owns

- The canonical kernel `.config` (`configs/smooth-amd64.config`). One config for every flavor.
- The CachyOS patch series per kernel version (`patches/cachyos-*`).
- The Nobara HID/controller cherry-picks (`patches/nobara-picks/`).
- The recipes that turn kernel.org source + patches + config into signed `.deb`s.
- The DKMS packaging templates used by out-of-tree modules (`smoothfs`, etc.) in consuming repos.
- The cross-cutting architecture docs for the Smooth* family — colocated here because the kernel is the piece every flavor shares.

## What this does NOT own

- Per-flavor `.config` variants — there aren't any. One canonical config; flavor differences live in userspace (udev/sysctl/tuned) via per-flavor `-tuning` packages.
- Out-of-tree module *sources* — per-OS (e.g. `smoothfs` source lives in SmoothNAS).
- Signed-module key custody — per-deployment, never in git (see [`docs/signing.md`](docs/signing.md)).
- Per-OS CI plumbing — each consuming repo owns its test pipeline.

## Quick start

```sh
git clone git@github.com:RakuenSoftware/smoothkernel.git
cd smoothkernel
cp examples/smooth.env build.env
$EDITOR build.env              # set KERNEL_VERSION, ZFS_VERSION, CACHYOS_PATCH_TAG, etc.
make kernel                    # produces linux-{image,headers,libc-dev,modules}-smoothkernel_*.deb
make zfs                       # produces zfs-dkms_*.deb + libs (against KERNEL_VERSION)
```

The .debs land in `out/`. Promote them into the apt repo's `common` suite per [`docs/RELEASE_MODEL.md`](docs/RELEASE_MODEL.md).

## Bumping the kernel pin

See [`docs/bumping-kernel.md`](docs/bumping-kernel.md). The short version:

1. Edit `build.env` with the new `KERNEL_VERSION` and `CACHYOS_PATCH_TAG`. Selection rule for NAS: "latest stable the OpenZFS release supports".
2. Vendor the matching CachyOS patch series into `patches/cachyos-<version>/`.
3. `make kernel zfs` — verify both build clean against the new kernel.
4. In each consuming repo with an out-of-tree module (`smoothfs`): bump the `compat.h` floor macros, sweep dead pre-floor branches.
5. Deploy to a test box, validate module load + flavor-specific smoke test.
6. Sign + promote to `common` main.

## Why this exists

The single-kernel decision collapses four would-be kernel pipelines into one. The harness exists to make that one pipeline:

- Reproducible — kernel.org source + vendored patches + checked-in config → deterministic .debs
- Low-friction for kernel bumps — `build.env` edit + `make kernel zfs` + compat.h sweep
- Consistent across consumers — every flavor consumes the identical .deb, no per-flavor drift

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the rationale behind the one-kernel model.
