# Bumping the kernel pin

The procedure when moving `linux-smoothkernel` to a newer kernel version. Applies to both major bumps (`6.x → 7.x`) and point bumps (`6.18.22 → 6.18.30`).

One kernel across all four flavors, so one bump is a single coordinated edit — no per-flavor version skew.

## When to bump

Bump when the *latest stable kernel that the must-have DKMS set supports AND our vendored patch lanes are ready for* moves forward.

For Smooth* the must-have DKMS set is OpenZFS (required by SmoothNAS). Rule: **latest stable kernel ≤ OpenZFS `Linux-Maximum` AND our vendored patch lanes are ready for that kernel**.

Check OpenZFS:

```
$ curl -fsSL https://github.com/openzfs/zfs/raw/zfs-2.4.1/META | grep ^Linux
Linux-Maximum: 6.19
Linux-Minimum: 4.18
```

Check your downstream sources:

```
$ git log -- patches/cachyos-* patches/nobara-picks patches/post-nobara-* | head
```

If the downstream patch material for your target kernel is not ready yet, wait or do the rebase work first. SmoothKernel vendors the exact lane it builds.

Always pick a stable point release (`x.y.z`), never `-rc` or `-next`.

## Steps

### 1. Pick the new version

Cross-reference:

- kernel.org stable
- OpenZFS `Linux-Maximum` (for NAS-supporting kernels)
- CachyOS patch-series availability

Update `build.env`:

```sh
KERNEL_VERSION=6.19.12
LOCALVERSION=-smooth                # never changes under the one-kernel model
CACHYOS_PATCHSET=cachyos-6.19.12
NOBARA_PATCHSET=nobara-picks
POST_NOBARA_PATCHSET=post-nobara-6.19.12
ZFS_VERSION=2.4.1                   # bump if pairing requires it
```

### 2. Vendor the patch lanes

Refresh the ordered patch lanes and commit them:

```sh
mkdir -p patches/cachyos-$KERNEL_VERSION patches/post-nobara-$KERNEL_VERSION
# copy or regenerate the base lane, starting with the pristine-kernel-safe BORE patch
# refresh any Nobara picks in patches/nobara-picks/
# copy or regenerate any post-Nobara carry patches
git add patches/cachyos-$KERNEL_VERSION patches/nobara-picks patches/post-nobara-$KERNEL_VERSION
git commit -m "patches: refresh kernel lanes for $KERNEL_VERSION"
```

Vendoring keeps builds reproducible and CI-offline-safe. The current pristine-kernel base lane uses `0001-bore.patch`, not `0001-bore-cachy.patch`.

### 3. Update the canonical config

```sh
make kernel-config-update     # runs `make olddefconfig` against the new kernel
```

Review the diff in `configs/smooth-amd64.config`. New `CONFIG_*` symbols default to the kernel's preference; check that defaults don't regress the invariants in [`kernel-config.md`](kernel-config.md) (PREEMPT=y, HZ=1000, SCHED_BORE=y, etc.). `make kernel-config-update` also refreshes `configs/<kernel-version>/smooth-amd64.config`.

### 4. Build and verify

```sh
make kernel     # builds linux-{image,headers,libc-dev,modules}-smoothkernel_*.deb
make zfs        # builds zfs-dkms_*.deb against the new KERNEL_VERSION
ls out/
```

Both must build clean. Kernel build failures are usually patch-conflict or config drift; ZFS build failures are usually a kernel-API break that OpenZFS hasn't caught up to yet.

### 5. Update out-of-tree module compat shims

For each consuming repo with an out-of-tree module (`smoothfs` in SmoothNAS today; others later):

