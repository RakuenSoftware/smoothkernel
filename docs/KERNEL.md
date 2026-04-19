# linux-smoothkernel

The kernel for every Smooth* flavor. One source tree, one `.config`, one set of `.deb` outputs installed identically on SmoothNAS, SmoothRouter, SmoothHTPC, and SmoothDesktop.

This doc is the design rationale and maintenance runbook. For the mechanical build steps see [`bumping-kernel.md`](bumping-kernel.md). For the current canonical `.config` shape see [`kernel-config.md`](kernel-config.md).

## What it is

`linux-smoothkernel` ships four Debian binary packages from one source:

- `linux-image-smoothkernel` — the bzImage + builtin modules
- `linux-headers-smoothkernel` — headers for DKMS (zfs, nvidia, smoothfs, v4l-out-of-tree)
- `linux-modules-smoothkernel` — loadable modules
- `linux-libc-dev-smoothkernel` — userspace headers

All four flavors install all four packages unchanged. `LOCALVERSION=-smooth` — the kernel reports as `x.y.z-smooth` in `uname -r`, with no per-flavor suffix.

## Why one kernel

The intuition that NAS, router, HTPC, and desktop "need different kernels" is mostly false under BORE + modern tunables. The real deltas between those workloads are:

| Delta | Kernel concern? | Where it lives |
|---|---|---|
| I/O scheduler (BFQ vs mq-deadline vs none) | No — runtime per-block-device | udev rules in flavor `-tuning` package |
| VM tuning (dirty_ratio, swappiness) | No — runtime sysctl | sysctl fragment in flavor `-tuning` package |
| Network tuning (buffers, conntrack, forwarding) | No — runtime sysctl | sysctl fragment in flavor `-tuning` package |
| CPU governor (powersave vs performance vs schedutil) | No — runtime via tuned | tuned profile in flavor `-tuning` package |
| Preemption model | Yes — compile-time | `CONFIG_PREEMPT=y`, one choice for all |
| Scheduler (BORE vs CFS vs sched-ext default) | Yes — patch + compile-time | BORE patched in, selected as default |
| Timer frequency | Yes — compile-time | `CONFIG_HZ=1000` |

The compile-time deltas are settings where *one value works for everyone* once you pick the right scheduler. BORE makes `PREEMPT=y` cheap enough on servers that it's not a real tradeoff, and `HZ=1000` has negligible server impact on modern hardware. So: one binary.

The payoff: one rebase per upstream bump instead of four, one .config to maintain, one support surface to reproduce bugs against.

## Patch sources

### Primary: CachyOS

`github.com/CachyOS/kernel-patches` maintains a clean, versioned patch series per kernel point release. Designed for downstream reuse — XanMod, Liquorix, and Smooth* all consume from it.

The series we apply (see [`kernel-config.md`](kernel-config.md) for toggles):

- **BORE scheduler** — EEVDF-based burst-aware scheduler. Default.
- **BBRv3** — TCP congestion control; strictly better for NAS/router/desktop/HTPC (all of whom push or pull bytes).
- **MM/MGLRU tuning** — better page-cache and THP behavior; benefits NAS page cache and router conntrack tables.
- **bcachefs + btrfs improvements** — NAS storage win.
- **zstd compression levels** — btrfs compression ratios; initramfs/kernel compression.
- **AMD P-State, Intel thread director tweaks, timer subsystem fixes** — modern-CPU correctness/performance.
- **sched-ext** — compiled in, not default. Advanced-user escape hatch.
- **Wine/Proton support** (NTSYNC, fsync, futex2) — desktop win; futex2 is a better primitive that any multi-threaded daemon (Samba, Unbound) benefits from even if they don't opt in explicitly.

### Secondary: Nobara cherry-picks

Nobara's patchset is entangled with Fedora build scripts, so we don't consume the series. But a few HID/peripheral bits are worth applying:

- **OpenRGB kernel patches** — required for OpenRGB userspace to work.
- **Steam Controller / 8BitDo / DualSense wireless quirks** — beyond what upstream `hid-*` covers.
- **Specific wireless firmware handoff fixes** — case-by-case.

All of these are driver-level patches. On a headless NAS or router, the driver never loads because the hardware isn't present — zero runtime cost.

### Explicitly not applied

- CachyOS's aggressive compile flags (`-O3`, LTO). We build the kernel O2; microarch is x86-64-v2. Hardware inclusivity beats last-percent perf, especially for HTPC/NAS on cheap/old boxes.
- Debian-specific kernel patches (module signing enforcement defaults, etc.) are *not* carried — we build from kernel.org sources, not Debian's source package.

## Hardware baseline

- **x86-64-v2** — baseline ISA. Covers basically every x86 box from ~2009+. A lot of HTPC hardware (repurposed desktops) and NAS hardware (low-end Intel NUCs, older Xeons) is v2 but not v3.
- Optional `linux-smoothkernel-v3` variant could come later if there's measurable benefit and demand. Not v1.

