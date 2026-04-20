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

### Base lane: pristine kernel.org + vendored downstream patches

SmoothKernel builds from a pristine kernel.org tarball. Downstream scheduler and kernel adjustments are then applied from vendored patch lanes committed in-tree.

For the current `6.19.12` line, the base lane is derived from CachyOS's scheduler work but intentionally uses `sched/0001-bore.patch` rather than `0001-bore-cachy.patch`. `bore-cachy` expects additional Cachy scheduler deltas that are not present in a pristine kernel.org tree; `0001-bore.patch` applies cleanly and gives us the BORE default without inheriting hidden source deltas.

The base lane we currently carry (see [`kernel-config.md`](kernel-config.md) for toggles):

- **BORE scheduler** — EEVDF-based burst-aware scheduler. Default.

### Secondary: Nobara cherry-picks

Nobara's patchset is entangled with Fedora build scripts, so we don't consume the series. But a few HID/peripheral bits are worth applying:

- **USB interrupt-interval override** — lets specific wired controllers opt into higher poll rates.
- **Logitech G923 PlayStation wheel support** — adds the missing HID ID binding.
- **`xpadneo` Bluetooth Xbox controller integration** — covers Xbox One S/X, Series X|S, Elite, and related 8BitDo Bluetooth mappings better than the generic path.

All of these are driver-level patches. On a headless NAS or router, the driver never loads because the hardware isn't present — zero runtime cost.

### Tertiary: post-Nobara carry patches

Some kernel lines need a small number of additional patches after the Nobara lane. These live in `patches/post-nobara-<kernel-version>/` and are applied last so their provenance and rebasing burden stay explicit.

For `6.19.12`, this lane carries the rebased DRM / gamescope async-flip fixups
that were not clean “drop-in” Nobara picks.

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
- `CONFIG_MODULE_SIG_FORCE=n` for now (see [`signing.md`](signing.md))
- `CONFIG_DEBUG_INFO_BTF=n`, debug info stripped (matches `build-kernel.sh` STRIP_DEBUG_INFO=1 default)
- APPLIANCE_TRIM profile-equivalent: drop only cross-flavor-irrelevant legacy / industrial families. It must not remove DRM, audio, media, wifi, or input support needed by HTPC / Desktop.

Filesystems built in: ext4, xfs, btrfs, bcachefs. ZFS stays DKMS (CDDL/GPL).

## Build flow

Starting state: `recipes/build-kernel.sh` fetches a kernel.org tarball, seeds a `.config`, runs `bindeb-pkg`. Under the one-kernel model this is extended with an ordered patch-apply step:

```
kernel.org tarball
    ↓
extract + verify sha256
    ↓
apply base lane from patches/cachyos-<kernel-version>
    ↓
apply Nobara HID cherry-picks
    ↓
apply patches/post-nobara-<kernel-version>
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
linux-{image,headers,libc-dev,modules}-smoothkernel_*.deb in out/
```

The existing `build.env`-driven shape continues to work, but the patch inputs are now lane names rather than remote refs:

- `CACHYOS_PATCHSET=cachyos-<kernel-version>`
- `NOBARA_PATCHSET=nobara-picks`
- `POST_NOBARA_PATCHSET=post-nobara-<kernel-version>`

`LOCALVERSION=-smooth` replaces `-smoothnas-lts` (etc.).

## Rebase cadence

Target: track each kernel point release (`.1`, `.2`, ...) as upstream stable and the required downstream patch lanes are ready.

When a new point release arrives:

- Refresh the base lane from the relevant downstream source material.
- Rebase or refresh any Nobara picks that still apply.
- Rebase or refresh the post-Nobara carry patches.
- Run `make kernel-config-update`, then `make kernel zfs`.

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
- Add an ordered patch-lane step between extract and config-seed
- `build.env` grows patchset variables
- `examples/smoothnas.env` becomes `examples/smooth.env` (or similar) — just one

See [`bumping-kernel.md`](bumping-kernel.md) for the updated bump runbook.

## Open questions

- **Exact downstream provenance cadence** — how often we refresh the base lane from CachyOS/Nobara versus carrying local rebases longer-term.
- **Kernel signing** — tracked in [`signing.md`](signing.md). Phase 0.10 blocker for appliance shipping.
