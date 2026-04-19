# Installer framework

Each Smooth* flavor ships a bootable ISO. They share a framework (`smooth-installer`) extracted from the existing `SmoothNAS/iso/` work; each flavor contributes only its preseed answers, bootstrap hooks, and meta-package selection.

## Why a shared framework

The four flavors share:

- Debian base (trixie)
- Partitioning tooling (LVM, ZFS-on-root for NAS; ext4/btrfs for others)
- Rakuen apt repo setup (keyring install, sources.list for flavor suite + `common`)
- Network configuration (NetworkManager for HTPC/desktop; systemd-networkd for router)
- Kernel install (`linux-smoothkernel`)
- Branding (GRUB theme, Plymouth splash)

Building four independent installers would duplicate all of that. Extracting it into `smooth-installer` means each flavor ISO is thin: a preseed file, a bootstrap hook script, and a meta-package name.

## Shape

`smooth-installer` repo (new):

```
smooth-installer/
├── README.md
├── Makefile                     make iso FLAVOR=smoothnas
├── common/
│   ├── preseed-base.cfg         shared preseed fragments (apt keys, timezone, locale)
│   ├── post-install.sh          shared post-install: enable non-free-firmware, install keyring,
│   │                            add sources.list for common + flavor suite
│   ├── branding/                GRUB theme, Plymouth theme, wallpapers
│   └── build-iso.sh             debian-installer customization machinery
├── flavors/
│   ├── smoothnas/
│   │   ├── preseed.cfg          overrides common + adds NAS-specific (ZFS-on-root option)
│   │   ├── post-install.sh      runs tierd setup, generate-tls, nginx enable
│   │   └── packages.txt         meta-package(s): smoothnas
│   ├── smoothrouter/
│   │   ├── preseed.cfg          two-NIC config, first-boot wizard hook
│   │   ├── post-install.sh      install smoothrouter-setup wizard trigger
│   │   └── packages.txt         smoothrouter
│   ├── smoothhtpc/
│   │   ├── preseed.cfg          single-disk, single-user autologin
│   │   ├── post-install.sh      enable smoothhtpc-session.service
│   │   └── packages.txt         smoothhtpc
│   └── smoothdesktop/
│       ├── preseed.cfg          desktop-style partitioning (LVM + swap)
│       ├── post-install.sh      enable sddm, preconfigure Flathub
│       └── packages.txt         smoothdesktop
└── .github/workflows/build.yml  CI: build one ISO per flavor on release tag
```

## Build flow

```
make iso FLAVOR=smoothnas
    ↓
pull Debian netinst ISO for trixie
    ↓
overlay common/ (preseed-base, post-install, branding)
    ↓
overlay flavors/<FLAVOR>/ (preseed, post-install, packages.txt)
    ↓
regenerate ISO with modified initrd + menu entries
    ↓
output: smoothnas-<version>-amd64.iso
```

The actual machinery (xorriso, initramfs repacking, bootloader rewrite) is what's already in `SmoothNAS/iso/`. This doc is what it becomes after extraction.

## Extraction from SmoothNAS

Migration is mechanical:

1. Create the `smooth-installer` repo with the skeleton above.
2. Move shared scripts/templates from `SmoothNAS/iso/` into `smooth-installer/common/`.
3. Move SmoothNAS-specific bits into `smooth-installer/flavors/smoothnas/`.
4. Replace `SmoothNAS/iso/` contents with a Makefile target that calls `smooth-installer`.
5. Document the break in `SmoothNAS/docs/OPERATIONS.md`.

Until this lands, the existing `SmoothNAS/iso/` continues to work and other flavors just don't have ISOs yet. Extraction isn't blocking for any flavor's development — layer-onto-Debian via apt works for all four from day one.

## Per-flavor ISO concerns

### SmoothNAS

- Optional ZFS-on-root. Needs the installer to load ZFS modules during install (they come from `zfs-dkms` built against the installer kernel, or precompiled for the installer environment — decision deferred).
- Multi-disk mgmt during install is out of scope — non-OS disks stay untouched, managed from the web UI post-install.
- Default user setup: one admin user, web UI login is separate credential.

### SmoothRouter

- Two-NIC assumption (WAN + LAN). Installer must *not* autoconfigure DHCP on the WAN — the default state is "everything denied until first-boot wizard completes."
- First-boot `smoothrouter-setup` wizard is a CLI that runs at first login on the console. Only after wizard completes does the web UI bind to the LAN interface.
- If there's only one NIC (VM or single-interface test), wizard offers a "router-on-a-stick" single-interface mode.

### SmoothHTPC

- Single-disk common case (NUC, mini-PC). Full-disk encryption optional.
- Autologin to a locked-down user account whose session is the `smoothhtpc-session.service` that runs the wlroots compositor + `smoothtv`.
- HDMI-CEC and IR receiver detection at first boot.
- Debian `non-free-firmware` enabled by default; Debian `non-free` stays opt-in for NVIDIA systems.

### SmoothDesktop

- Regular desktop partitioning: LVM on root with encrypted swap (LUKS optional at install).
- User creation triggers Plasma first-run wizard on first login.
- Flathub preconfigured; no apps auto-installed beyond what the `smoothdesktop` meta pulls.
- Before `apt` installs `smoothdesktop`, the installer enables Debian `contrib non-free non-free-firmware`, enables `i386`, and adds the WineHQ source/key so `steam-installer` and `winehq-stable` are resolvable during the initial install.

## Update model (post-install)

ISOs are for initial install. After that, updates come through apt:

```
apt update
apt full-upgrade
```

The installer is responsible only for:

- Correct Debian base with `non-free-firmware` enabled
- Rakuen apt keyring installed
- `/etc/apt/sources.list.d/smooth.list` with `common` + flavor suite
- Any flavor-specific Debian components or third-party apt sources required before the flavor meta-package can be resolved
- The flavor meta-package installed (which pulls kernel, tuning, daemons, UI, etc.)

After first boot, the system is an ordinary Debian box with our apt repo enabled. All subsequent lifecycle is standard Debian package management.

Layering a flavor onto an existing Debian install follows the same rule: run the flavor bootstrap helper first, then install the flavor meta-package. The bootstrap helper exists to perform any pre-`apt install <flavor-meta>` work that cannot be deferred to package `postinst`.

## Non-goals for v1

- **In-ISO live mode.** Not building a "try before install" live CD for any flavor. Cost/value doesn't work for appliance flavors; desktop could justify it later.
- **Calamares graphical installer.** Debian's `debian-installer` via preseed is enough. Calamares for smoothdesktop is a possible later addition if non-technical users become a target.
- **Network install beyond netinst.** No PXE/netboot story at v1.

## Open questions

- **ZFS in the SmoothNAS installer environment.** Simplest: precompile `zfs.ko` against the installer kernel and ship as a squashfs overlay. Painful: rebuild every Debian installer kernel bump. Defer decision to when we actually stand up the smooth-installer repo.
- **Signing ISOs.** We sign the apt repo; should we also sign ISOs (GPG-detached-sig alongside the ISO)? Probably yes, same key. Same infrastructure as the apt repo.
