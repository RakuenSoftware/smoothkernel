# Patch Stack

SmoothKernel builds from a pristine kernel.org tarball plus patch lanes committed
to this repository. This keeps the kernel source reproducible from git history:
there is no hidden local tree and no dependency on a downstream source checkout
at build time.

## Patch Order

Patches are applied in this exact order:

```text
patches/cachyos-<kernel-version>/
patches/nobara-picks/
patches/post-nobara-<kernel-version>/
```

Within each directory, `*.patch` files are sorted by filename before being
applied. Prefix patches with `0001-`, `0002-`, and so on to make ordering
explicit.

## Lanes

### Base lane: `patches/cachyos-<version>/`

The first lane contains the downstream scheduler/kernel base material for the
specific kernel version. For the current line this is the BORE patch that applies
cleanly to a pristine kernel.org tree.

Do not assume every patch from a downstream project applies to a pristine
kernel.org tarball. Some downstream patchsets are authored against their own
already-modified tree. If a patch depends on hidden source deltas, either rebase
it explicitly or do not carry it.

### Secondary lane: `patches/nobara-picks/`

This lane contains narrow Nobara cherry-picks that are useful across Smooth*
flavors, currently HID/controller improvements. These patches are deliberately
not a full Nobara patch import.

Good candidates:

- Driver-level hardware enablement.
- Patches that have no runtime cost unless matching hardware is present.
- Patches that apply cleanly after the base lane.

Bad candidates:

- Fedora packaging changes.
- Build-system assumptions tied to Nobara's SRPM pipeline.
- Broad desktop policy changes that do not help headless flavors.

### Final lane: `patches/post-nobara-<version>/`

This lane is for local carry patches and rebased follow-ons that must apply
after the secondary lane. It should stay small. A growing final lane is a signal
that we are maintaining too much kernel code ourselves.

## Patch Directory README

Every patch directory should include a README that records:

- Kernel version or version range.
- Patch source and upstream reference.
- Why the patch is carried.
- Any local rebase notes.
- Removal condition.

For small single-purpose lanes, the README can be short. For local carry patches,
include enough context that a maintainer can decide whether to drop or rebase the
patch during the next kernel bump.

## Adding a Patch

1. Choose the correct lane.
2. Name the file with an ordered numeric prefix.
3. Keep the patch in `git format-patch` style when possible.
4. Add or update the lane README.
5. Run `make kernel-config-update-all` if the patch adds or removes Kconfig symbols.
6. Run `make kernel DEB_ARCH=<arch>` for each affected architecture.
7. Install on the relevant hardware path before promotion.

If a patch is hardware-specific, document the hardware tested. If no hardware is
available, document that explicitly and do not treat the patch as fully
validated.

## Refreshing for a Kernel Bump

For a point release:

1. Create the new versioned lane directories.
2. Rebase or replace the base lane for the new kernel.
3. Re-test `nobara-picks`; keep the lane unversioned only while the patches
   continue to apply cleanly across current supported versions.
4. Rebase local carry patches into the new `post-nobara-<version>/` lane.
5. Run `make kernel-config-update-all`.
6. Review the config diff.
7. Run kernel and ZFS builds for each supported architecture.

The full bump process is in [bumping-kernel.md](bumping-kernel.md).

## Review Checklist

Before merging a patch-stack change:

- Does every patch apply to a pristine kernel.org tree after earlier lanes?
- Is the patch source documented?
- Is the reason documented in user/workload terms?
- Is the removal condition known?
- Does the patch affect config symbols, ABI, module names, or userspace APIs?
- Did the maintainer run the affected `make kernel DEB_ARCH=<arch>` builds?
- Did the maintainer run the relevant hardware or flavor smoke test?

## What Not To Carry

Avoid carrying patches that:

- Only improve synthetic benchmarks without a Smooth* workload reason.
- Require a large downstream source base not present in this repo.
- Are security-sensitive and better handled by upstream stable.
- Create per-flavor behavior in the shared kernel.
- Replace a runtime userspace tuning knob with a compile-time fork.

The one-kernel model depends on keeping the patch stack understandable. If a
patch cannot be explained briefly and tested concretely, it probably does not
belong here.
