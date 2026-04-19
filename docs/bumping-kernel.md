# Bumping the kernel pin

The procedure when moving `linux-smoothkernel` to a newer kernel version. Applies to both major bumps (`6.x → 7.x`) and point bumps (`6.18.22 → 6.18.30`).

One kernel across all four flavors, so one bump is a single coordinated edit — no per-flavor version skew.

## When to bump

Bump when the *latest stable kernel that the must-have DKMS set supports AND CachyOS has published a patch series for* moves forward.

For Smooth* the must-have DKMS set is OpenZFS (required by SmoothNAS). Rule: **latest stable kernel ≤ OpenZFS `Linux-Maximum` AND covered by a CachyOS patch-series release**.

Check OpenZFS:

```
$ curl -fsSL https://github.com/openzfs/zfs/raw/zfs-2.4.1/META | grep ^Linux
Linux-Maximum: 6.19
Linux-Minimum: 4.18
```

Check CachyOS:

```
$ curl -fsSL https://api.github.com/repos/CachyOS/kernel-patches/tags \
  | jq -r '.[] | .name' | head -20
```

If CachyOS hasn't tagged a series for your target kernel yet, wait. We don't carry the patch series ourselves.

Always pick a stable point release (`x.y.z`), never `-rc` or `-next`.

## Steps

### 1. Pick the new version

Cross-reference:

- kernel.org stable
- OpenZFS `Linux-Maximum` (for NAS-supporting kernels)
- CachyOS patch-series availability

Update `build.env`:

```sh
KERNEL_VERSION=6.19.10
LOCALVERSION=-smooth                # never changes under the one-kernel model
CACHYOS_PATCH_TAG=6.19-main         # or whatever CachyOS tags it
NOBARA_PATCH_REF=<commit-sha>       # Nobara HID/OpenRGB cherry-picks, pinned SHA
ZFS_VERSION=2.4.1                   # bump if pairing requires it
```

### 2. Vendor the CachyOS patch series

Pull the CachyOS patches into `patches/cachyos-<KERNEL_VERSION>/` and commit:

```sh
git clone --branch "$CACHYOS_PATCH_TAG" --depth 1 \
  https://github.com/CachyOS/kernel-patches.git /tmp/cachyos-patches
cp -r /tmp/cachyos-patches/patches/<version>/* patches/cachyos-$KERNEL_VERSION/
git add patches/cachyos-$KERNEL_VERSION/
git commit -m "patches: vendor CachyOS $CACHYOS_PATCH_TAG for $KERNEL_VERSION"
```

Vendoring (rather than submoduling) keeps builds reproducible and CI-offline-safe.

### 3. Update the canonical config

```sh
make kernel-config-update     # runs `make olddefconfig` against the new kernel
```

Review the diff in `configs/smooth-amd64.config`. New `CONFIG_*` symbols default to the kernel's preference; check that defaults don't regress the invariants in [`kernel-config.md`](kernel-config.md) (PREEMPT=y, HZ=1000, SCHED_BORE=y, etc.).

Commit the updated config in the same PR as the patch vendor.

### 4. Build and verify

```sh
make kernel     # builds linux-{image,headers,libc-dev,modules}-smoothkernel_*.deb
make zfs        # builds zfs-dkms_*.deb against the new KERNEL_VERSION
ls out/
```

Both must build clean. Kernel build failures are usually patch-conflict or config drift; ZFS build failures are usually a kernel-API break that OpenZFS hasn't caught up to yet.

Local builds are sufficient for patch/config bring-up. The promotable artifact still comes from signing-capable CI so packaged modules carry the Rakuen release signature described in [`signing.md`](signing.md).

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

Per-flavor smoke tests. The minimum publish gate is one representative target per flavor class, not just "the author's test box":

- **SmoothNAS**: real or virtual machine with a ZFS pool and SMB export path
- **SmoothRouter**: dual-NIC box or VM with WAN/LAN traffic path and WireGuard enabled
- **SmoothHTPC**: Intel or AMD GPU box that boots to `smoothtv` and exercises hardware video decode
- **SmoothDesktop**: desktop-class box that boots to Plasma and exercises Rakuen Mesa userspace

Per target, the minimum smoke tests are:

- **SmoothNAS**: mount a ZFS pool, export an SMB share, confirm tierd starts + UI loads.
- **SmoothRouter**: pass packets WAN↔LAN, verify nftables rules applied, wireguard handshake completes.
- **SmoothHTPC**: boot to smoothtv, launch Kodi, verify VA-API hardware decode.
- **SmoothDesktop**: boot to Plasma, launch Firefox and Steam Big Picture, verify GPU acceleration.

NVIDIA is a conditional lane rather than a universal gate: run it whenever the kernel bump also changes NVIDIA-relevant DKMS or graphics packaging assumptions.

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

### 9. Secure-Boot verify

Before marking the bump promotable:

- verify a CI-produced kernel package reports a non-empty signer on one packaged module
- verify a Secure-Boot-enabled test machine enrolled via `smooth-secureboot` can rebuild and load ZFS
- verify an unsigned ad-hoc module is rejected

See [`signing.md`](signing.md) for the trust model.

## Tradeoffs to remember

- **Major bumps (`6.x → 7.0`)** historically have more API churn and surface more shim work. Wait for `7.1` minimum before shipping to users.
- **Point bumps within an LTS** (`6.18.22 → 6.18.30`) almost never break out-of-tree modules. Fast.
- **Cross-line bumps** (`6.18 → 6.19`) often involve real API changes. Plan for shim work in any DKMS consumer.
- **CachyOS lag**: if CachyOS hasn't shipped the patch series for your target kernel, wait. We don't carry patches ourselves.
- **OpenZFS lag**: typically 1–3 months behind mainline stable. Same "wait" rule if NAS is in-scope.

## When CachyOS skips a kernel version

Sometimes CachyOS skips a point release (e.g. 6.19.7 → 6.19.9, no 6.19.8 series). We skip too — there's no partial-patch-series option. Document the skip in the bump PR's changelog:

```
bump kernel: 6.19.6 → 6.19.9 (skipping .7 and .8; CachyOS did not publish series)
```

## When a major kernel bump requires patch-series rework

Major version bumps (6 → 7) sometimes require updated patch series from CachyOS that don't arrive at `x.0` but at `x.1` or later. The rule is unchanged: wait. The conservative `x.1` minimum for shipping to users gives CachyOS time to stabilize its patches against the new kernel line too.

## Single-flavor rollback

The one-kernel model means we can't selectively roll back the kernel for one flavor. If kernel X breaks SmoothDesktop but is fine on SmoothNAS, both roll back. In practice this has been rare (most kernel regressions affect either all workloads or none), but it's a trade we accept for the maintenance savings.

If a flavor-specific rollback becomes chronic, that's a strong signal to reconsider the one-kernel decision. See [`ARCHITECTURE.md`](ARCHITECTURE.md) and [`kernel-config.md`](kernel-config.md).
