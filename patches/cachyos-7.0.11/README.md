# cachyos-7.0.11

Vendored base-lane patches applied first to a pristine kernel.org `7.0.11`
tree. Source: [`CachyOS/kernel-patches`](https://github.com/CachyOS/kernel-patches)
`7.0/` (`sched/` and `misc/`).

Current contents (apply in order):

- `0001-bore.patch` — BORE scheduler (`7.0/sched/0001-bore.patch`).
- `0002-acpi-call.patch` — `acpi_call` module (`7.0/misc/0001-acpi-call.patch`),
  used by fan-control / charge-threshold userspace on laptop, desktop, and
  handheld hardware. New out-of-tree-style module: no runtime effect unless a
  tool drives `/proc/acpi/call`.
- `0003-rt-i915.patch` — low-latency / RT tweaks for the Intel i915 display
  path (`7.0/misc/0001-rt-i915.patch`). Aligns with SmoothKernel's
  latency-oriented defaults; no effect on non-Intel-graphics hardware.

All three apply cleanly to a pristine kernel.org `7.0.11` tarball and were
verified together with the `nobara-picks` and `post-nobara-7.0.11` lanes.

As with the previous line, this lane uses the kernel.org-applicable
`0001-bore.patch`, **not** `0001-bore-cachy.patch`: `bore-cachy` expects
additional CachyOS scheduler deltas that are not present in a pristine
kernel.org tree.

## Deliberately not vendored from CachyOS `7.0/misc`

These were evaluated for the expanded ingest and excluded:

- `0001-cgroup-vram.patch` — does not apply to a pristine tree (authored against
  the already-modified CachyOS tree; hunks 1 and 8 fail). Revisit if a clean
  rebase becomes available — it is the desktop/HTPC VRAM-accounting feature and
  is a good future candidate.
- `0001-handheld.patch` — 107-file handheld-platform bundle that does not apply
  to a pristine tree; far broader than the Smooth* hardware surface.
- `0001-hardened.patch` — hardening series; security policy is left to upstream
  stable per `docs/PATCHES.md`. Does not apply to a pristine tree.
- `0001-aufs-*.patch`, `0001-clang-polly.patch`, `dkms-clang.patch`,
  `nvidia/` — niche filesystem / clang-build-only / NVIDIA-DKMS material not
  relevant to the shared gcc-built kernel. NVIDIA is a conditional lane handled
  in the consuming repos.
