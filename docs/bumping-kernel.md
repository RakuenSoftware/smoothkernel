# Bumping the kernel pin

The procedure when moving `linux-smoothkernel` to a newer kernel version. Applies to both major bumps (`6.x → 7.x`) and point bumps (`6.18.22 → 6.18.30`).

One kernel across all four flavors, so one bump is a single coordinated edit — no per-flavor version skew.

Repository status: the current harness has not yet wired in vendored CachyOS/Nobara patches or a checked-in canonical `configs/` tree. The practical bump flow today is version selection + seed-config refresh + build/validation. References below to vendored patch flow are target-state notes unless the recipes gain that wiring.

## When to bump

Bump when the latest stable kernel that the must-have DKMS set supports moves forward.

For Smooth* the must-have DKMS set is OpenZFS (required by SmoothNAS). Rule: **latest stable kernel ≤ OpenZFS `Linux-Maximum` AND covered by a CachyOS patch-series release**.

Check OpenZFS:

```
$ curl -fsSL https://github.com/openzfs/zfs/raw/zfs-2.4.1/META | grep ^Linux
Linux-Maximum: 6.19
Linux-Minimum: 4.18
```

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
ZFS_VERSION=2.4.1                   # bump if pairing requires it
CONFIG_SOURCE=/tmp/smooth-seed.config
```

### 2. Refresh the seed config

Refresh `CONFIG_SOURCE` from a known-good machine or a previously validated build:

```sh
ssh smoothbox 'cat /boot/config-$(uname -r)' > /tmp/smooth-seed.config
```

The current harness consumes this external seed file directly. A checked-in canonical `configs/` tree is still future work.

### 3. Build and verify

```sh
make kernel     # builds bindeb-pkg kernel artifacts
make zfs        # builds zfs-dkms_*.deb against the new KERNEL_VERSION
ls out/
```

Both must build clean. Kernel build failures are usually patch-conflict or config drift; ZFS build failures are usually a kernel-API break that OpenZFS hasn't caught up to yet.

Local builds are sufficient for patch/config bring-up. The promotable artifact still comes from signing-capable CI so packaged modules carry the Rakuen release signature described in [`signing.md`](signing.md).

### 4. Update out-of-tree module compat shims

For each consuming repo with an out-of-tree module (`smoothfs` in SmoothNAS today; others later):

1. Edit the module's `compat.h`:
   - Bump `KERNEL_FLOOR_MAJOR` / `KERNEL_FLOOR_MINOR` to the new floor.
   - Sweep dead pre-floor branches (anything inside `#if LINUX_VERSION_CODE < KERNEL_VERSION(<old_floor>, …)` is now unreachable — delete).
   - For new kernel APIs the new floor makes available and you want to adopt: add `#if LINUX_VERSION_CODE >= KERNEL_VERSION(<new_floor>, …)` blocks; expose them via `<prefix>_compat_*()` helpers.
2. Update the module's `dkms.conf` `BUILD_EXCLUSIVE_KERNEL` regex if needed.

### 5. Deploy to a test box

```sh
scp out/*.deb test-box:/tmp/
ssh test-box 'sudo dpkg -i /tmp/linux-*_*.deb /tmp/zfs*.deb /tmp/lib*.deb'
ssh test-box 'sudo reboot'
```

### 6. Validate

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

### 7. Promote to `common` main

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

### 8. Secure-Boot verify

Before marking the bump promotable:

- verify a CI-produced kernel package reports a non-empty signer on one packaged module
- verify a Secure-Boot-enabled test machine enrolled via `smooth-secureboot` can rebuild and load ZFS
- verify an unsigned ad-hoc module is rejected

See [`signing.md`](signing.md) for the trust model.

## Tradeoffs to remember

- **Major bumps (`6.x → 7.0`)** historically have more API churn and surface more shim work. Wait for `7.1` minimum before shipping to users.
- **Point bumps within an LTS** (`6.18.22 → 6.18.30`) usually only surface config drift or out-of-tree module fallout.
- **Cross-line bumps** (`6.18 → 6.19`) often involve real API changes. Plan for shim work in any DKMS consumer.
- **OpenZFS lag**: typically 1–3 months behind mainline stable. Same "wait" rule if NAS is in-scope.

## Future patch-vendoring lane

If SmoothKernel later wires in vendored CachyOS or Nobara patches, reintroduce those checks into this runbook at the same time as the recipe change. Until then, keep the bump instructions tied to the actual harness behavior.

## Single-flavor rollback

The one-kernel model means we can't selectively roll back the kernel for one flavor. If kernel X breaks SmoothDesktop but is fine on SmoothNAS, both roll back. In practice this has been rare (most kernel regressions affect either all workloads or none), but it's a trade we accept for the maintenance savings.

If a flavor-specific rollback becomes chronic, that's a strong signal to reconsider the one-kernel decision. See [`ARCHITECTURE.md`](ARCHITECTURE.md) and [`kernel-config.md`](kernel-config.md).
