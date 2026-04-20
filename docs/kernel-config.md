# Kernel config

The canonical `.config` for `linux-smoothkernel`. One config for every Smooth* flavor. See [`KERNEL.md`](KERNEL.md) for the one-kernel rationale and [`bumping-kernel.md`](bumping-kernel.md) for how the config carries forward across kernel bumps.

## Custody

The config lives in smoothkernel (colocated with the recipes that consume it), committed as `configs/smooth-amd64.config`. Versioned alongside the patch series for that kernel version.

```
smoothkernel/
├── configs/
│   ├── smooth-amd64.config          The canonical config, current kernel line
│   └── <kernel-version>/            Archived configs from prior kernel bumps
├── patches/
│   ├── cachyos-<kernel-version>/    Vendored base lane (`0001-bore.patch` on pristine kernel.org today)
│   ├── nobara-picks/                Cherry-picked Nobara HID patches
│   └── post-nobara-<kernel-version>/ Extra carry patches applied after Nobara
└── recipes/
    └── build-kernel.sh              Consumes configs/ + ordered patch lanes automatically
```

## Invariants

The following settings are load-bearing across every flavor. Changing one has cross-flavor consequences; don't touch without updating [`KERNEL.md`](KERNEL.md) and filing a PR with rationale.

| Setting | Value | Reason |
|---|---|---|
| `CONFIG_PREEMPT` | `y` | Full preemption; BORE makes the server-side cost negligible |
| `CONFIG_HZ` | `1000` | UI/game responsiveness; negligible server impact on modern hardware |
| `CONFIG_SCHED_BORE` | `y` | BORE scheduler enabled by the vendored base lane; default `y` |
| `CONFIG_SCHED_EXT` | `m` | sched-ext available as a module; not default, escape hatch |
| Microarch baseline | `x86-64-v2` | Inclusivity for HTPC/NAS on ~2009+ hardware |
| `CONFIG_MODULE_SIG_FORCE` | `n` | See [`signing.md`](signing.md); Phase 0.10 blocker |
| `CONFIG_DEBUG_INFO_BTF` | `n` | Set by `STRIP_DEBUG_INFO=1` default in build-kernel.sh |
| `CONFIG_SYSTEM_TRUSTED_KEYS` | `""` | Cleared to avoid Debian's trusted-keys path |
| `CONFIG_SYSTEM_REVOCATION_KEYS` | `""` | Same |

## Filesystems

Built in as modules (available but not always loaded):

- ext4, xfs, btrfs, bcachefs — all built in as `=m`
- ZFS — *not* in-tree (CDDL/GPL); ships as `zfs-dkms`
- NTFS3 — `=m` (useful for external drives on desktop/HTPC)
- f2fs, exfat, FAT — `=m`
- Network filesystems: CIFS, NFSv3/v4 — `=m`

## Networking

- IPv4/IPv6 — built in
- netfilter + nftables — built in (required for smoothrouter's default-deny posture)
- `tcp_bbr` — built in, default congestion control (matches existing `build-kernel.sh` NET_TUNING)
- `sch_fq` — built in, default qdisc
- VLAN, bridge, bonding, VXLAN — `=m`
- WireGuard — built in (required for smoothrouter)

## Hardware support

Built in: the handful of drivers needed to boot every supported platform. Everything else as modules.

- Core: AHCI, NVMe, USB storage
- GPU: amdgpu, i915, xe, nouveau, radeon — all `=m`
- Network: common NIC drivers (e1000e, igc, ixgbe, r8169, iwlwifi, mt76) — `=m`
- USB HID, input — `=y` for boot-time usability

## What we drop

The existing `build-kernel.sh` has an APPLIANCE_TRIM profile, but it is scoped to hardware families no Smooth* flavor is expected to rely on. It must not disable HTPC / Desktop basics like DRM, audio, media, wifi, or controller input. The trim list stays narrow:

- Mainframe / s390 / IBM Power drivers — `n`
- Niche industrial buses (CAN, I2C multiplexers for industrial) — `n`
- Exotic network devices (InfiniBand in some configs) — `n`, revisit if a user case emerges
- Obscure filesystems (reiserfs [removed upstream], hfs*, ubifs) — `n`

Revisit the trim list when a user reports hardware that needs something we dropped.

## Per-flavor differences that DON'T go here

These come up in `.config` discussions but belong in flavor `-tuning` packages, not the kernel config:

- Default I/O scheduler per device class (BFQ for rotational, mq-deadline for SSD) → udev rules
- VM tuning (swappiness, dirty_ratio) → sysctl fragment
- Network buffer sizes → sysctl fragment
- CPU governor → tuned profile
- Forwarding on/off → sysctl fragment
- `vm.max_map_count` bumps for gaming → sysctl fragment

See the per-flavor docs (SMOOTHNAS.md, SMOOTHROUTER.md, SMOOTHHTPC.md, SMOOTHDESKTOP.md) for the actual values.

## Per-flavor differences that legitimately need kernel support

Currently none. Every user-relevant difference between flavors is solvable in userspace with the canonical kernel. If that changes, this table fills in:

| Flavor | What they need | Why userspace can't do it |
|---|---|---|
| — | — | — |

Adding a row is a strong signal to reconsider whether the one-kernel model is still correct.

## Updating the config

When a kernel bump introduces new config symbols (common on major bumps):

1. `make kernel-config-update` refreshes the patched tree, runs `olddefconfig`, reapplies the SmoothKernel profile, and writes the resulting config back into `configs/`.
2. Review the resulting diff. Sometimes a new option defaults to `y` and bloats the image; sometimes to `n` and disables something we want. Check the diff manually.
3. Commit the updated `configs/smooth-amd64.config` and `configs/<kernel-version>/smooth-amd64.config` as part of the kernel-bump PR.

## Out-of-tree modules

Smooth* out-of-tree kernel modules (currently just `smoothfs`) use the `compat.h` shim pattern documented in the existing templates. See [`templates/compat.h.in`](../templates/compat.h.in) and the update steps in [`bumping-kernel.md`](bumping-kernel.md) for how to move `KERNEL_FLOOR_MAJOR`/`MINOR` across a bump.

New out-of-tree modules in Smooth* repos follow the same pattern — copy the template, wire into the repo's `debian/` packaging, build via DKMS against `linux-headers-smoothkernel`.

## Non-goals

- **Per-flavor kernel variants.** Not shipping `linux-smoothkernel-server`, `linux-smoothkernel-desktop`, etc. One binary. See [`ARCHITECTURE.md`](ARCHITECTURE.md).
- **Microarch variants.** Not shipping `linux-smoothkernel-v3`. Possible future addition if demand justifies; not v1.
- **A "configurator" UI for the kernel.** Users don't configure kernels. That's what this doc — and one canonical config — exists to avoid.