1. Edit the module's `compat.h`:
   - Bump `KERNEL_FLOOR_MAJOR` / `KERNEL_FLOOR_MINOR` to the new floor.
   - Sweep dead pre-floor branches (anything inside `#if LINUX_VERSION_CODE < KERNEL_VERSION(<old_floor>, …)` is now unreachable — delete).
   - For new kernel APIs the new floor makes available and you want to adopt: add `#if LINUX_VERSION_CODE >= KERNEL_VERSION(<new_floor>, …)` blocks; expose them via `<prefix>_compat_*()` helpers.
2. Update the module's `dkms.conf` `BUILD_EXCLUSIVE_KERNEL` regex if needed.

### 6. Deploy to a test box

```sh
scp out/*.deb test-box:/tmp/
ssh test-box 'sudo dpkg -i /tmp/linux-*_*.deb /tmp/zfs*.deb /tmp/lib*.deb'
ssh test-box 'sudo reboot'
```

### 7. Validate

Per-flavor smoke tests. At minimum:

- **SmoothNAS**: mount a ZFS pool, export an SMB share, confirm tierd starts + UI loads.
- **SmoothRouter**: pass packets WAN↔LAN, verify nftables rules applied, wireguard handshake completes.
- **SmoothHTPC**: boot to smoothtv, launch Kodi, verify VA-API hardware decode.
- **SmoothDesktop**: boot to Plasma, launch Firefox and Steam Big Picture, verify GPU acceleration.

Flavor-specific smoke tests live in their respective repos' `docs/OPERATIONS.md`.

### 8. Promote to `common` main

Publish the `.deb`s to the apt repo's `common` suite via the usual path (see [`../../apt-repo/README.md`](../../apt-repo/README.md)):

```sh
cd ../apt-repo
scripts/add-package.sh common ../smoothkernel/out/linux-*.deb
scripts/add-package.sh common ../smoothkernel/out/zfs*.deb ../smoothkernel/out/lib*.deb
git add pool/ dists/
git commit -m "common: linux-smoothkernel $KERNEL_VERSION, zfs $ZFS_VERSION"
git push
```

Signing and GitHub Pages deploy runs in CI.

### 9. Sign

Module signing is a Phase 0.10 blocker for appliance shipping. Currently unsigned; see [`signing.md`](signing.md). Update this doc when signing lands.

## Tradeoffs to remember

- **Major bumps (`6.x → 7.0`)** historically have more API churn and surface more shim work. Wait for `7.1` minimum before shipping to users.
- **Point bumps within an LTS** (`6.18.22 → 6.18.30`) almost never break out-of-tree modules. Fast.
- **Cross-line bumps** (`6.18 → 6.19`) often involve real API changes. Plan for shim work in any DKMS consumer.
- **Patch-lane lag**: if the base lane, Nobara picks, or post-Nobara carry patches are not ready for your target kernel, wait or schedule the rebase work.
- **OpenZFS lag**: typically 1–3 months behind mainline stable. Same "wait" rule if NAS is in-scope.

## When a patch lane skips a kernel version

Sometimes the downstream material you are following skips a point release, or a carry patch only rebases cleanly on the next one. In that case we can skip that version too. Document the skip in the bump PR's changelog:

```
bump kernel: 6.19.6 → 6.19.9 (skipping .7 and .8; downstream patch lanes were not ready)
```

## When a major kernel bump requires patch-series rework

Major version bumps (6 → 7) often require real rebase work across the base lane, Nobara picks, and any post-Nobara carry patches. The rule is unchanged: wait. The conservative `x.1` minimum for shipping to users gives downstream patch material time to stabilize against the new kernel line too.

## Single-flavor rollback

The one-kernel model means we can't selectively roll back the kernel for one flavor. If kernel X breaks SmoothDesktop but is fine on SmoothNAS, both roll back. In practice this has been rare (most kernel regressions affect either all workloads or none), but it's a trade we accept for the maintenance savings.

If a flavor-specific rollback becomes chronic, that's a strong signal to reconsider the one-kernel decision. See [`ARCHITECTURE.md`](ARCHITECTURE.md) and [`kernel-config.md`](kernel-config.md).
