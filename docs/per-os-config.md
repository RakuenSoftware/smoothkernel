# Per-OS config conventions

`smoothkernel` builds the kernel; each Smooth* OS provides the `.config` and out-of-tree modules. This page documents the conventions so adding a new Smooth* OS is mechanical.

## What each OS provides

```
<smooth-os-repo>/
├── kernel/
│   ├── seed.config              The .config to feed `build-kernel.sh`
│   └── build.env                The build env (KERNEL_VERSION, LOCALVERSION, …)
└── src/
    └── <module>/                Out-of-tree module(s), if any
        ├── compat.h             From templates/compat.h.in
        ├── dkms.conf            From templates/dkms.conf.in
        └── debian/
            ├── postinst         From templates/debian-postinst.in
            └── prerm            From templates/debian-prerm.in
```

## Naming conventions

| Field | SmoothNAS | SmoothHTPC | SmoothRouter |
|---|---|---|---|
| `LOCALVERSION` | `-smoothnas-lts` | `-smoothhtpc-lts` | `-smoothrouter-lts` |
| package suffix | `-smoothnas-lts` | `-smoothhtpc-lts` | `-smoothrouter-lts` |
| out-of-tree modules | `smoothfs` | (none yet) | (none yet) |

The `LOCALVERSION` shows up in `uname -r` (e.g. `6.18.22-smoothnas-lts`) and in the .deb filename. It MUST start with a hyphen.

## Seeding the .config

Copy from a known-good box of the same OS:

```sh
ssh appliance 'cat /boot/config-$(uname -r)' > kernel/seed.config
```

For a brand-new OS:
1. Start from the Debian generic `.config` for the target arch.
2. Disable everything that's clearly not needed (e.g., for a router: disable HDMI/audio/GPU; for an HTPC: keep them).
3. Enable everything the OS requires (filesystems, networking, etc.).
4. Run `make olddefconfig` to fill in defaults.
5. Test-boot on real hardware.

## Build env example

`build.env`:

```sh
KERNEL_VERSION=6.18.22
LOCALVERSION=-smoothnas-lts
ZFS_VERSION=2.4.1
CONFIG_SOURCE=/home/virant/dev/SmoothNAS/kernel/seed.config
OUT_DIR=/home/virant/dev/SmoothNAS/build/out
BUILD_THREADS=14
```

## Out-of-tree module skeleton

When adding a new module to a Smooth* OS:

```sh
cd src/mymodule/
cp $SMOOTHKERNEL/templates/compat.h.in compat.h
cp $SMOOTHKERNEL/templates/dkms.conf.in dkms.conf
mkdir -p debian
cp $SMOOTHKERNEL/templates/debian-postinst.in debian/postinst
cp $SMOOTHKERNEL/templates/debian-prerm.in debian/prerm
chmod +x debian/postinst debian/prerm
```

Then substitute the `@MODULE_NAME@`, `@MODULE_PREFIX@`, etc. placeholders. (A future iteration of `smoothkernel` will provide a `make new-module NAME=mymodule PREFIX=mm KERNEL_FLOOR_MAJOR=6 KERNEL_FLOOR_MINOR=18` helper to do the substitution.)
