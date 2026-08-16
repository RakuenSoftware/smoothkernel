# zfs-2.4.3

Carry patches applied to the pristine OpenZFS `2.4.3` release tarball before
`autogen.sh` runs. Applied by `recipes/build-zfs.sh` via `ZFS_PATCHSET`.

This is the first patch lane for OpenZFS in this repository. It follows the
same rules as the kernel lanes in [`../../docs/PATCHES.md`](../../docs/PATCHES.md):
ordered numeric prefixes, vendored in git, README records source, reason and
removal condition.

Current contents:

- `0001-meta-raise-linux-maximum-to-7.1.patch`

## Why this lane exists

OpenZFS `2.4.3` declares `Linux-Maximum: 7.0`. Our kernel line is `7.1.8`, and
`config/kernel.m4` turns that cap into a hard `configure` error:

```
*** Cannot build against kernel version 7.1.8-smoothkernel.
*** The maximum supported kernel version is 7.0.
```

Upstream raised the same cap to `7.1` on master in
[PR #18682](https://github.com/openzfs/zfs/pull/18682) ("Linux 7.1 compat:
META"). That PR changed **one line of one file and nothing else** — OpenZFS
required no code changes to support Linux 7.1. It landed 2026-06-17, six days
after the `2.4.3` tag, so it missed the release on timing, not readiness. The
`zfs-2.4-release` branch still carries `7.0`.

## Why not `--enable-linux-experimental`

OpenZFS ships an official escape hatch for exactly this situation, and it does
work for a local build. It is **not** usable here, because SmoothNAS consumes
OpenZFS through `zfs-dkms` (see [`../../docs/DKMS.md`](../../docs/DKMS.md)).

`scripts/dkms.mkconf` hardcodes the `configure` argument list that DKMS runs on
the **target machine** at module-rebuild time:

```
PRE_BUILD="configure
  --disable-dependency-tracking --prefix=/usr
  --with-config=kernel --with-linux=... --with-linux-obj=...
```

The only injectable knobs are `ICP_ROOT`, `ZFS_DKMS_ENABLE_DEBUG` and
`ZFS_DKMS_ENABLE_DEBUGINFO`. There is no hook for arbitrary configure flags, so
a flag passed when we build the `.deb` never reaches the appliance. Every
SmoothNAS box rebuilding `zfs-dkms` against `7.1.8` headers would hit the `7.0`
gate and fail.

Patching `META` puts the raised cap in the packaged source, so it holds on
every target rebuild.

## Verification

OpenZFS `2.4.3` was configured and compiled against a patched Linux `7.1.8`
tree (the full SmoothKernel patch stack, `CONFIG_SCHED_BORE=y`):

- Control, no flag and no patch: `configure` **blocked** with the 7.0 gate
  message above — the gate is real, not advisory.
- With the cap lifted: `configure` OK, `make` OK, **143** modules built.
- Resulting `zfs.ko` reports `vermagic: 7.1.8-smoothkernel SMP preempt
  mod_unload modversions`.
- 16 build warnings, all pre-existing objtool `__noreturn` annotations on
  `spl_panic()` and `luaD_throw()`. **No** implicit-declaration or
  incompatible-pointer warnings — nothing indicating real kernel API drift.

What this does **not** prove: that the modules behave correctly at runtime. A
clean compile is necessary, not sufficient. Pool import/export and an SMB
export path must be exercised on a booted 7.1.8 system before promotion.

## Removal condition

Drop this lane entirely as soon as SmoothKernel moves to an OpenZFS release
whose own `META` declares `Linux-Maximum >= 7.1`. At that point
`ZFS_PATCHSET` should be unset in `examples/*.env`.

Check with:

```sh
curl -fsSL https://github.com/openzfs/zfs/raw/zfs-<version>/META | grep ^Linux-Maximum
```
