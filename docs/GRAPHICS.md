# Graphics stack

How the Smooth* family keeps Mesa, firmware, and GPU drivers meaningfully newer than Debian stable ships. Applies to SmoothHTPC and SmoothDesktop; SmoothNAS and SmoothRouter don't pull any of it.

## Why we take ownership

Debian stable freezes Mesa, `linux-firmware`, and sometimes LLVM at release time and then only backports security fixes for ~2 years. That's a feature for servers and a problem for:

- **HTPC** — VA-API / VDPAU / Vulkan-video paths for hardware decode regress on stale Mesa. New codec support (AV1 decode on older GPUs, HEVC 10-bit paths) lands in Mesa continuously.
- **Desktop** — Vulkan 1.3+ features, HDR path, newer GPU families (RDNA3/RDNA4, Intel Arc/Battlemage, NVIDIA Blackwell) need current drivers. Gaming depends on it.
- **Both** — new GPUs need firmware blobs that Debian's `linux-firmware` often lags by months.

We override exactly these three pieces and ride Debian for everything else.

## Package set

All three live in the `common` apt suite (see [`APT_REPO.md`](APT_REPO.md)):

### `linux-firmware-smooth`

Tracks `linux-firmware.git` tip from kernel.org. Rebuilt as Debian drops behind on GPU firmware (typically monthly, sometimes more often when new hardware lands).

- Pure firmware blobs — no code build, just package-and-sign
- Conflicts / Replaces Debian's `firmware-*` and `linux-firmware`
- Small, cheap pipeline

### `mesa`

Rebuilt from upstream Mesa releases using **kisak-mesa**'s Debian packaging as the upstream. Clone kisak-mesa's packaging tree, bump the `MESA_VER`, rebuild in CI. Not a fork — a same-packaging rebuild.

Produces the full Debian mesa package graph (~20 binaries):

- `libgl1-mesa-dri`, `libegl-mesa0`, `libglx-mesa0`
- `mesa-vulkan-drivers`, `mesa-va-drivers`, `mesa-vdpau-drivers`
- `libgbm1`, `libglapi-mesa`
- `-dev` and `-dbgsym` variants

Override mechanism: apt pin on `Package: libgl1-mesa-* libegl* libglx-mesa* mesa-* libgbm1 libglapi-mesa` pointing at `o=RakuenSoftware, a=common` at priority 1001 (see [`APT_REPO.md`](APT_REPO.md)).

### `smooth-gfx` (meta)

Metapackage that pulls the full graphics set + firmware + non-free driver integrations. Both HTPC and desktop depend on this through `smooth-workstation`:

```
Depends:
 mesa-vulkan-drivers,
 mesa-va-drivers,
 mesa-vdpau-drivers,
 libgl1-mesa-dri,
 libegl-mesa0,
 libglx-mesa0,
 libgbm1,
 linux-firmware-smooth,
 intel-media-va-driver-non-free | intel-media-va-driver,
 vulkan-tools
```

NVIDIA handled separately — see below.

### 32-bit userspace for gaming and Wine

SmoothDesktop and SmoothHTPC are first-class Steam / Proton / Wine systems, so the graphics story is not complete with amd64 packages alone.

When those flavors enable `i386`, `smooth-workstation` also pulls the matching 32-bit graphics runtime alongside the native one:

- `libgl1-mesa-dri:i386`
- `libglx-mesa0:i386`
- `libgbm1:i386`
- `mesa-vulkan-drivers:i386`

That keeps the 32-bit OpenGL / Vulkan userspace aligned with the Rakuen-built Mesa stack rather than silently falling back to Debian's older i386 graphics packages.

## LLVM dependency

Mesa's RADV, RadeonSI, and llvmpipe link against LLVM. Mesa's LLVM version requirement bumps with each major Mesa release. Our posture:

- **Today (Debian 13 / trixie):** Debian ships `llvm-19`. Current Mesa releases through at least mid-2026 target LLVM 18/19. We depend on Debian's `libllvm19` — no override needed.
- **When Mesa outgrows Debian's LLVM:** add an `llvm` pipeline to the `common` suite. This is a significant new build (~1h) with complex packaging. We don't do this speculatively; we do it when Mesa demands it.

The "LLVM bump forced on us" event is the single biggest hidden cost in the graphics stack. Budget for it when it arrives; don't preempt.

## NVIDIA

Separate track, separate pipeline.

- **Open kernel modules** (for RTX 20+, increasingly preferred) — Debian packages them; we don't need to fork.
- **Proprietary userspace** (`nvidia-driver-*`) — Debian ships via `non-free`; we can either:
  - (a) Tell users to enable Debian's `non-free` in their `sources.list`. Simpler; one fewer thing we maintain.
  - (b) Mirror the relevant `nvidia-driver-*` packages into our `common` suite as a convenience. More maintenance; fewer steps for users.

Leaning (a) at v1 — Debian's non-free is well-maintained, and the Smooth* value-add isn't repackaging NVIDIA.

DKMS modules build against `linux-smoothkernel-headers` automatically once installed. No special glue needed.

## Intel

`intel-media-va-driver-non-free` (the iHD driver) comes from Debian's non-free section. Required for current Intel GPU video decode (Arc, Battlemage, 11th-gen+ iGPUs with new codec support). Pulled by `smooth-gfx` as a recommends with a fallback to `intel-media-va-driver` (older, in main).

## Cadence

| Package | Cadence | Trigger |
|---|---|---|
| `mesa` | Quarterly majors (25.0, 25.1, ...) + point releases | Upstream tag |
| `linux-firmware-smooth` | ~Monthly | Debian lags a firmware blob we need for a supported GPU |
| NVIDIA mirror (if we do it) | Per Debian `nvidia-driver-*` update | Debian push |
| LLVM | Case-by-case | Mesa requirement bumps past Debian |

Rebuilds go through the same testing → main promotion as the kernel. A broken Mesa rebuild is user-visible within a session (GPU apps fail to start); needs a rollback plan. See [`RELEASE_MODEL.md`](RELEASE_MODEL.md).

## What's not in scope here

- **Flatpak runtime Mesa** — Flatpak apps carry their own Mesa via the Freedesktop runtime; we don't need to update that. Helps apps in Flatpak but doesn't help native Kodi/system graphics.
- **Userspace GL/Vulkan loaders** — `libvulkan1`, `libegl1`, `libgl1` (the vendor-neutral loaders) come from Debian; no override needed.
- **Wayland compositors** — `kwin` (on desktop), `cage` (on HTPC), `wlroots` — pulled unchanged from Debian. Mesa changes independently of these.

## Open questions

- **Stable vs development Mesa channel.** Stick to upstream stable branches (25.0.x, 25.1.x point releases). `main`-branch Mesa is too churn-y for a shipped product. Re-evaluate only if a specific feature is stable-only-after-six-months.
- **AMDVLK.** We don't ship it. RADV (in Mesa) is the default Vulkan driver for AMD; AMDVLK is a corner case. If real demand appears, package it separately — don't bundle.
