# Bumping the kernel pin

The standard procedure when moving a Smooth* OS to a newer kernel version. Applies to both major bumps (6.x → 7.x) and point bumps (6.18.22 → 6.18.30).

## When to bump

Bump when the *latest stable kernel that the must-have DKMS set supports* moves forward. For SmoothNAS, the must-have DKMS set is OpenZFS — so the rule is "latest stable kernel ≤ OpenZFS Linux-Maximum". Check the OpenZFS `META` file in the release tarball:

```
$ curl -fsSL https://github.com/openzfs/zfs/raw/zfs-2.4.1/META | grep ^Linux
Linux-Maximum: 6.19
Linux-Minimum: 4.18
```

For Smooth* OSes without ZFS, the rule is "latest stable kernel". Always pick a stable point release (`x.y.z`), never `-rc` or `-next`.

## Steps

1. **Pick the new version.** Cross-reference kernel.org `finger_banner` against the DKMS set you depend on. Update `build.env`:
   ```sh
   KERNEL_VERSION=6.19.10
   LOCALVERSION=-smoothnas-lts        # unchanged across point bumps
   ZFS_VERSION=2.4.1                  # bump together if needed
   CONFIG_SOURCE=/path/to/seed.config
   ```

2. **Build the new kernel + ZFS .debs:**
   ```sh
   make kernel
   make zfs
   ls out/   # linux-image-*, linux-headers-*, linux-libc-dev_*, zfs-dkms_*, libs
   ```

3. **For each consuming Smooth* OS**, in its `compat.h`:
   - Bump `KERNEL_FLOOR_MAJOR` and `KERNEL_FLOOR_MINOR` to the new floor.
   - Sweep dead pre-floor branches. (Anything inside `#if LINUX_VERSION_CODE < KERNEL_VERSION(<old_floor>, …)` blocks is now unreachable.)
   - For new APIs the new floor makes available that you want to adopt: add `#if LINUX_VERSION_CODE >= KERNEL_VERSION(<new_floor>, …)` blocks. Expose them via `<prefix>_compat_*()` helpers.
   - Update the module's `dkms.conf` `BUILD_EXCLUSIVE_KERNEL` regex.

4. **Compile each Smooth* OS module** against the new kernel headers. Fix any drift the kernel surface introduced. The `compat.h` pattern keeps this localized — drift fixes go inside the helper, call sites stay clean.

5. **Deploy to a test box:**
   ```sh
   scp out/*.deb test-box:/tmp/
   ssh test-box 'sudo dpkg -i /tmp/linux-*_*.deb /tmp/zfs*.deb /tmp/lib*.deb'
   ssh test-box 'sudo reboot'
   ```

6. **Validate** the OS-specific module loads and a smoke test passes on the new kernel.

7. **Sign + ship** per `docs/signing.md`.

## Tradeoffs to remember

- **Major bumps (`6.x → 7.0`)** historically have more API churn and surface more shim work. Wait at least until `7.1` for production.
- **Point bumps within an LTS** (`6.18.22 → 6.18.30`) almost never break out-of-tree modules. Quick to roll forward.
- **Cross-LTS bumps** (`6.18 → 6.19`) often involve real API changes (the kind that change function signatures). Plan for shim work.
- **OpenZFS lag**: OpenZFS typically supports the latest stable kernel within 1–3 months of its release. If you want to track mainline tightly, expect to wait.
