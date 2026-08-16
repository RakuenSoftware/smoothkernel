# cachyos-7.1.8

Vendored base-lane patches applied first to a pristine kernel.org `7.1.8`
tree. Source: [`CachyOS/kernel-patches`](https://github.com/CachyOS/kernel-patches)
`7.1/` (`sched/` and `misc/`).

Current contents (apply in order):

- `0001-bore.patch` — BORE scheduler (`7.1/sched/0001-bore.patch`, BORE
  `6.6.3`). **Carries a local rebase — see below.**
- `0002-acpi-call.patch` — `acpi_call` module (`7.1/misc/0001-acpi-call.patch`),
  used by fan-control / charge-threshold userspace on laptop, desktop, and
  handheld hardware. New out-of-tree-style module: no runtime effect unless a
  tool drives `/proc/acpi/call`.
- `0003-rt-i915.patch` — low-latency / RT tweaks for the Intel i915 display
  path (`7.1/misc/0001-rt-i915.patch`). Aligns with SmoothKernel's
  latency-oriented defaults; no effect on non-Intel-graphics hardware.

`0002` and `0003` are byte-identical to the `7.0` lane files they replace.

As with the previous line, this lane uses the kernel.org-applicable
`0001-bore.patch`, **not** `0001-bore-cachy.patch`: `bore-cachy` expects
additional CachyOS scheduler deltas that are not present in a pristine
kernel.org tree.

## Local rebase: `0001-bore.patch`

Upstream CachyOS `7.1/sched/0001-bore.patch` was authored against `7.1-rc1`
(committed 2026-05-04, "7.1: Add BORE 6.6.3") and has **not** been refreshed
for later `7.1.x` point releases. Upstream BORE
([`firelzrd/bore-scheduler`](https://github.com/firelzrd/bore-scheduler))
likewise only ships `0001-linux7.1-rc1-bore-6.6.3.patch` for this line, so
there was no newer upstream revision to take instead.

Against a pristine `7.1.8` tree the patch failed 1 of 21 hunks — hunk 19,
in `kernel/sched/fair.c`:

- The upstream hunk inserts the BORE burst-restart block after a
  `util_est_update(&rq->cfs, p, flags & DEQUEUE_SLEEP);` context line in
  `dequeue_task_fair()`.
- That call no longer exists in `7.1.8`; `dequeue_task_fair()` now goes
  straight from the `util_est_dequeue()` block to `dequeue_entities()`.

The rebase drops the stale context line and adjusts the hunk header count
(`-7410,6` → `-7410,5`). The inserted BORE block is unchanged, and it still
lands **before** `dequeue_entities()` — the ordering the block requires, since
`dequeue_entities()` removes the entity that `restart_burst_bore()` reads.
No BORE behaviour is changed by the rebase.

Removal condition: drop this note and re-vendor verbatim once CachyOS (or
upstream BORE) publishes a `7.1` series rebased onto a current `7.1.x`.
Re-check on every bump — if the stale `util_est_update` context reappears
upstream, take theirs.

## Verification

All three patches were applied, in order, to a pristine kernel.org `7.1.8`
tarball (sha256 `ff01dcb449279d5b4cfccdb01fee639cf5ff1803f1749a77844dd33915422c49`,
verified against `sha256sums.asc`), together with the `nobara-picks` and
`post-nobara-7.1.8` lanes. Results:

- `0001-bore.patch` — applies clean (after the local rebase above).
- `0002-acpi-call.patch` — applies clean.
- `0003-rt-i915.patch` — applies with **fuzz 1** on hunk 3
  (`drivers/gpu/drm/i915/display/intel_crtc.c`, offset 45 lines). Accepted;
  re-check on the next bump, as fuzz is how a patch reports that upstream is
  drifting underneath it.

## Deliberately not vendored from CachyOS `7.1/misc`

These are the remaining files in the current `7.1/misc` listing, all excluded:

- `0001-handheld.patch` — large handheld-platform bundle; far broader than the
  Smooth* hardware surface.
- `0001-aufs-7.1-merge-v20260713.patch` — niche filesystem material.
- `0001-clang-polly.patch`, `dkms-clang.patch` — clang-build-only; the shared
  kernel is gcc-built.
- `nvidia/` — NVIDIA DKMS material; NVIDIA is a conditional lane handled in the
  consuming repos.

Note for anyone diffing against the `7.0` lane README: `0001-cgroup-vram.patch`
and `0001-hardened.patch` were listed there as excluded, but they are **no
longer present** in the upstream `7.1/misc` directory at all, so they are not
carried forward as exclusions. `cgroup-vram` was flagged in the `7.0` notes as
a good future candidate for desktop/HTPC VRAM accounting — if it returns
upstream for a later line, re-evaluate it then.