## Configuration

One canonical `.config`, versioned in smoothkernel. See [`kernel-config.md`](kernel-config.md) for the shape and rationale. Key points:

- `CONFIG_PREEMPT=y`
- `CONFIG_HZ=1000`
- `CONFIG_SCHED_BORE=y`, BORE selected as default
- `CONFIG_MODULE_SIG_FORCE=y`, with packaged modules signed in release builds and DKMS modules signed on-host (see [`signing.md`](signing.md))
- `CONFIG_DEBUG_INFO_BTF=n`, debug info stripped (matches `build-kernel.sh` STRIP_DEBUG_INFO=1 default)
- APPLIANCE_TRIM profile-equivalent: drop driver families no Smooth* flavor ships (mainframe, niche industrial, etc.) — carried through from `build-kernel.sh`

Filesystems built in: ext4, xfs, btrfs, bcachefs. ZFS stays DKMS (CDDL/GPL).

## Build flow

Starting state: `recipes/build-kernel.sh` fetches a kernel.org tarball, seeds a `.config`, runs `bindeb-pkg`. Under the one-kernel model this is extended with a patch-apply step:

```
kernel.org tarball
    ↓
extract + verify sha256
    ↓
apply CachyOS patch series (per-kernel-version)
    ↓
apply Nobara HID cherry-picks
    ↓
seed canonical .config
    ↓
make olddefconfig
    ↓
strip debug-info (default)
    ↓
apply appliance-trim (net-tuning, server-tuning — already in build-kernel.sh)
    ↓
make bindeb-pkg
    ↓
release build signs packaged modules
    ↓
linux-{image,headers,libc-dev,modules}-smoothkernel_*.deb in out/
```

DKMS modules are not signed here; they are signed on the target system by `smooth-secureboot` after each DKMS rebuild.

The existing `build.env`-driven shape continues to work; it just grows two new variables — `CACHYOS_PATCH_TAG` and `NOBARA_PATCH_REF` — that point at the patch sources for this kernel version. `LOCALVERSION=-smooth` replaces `-smoothnas-lts` (etc.).

## Rebase cadence

Target: track each kernel point release (`.1`, `.2`, ...) as CachyOS publishes the corresponding patch series. In practice that's every 1–2 weeks.

When CachyOS lags a point release:

- **Small lag (< 1 week)**: wait.
- **Larger lag**: skip that point release. We don't carry CachyOS patches ourselves — the maintenance surface is too wide. Document the skip in the PR that lands the next version.

When CachyOS skips a release entirely: we skip too.

Major version bumps (e.g. 6.x → 7.0) follow the conservative rule from [`bumping-kernel.md`](bumping-kernel.md): wait until `.1` minimum before shipping to users.

## DKMS modules

Every flavor that needs out-of-tree kernel code consumes `linux-headers-smoothkernel` via DKMS. Current consumers:

- `zfs-dkms` — SmoothNAS. OpenZFS tracks kernel compatibility per release; see [`bumping-kernel.md`](bumping-kernel.md) for the version-pairing rule.
- `smoothfs` — SmoothNAS-specific filesystem module. Uses the `compat.h` pattern (see [`kernel-config.md`](kernel-config.md)).
- NVIDIA proprietary — optional on HTPC/desktop. Ships via Debian's `nvidia-driver-*` packages (mirrored or pulled directly) which are DKMS-compatible.

New DKMS modules follow the `templates/` pattern already in smoothkernel. Nothing changes in the harness.

## Relationship to the existing harness

The existing smoothkernel harness (recipes/, templates/, Makefile) remains the right tool — the one-kernel model simplifies its *consumer* shape, not the harness itself. Changes:

- Canonical `.config` becomes part of smoothkernel (or a sibling `smoothkernel-config` repo), not per-flavor
- `LOCALVERSION` convention collapses to `-smooth`
- Add a patch-apply step between extract and config-seed
- `build.env` grows patch-source variables
- `examples/smoothnas.env` becomes `examples/smooth.env` (or similar) — just one

See [`bumping-kernel.md`](bumping-kernel.md) for the updated bump runbook.

## Open questions

- **Canonical `.config` custody** — inside smoothkernel/ or a sibling repo? Leaning inside smoothkernel to keep it colocated with the recipes that consume it.
- **Patch vendoring vs git submodule** — CachyOS patches could be vendored into `patches/cachyos-<ver>/` per release (build-time stable, git-size cost) or pulled via submodule (repo stays small, needs network during build). Leaning vendor for CI simplicity and reproducibility.
- **Release-key scope** — one Smooth* module-signing key keeps the one-kernel pipeline simple, but per-product keys reduce blast radius.
