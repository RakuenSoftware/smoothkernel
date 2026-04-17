# smoothkernel

Shared kernel-build harness for the Smooth* family of Debian-based appliance OSes (SmoothNAS, SmoothHTPC, SmoothRouter, …). Owns the recipes, packaging templates, and conventions every Smooth* OS reuses; each consumer provides its own `.config`, `LOCALVERSION`, and out-of-tree module set.

## What's here

```
smoothkernel/
├── README.md
├── Makefile                       Top-level orchestration (make kernel / make zfs / etc.)
├── recipes/
│   ├── build-kernel.sh            kernel.org tarball → bindeb-pkg recipe
│   ├── build-zfs.sh               OpenZFS source → DKMS .deb recipe
│   └── stamp-version.sh           Compute KDEB_PKGVERSION + LOCALVERSION
├── templates/
│   ├── dkms.conf.in               DKMS config skeleton (MODULE_NAME / KERNEL_FLOOR)
│   ├── debian-postinst.in         Debian postinst hook (DKMS register + autoload)
│   ├── debian-prerm.in            Debian prerm hook (DKMS deregister + unload)
│   └── compat.h.in                Kernel-version shim header skeleton
├── docs/
│   ├── bumping-kernel.md          The "how do I move from N.X to N.Y" runbook
│   ├── per-os-config.md           How each Smooth* OS plugs its .config in
│   └── signing.md                 Module signing / MOK enrollment (placeholder)
└── examples/
    └── smoothnas.env              Sample env file consumed by the recipes
```

## What this does NOT own

- The kernel `.config` itself — per-OS, sized to that OS's hardware/feature set
- Out-of-tree module sources — per-OS (smoothfs is NAS-only; HTPC/Router will have their own)
- The signed-module key custody — per-deployment, never checked into git
- The test-server/CI plumbing — per-OS

## Quick start

```sh
git clone git@github.com:RakuenSoftware/smoothkernel.git
cd smoothkernel
cp examples/smoothnas.env build.env
$EDITOR build.env                 # set KERNEL_VERSION, ZFS_VERSION, LOCALVERSION, etc.
make kernel                       # produces linux-{image,headers,libc-dev}_*.deb
make zfs                          # produces zfs-dkms_*.deb + libs (against KERNEL_VERSION)
```

The .debs land in `out/`. Ship them to the appliance and `dpkg -i`.

## Bumping the kernel pin

See [`docs/bumping-kernel.md`](docs/bumping-kernel.md). The short version:

1. Edit `build.env` with the new `KERNEL_VERSION`. The selection rule is "latest stable that the must-have DKMS set (typically OpenZFS) supports".
2. `make kernel zfs` — verify both build clean.
3. In each consuming Smooth* OS: bump the `compat.h` floor macros, sweep dead pre-floor branches, add new-API adoption blocks where wanted.
4. Deploy the new .debs to a test box, validate the OS-specific module load + smoke test.
5. Sign + ship.

## Why this exists

Every Smooth* OS will hit:
- The same kernel-build dance (kernel.org → `.config` → `bindeb-pkg`)
- The same OpenZFS-from-source dance (Debian's `zfs-dkms` lags upstream by months)
- The same Debian DKMS packaging shape
- The same kernel-version-shim problem in any out-of-tree module

Owning these once means a kernel bump is a coordinated edit across Smooth* OSes rather than three independent reinventions.
