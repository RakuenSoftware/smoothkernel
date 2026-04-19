# SmoothNAS

NAS appliance flavor. This doc is the Smooth* cross-repo contract for SmoothNAS: what goes in the `smoothnas` apt suite, how the existing Makefile maps to Debian packaging, and the NAS-specific bits of the shared base. The SmoothNAS repo may carry deeper product-internal details, but cross-cutting decisions should be readable from here.

## Suite composition (`smoothnas` suite)

| Package | Source | Purpose |
|---|---|---|
| `smoothnas` | `smooth-meta` | Flavor meta — pulls kernel + tuning + tierd + tierd-ui + storage stack |
| `smoothnas-tuning` | `smooth-meta` | udev rules, sysctl fragments, tuned profile |
| `tierd` | `SmoothNAS` | Go backend daemon (CGO, libzfs, libfuse3 bindings) |
| `tierd-ui` | `SmoothNAS` | React/Vite UI consuming `@rakuensoftware/smoothgui` |
| `smoothfs` | `SmoothNAS` | Out-of-tree kernel module (DKMS) |
| `smoothfs-utils` | `SmoothNAS` | Userspace tools for smoothfs |

Shared from `common`: `linux-smoothkernel`, `linux-headers-smoothkernel`, `linux-firmware-smooth`, `smooth-base`, `zfs-dkms` (if we host it; otherwise pulled from Debian), `smoothgui-assets` (optional — cached smoothgui build for offline installer).

## Meta-package dependencies

`smoothnas` pulls (paraphrased `debian/control`):

```
Depends:
 linux-image-smoothkernel,
 linux-headers-smoothkernel,
 linux-firmware-smooth,
 smooth-base,
 smoothnas-tuning,
 tierd,
 tierd-ui,
 smoothfs,
 smoothfs-utils,
 zfs-dkms,
 zfsutils-linux,
 samba,
 nfs-kernel-server,
 tgt,
 mdadm,
 lvm2,
 btrfs-progs,
 bcachefs-tools,
 smartmontools,
 nginx,
 openssh-server
Recommends:
 minidlna,
 syncthing,
 cockpit
```

No graphical dependencies — NAS is headless.

## Existing Makefile → Debian packaging

`SmoothNAS/Makefile` already has `install` and build targets. The Debian packaging wraps it:

```
SmoothNAS/
├── Makefile                     (existing — builds tierd, tierd-ui, smoothfs)
├── debian/                      (new — packaging metadata)
│   ├── control                  declares tierd, tierd-ui, smoothfs, smoothfs-utils, smoothnas
│   ├── rules                    invokes `make build` then stages files
│   ├── tierd.install            bin/tierd → /usr/bin/tierd
│   ├── tierd.service            systemd unit (move from tierd/deploy/)
│   ├── tierd.postinst           nginx site enable + smooth-tls-gen
│   ├── tierd-ui.install         tierd-ui/dist/ → /usr/share/tierd-ui
│   ├── smoothfs.dkms            DKMS config (from templates/dkms.conf.in)
│   └── changelog
```

Key change from the existing Makefile: binaries install to `/usr/bin/tierd` (Debian policy) rather than `/usr/local/bin/tierd`. The existing Makefile's `install` target remains for dev-box direct-install; the `.deb` path is the production path.

## NAS-specific tuning (`smoothnas-tuning`)

Ships three files:

```
/etc/sysctl.d/60-smoothnas.conf
/etc/udev/rules.d/60-smoothnas-io.rules
/etc/tuned/profiles/smoothnas/tuned.conf
```

**Sysctl (excerpt):**

```
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_congestion_control = bbr
```

**udev I/O scheduler rules:**

```
# Rotational disks → BFQ (better for interactive + bulk mixed)
ACTION=="add|change", KERNEL=="sd[a-z]|hd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
# SSD → mq-deadline (simpler, lower latency than BFQ on SSD)
ACTION=="add|change", KERNEL=="sd[a-z]|hd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
# NVMe → none (NVMe has its own queueing)
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
```

**tuned profile:**

```
[main]
summary=SmoothNAS: throughput + readahead, CPU powersave
include=throughput-performance

[cpu]
governor=powersave
energy_perf_bias=balance-power

[sysfs]
/sys/block/*/queue/read_ahead_kb=4096
```

Everything here is runtime, kernel-neutral, and independently installable — someone could put `smoothnas-tuning` on a bare Debian and get the storage-oriented sysctls without any smoothnas binaries.

## ZFS posture

`zfs-dkms` from DKMS, built against `linux-headers-smoothkernel`. OpenZFS release pairing follows the rule in [`bumping-kernel.md`](bumping-kernel.md) — kernel version ≤ the OpenZFS release's `Linux-Maximum`.

We can either:

- (a) Mirror `zfs-dkms` and `zfsutils-linux` into `common` (rebuilt when OpenZFS releases).
- (b) Pull from Debian. Lags upstream by months, frustrating when a kernel bump outruns Debian's ZFS.

Leaning (a) because kernel cadence is the bottleneck and Debian's ZFS will chronically lag. Implementation: extend `smoothkernel`'s existing `build-zfs.sh` recipe to produce signed Debian packages for the `common` suite.

## Installer considerations

See [`INSTALLERS.md`](INSTALLERS.md). NAS-specific bits:

- Optional ZFS-on-root at install time.
- Non-OS disks stay untouched — post-install the web UI manages them.
- First-boot UX: admin user created at install; web UI login is a separate credential set on first browser access.

## Relationship to repo-local aimee

`SmoothNAS/.mcp.json` configures a repo-local aimee MCP server for engineering agents (see [`SmoothNAS/docs/ARCHITECTURE.md`](../../SmoothNAS/docs/ARCHITECTURE.md) §1.1). This is engineering surface, not appliance runtime, and not shipped in .debs.

Other Smooth* products will likely adopt the same repo-local aimee pattern as they mature.

## Open questions

- **zfs-dkms custody.** Mirror (a) vs Debian (b) — decision pending; lean (a) as above.
- **Installer ZFS modules.** See [`INSTALLERS.md`](INSTALLERS.md).
- **Appliance-mode hardening.** Should the `.deb` install disable password login by default and force SSH-key-only? Right posture for an appliance, but increases first-boot friction. Decision deferred.
