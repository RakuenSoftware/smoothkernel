# cachyos-7.2.10

Base lane for pristine kernel.org Linux `7.2.10`, refreshed from
[CachyOS/kernel-patches](https://github.com/CachyOS/kernel-patches/tree/17bb0bb818d283d0dc6e0280a2e9d5b95e66808b/7.2)
at commit `17bb0bb818d283d0dc6e0280a2e9d5b95e66808b` (2026-10-04).

Apply in order:

- `0001-bore.patch`: standalone BORE scheduler from `7.2/sched/0001-bore.patch`.
  Vendored verbatim; the 7.1 stale-context rebase is no longer needed.
  `bore-cachy` still assumes additional CachyOS source deltas and is not used.
- `0002-acpi-call.patch`: verbatim `7.2/misc/0001-acpi-call.patch`;
  enabled as a module on x86 by the existing profile.
- `0003-rt-i915.patch`: `7.2/misc/0001-rt-i915.patch`, with context refreshed
  against 7.2.10. The upstream intel_crtc.c hunk 3 applied with fuzz 1;
  the refreshed patch applies with fuzz 0. No inserted/deleted code changed.

Verification: applied in build-recipe order with the Nobara and post-Nobara
lanes to Linux `7.2.10.tar.xz`, SHA256 `2feaa70453e91f541be6a5c9078d8168e081af45a3d9718054850538cff2ebf3`,
checked against kernel.org's checksum manifest. Both architecture configs
were regenerated. Local object/module build results and pending package/runtime
gates are recorded in `docs/validation/7.2.10.md`.

The upstream 7.2 misc lane also contains handheld, hardened, aufs, clang-DKMS,
and NVIDIA material. These remain outside the existing standalone GCC base
lane: platform bundles, alternative hardening policy/filesystems, or tooling
for optional downstream builds. They are not imported as part of this refresh.
Revisit them when the corresponding hardware or build profile is supported.

Removal: refresh this lane on the next point bump; replace the i915 context
refresh with upstream verbatim when it applies without fuzz.
