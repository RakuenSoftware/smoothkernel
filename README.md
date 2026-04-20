# smoothkernel

Kernel build harness and architecture docs for the Smooth* family of Debian-based appliance OSes (SmoothNAS, SmoothRouter, SmoothHTPC, SmoothDesktop).

The current harness builds from a caller-supplied seed `.config` via `CONFIG_SOURCE`. The one-kernel documentation in this repo describes the intended shared-kernel model, but the committed `configs/` tree and vendored patch flow described in some docs are not wired into this checkout yet.

For the architectural rationale — why one kernel across four flavors, why CachyOS patches, why BORE — see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`docs/KERNEL.md`](docs/KERNEL.md).

## What's here

```
smoothkernel/
├── README.md
├── Makefile                       Top-level orchestration (make kernel / make zfs / etc.)
├── recipes/
│   ├── build-kernel.sh            kernel.org tarball → seed .config → bindeb-pkg
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
│   └── signing.md                 Secure Boot + module-signing model
└── examples/
    ├── smooth.env                 Canonical sample env file consumed by the recipes
    └── smoothnas.env              Compatibility alias for older local workflows
```

## What this owns

- The recipes that turn kernel.org source + a supplied seed config into Debian `.deb`s.
- The DKMS packaging templates used by out-of-tree modules (`smoothfs`, etc.) in consuming repos.
- The cross-cutting architecture docs for the Smooth* family.

## What this does NOT own

- Per-flavor `.config` variants — there aren't any. One canonical config; flavor differences live in userspace (udev/sysctl/tuned) via per-flavor `-tuning` packages.
- Out-of-tree module *sources* — per-OS (e.g. `smoothfs` source lives in SmoothNAS).
- Module-signing trust model and key custody policy — defined in [`docs/signing.md`](docs/signing.md); no private keys live in git.
- Per-OS CI plumbing — each consuming repo owns its test pipeline.

## Quick start

```sh
git clone git@github.com:RakuenSoftware/smoothkernel.git
cd smoothkernel
cp examples/smooth.env build.env
$EDITOR build.env              # set KERNEL_VERSION, ZFS_VERSION, CONFIG_SOURCE, etc.
make kernel                    # produces bindeb-pkg kernel artifacts (image, headers, libc-dev)
make zfs                       # produces zfs-dkms_*.deb + libs (against KERNEL_VERSION)
```

The .debs land in `out/`. Promote them into the apt repo's `common` suite per [`docs/RELEASE_MODEL.md`](docs/RELEASE_MODEL.md).

If you are following the one-kernel design docs: patch vendoring and a checked-in canonical `configs/` tree are still target-state work. Today's harness does not consume `CACHYOS_PATCH_TAG` or `NOBARA_PATCH_REF`.

## Bumping the kernel pin

See [`docs/bumping-kernel.md`](docs/bumping-kernel.md). The short version:

1. Edit `build.env` with the new `KERNEL_VERSION`, `ZFS_VERSION`, and `CONFIG_SOURCE`. Selection rule for NAS: "latest stable the OpenZFS release supports".
2. `make kernel zfs` — verify both build clean against the new kernel.
3. In each consuming repo with an out-of-tree module (`smoothfs`): bump the `compat.h` floor macros, sweep dead pre-floor branches.
4. Deploy to a test box, validate module load + flavor-specific smoke test.
5. Sign + promote to `common` main.

## Why this exists

The single-kernel decision collapses four would-be kernel pipelines into one. The harness exists to make that one pipeline:

- Reproducible — kernel.org source + vendored patches + checked-in config → deterministic .debs
- Low-friction for kernel bumps — `build.env` edit + `make kernel zfs` + compat.h sweep
- Consistent across consumers — every flavor consumes the identical .deb, no per-flavor drift

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the rationale behind the one-kernel model.
