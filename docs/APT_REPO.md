# Apt repo model

Companion doc to [`../../apt-repo/README.md`](../../apt-repo/README.md), which covers the concrete mechanics (signing, scripts, GitHub Pages deploy). This doc covers the design: suite layout, component choices, pinning, promotion.

## Suite layout

Five suites, all signed by the same key, all served from the same origin:

| Suite | Purpose |
|---|---|
| `common` | Packages shared across flavors: `linux-smoothkernel`, `linux-smoothkernel-headers`, `mesa` (full Debian-equivalent package set), `linux-firmware-smooth`, `smooth-base`, `smooth-gfx`, `smooth-workstation`, `smoothgui-assets`, `smooth-installer` artifacts |
| `smoothnas` | NAS-specific: `smoothnas` meta, `smoothnas-tuning`, `tierd`, `tierd-ui`, `smoothfs` (DKMS), optional NAS-only helpers |
| `smoothrouter` | Router-specific: `smoothrouter` meta, `smoothrouter-tuning`, `smoothrouterd`, `smoothrouter-ui`, `smoothrouter-setup` (first-boot wizard) |
| `smoothhtpc` | HTPC-specific: `smoothhtpc` meta, `smoothhtpc-tuning`, `smoothtv`, HTPC-specific helpers |
| `smoothdesktop` | Desktop-specific: `smoothdesktop` meta, `smoothdesktop-tuning`, `smoothdesktop-theme` |

Every flavor's `sources.list` enables `common` plus the flavor's own suite:

```
deb [signed-by=/etc/apt/keyrings/smooth-archive-keyring.gpg] https://<repo> common main
deb [signed-by=/etc/apt/keyrings/smooth-archive-keyring.gpg] https://<repo> smoothnas main
```

`smooth-base`'s `postinst` writes both lines on install; users never hand-edit.

## Component: `main` only

Flat component per suite. No `contrib` / `non-free` split internal to the Smooth* repo.

Rationale: the `main`/`contrib`/`non-free` distinction is a Debian-project artifact about the project's free-software guidelines. It doesn't add value for a vendor repo where we pick and sign every package ourselves. Non-free-licensed inclusions (firmware, NVIDIA driver mirror) are covered by the enabled-by-default `non-free-firmware` component on the Debian base, not by an internal split here.

If we later need a pre-promotion staging component, introduce a `testing` suite (not component) — see "Promotion" below.

## Architecture: amd64-only at v1

Matches the existing `apt-repo/README.md`. Arm64 is a deferred addition; the kernel build would be the largest new pipeline to stand up for it.

## Pinning

`smooth-base` ships `/etc/apt/preferences.d/10-smooth-overrides`:

```
Package: linux-image-smoothkernel* linux-headers-smoothkernel* linux-libc-dev-smoothkernel linux-firmware-smooth
Pin: release o=RakuenSoftware, a=common
Pin-Priority: 1001

Package: libgl1-mesa-* libegl* libglx-mesa* mesa-* libgbm1 libglapi-mesa
Pin: release o=RakuenSoftware, a=common
Pin-Priority: 1001
```

Priority > 1000 means RakuenSoftware's version wins even if Debian's version string happens to be higher (unlikely but defensive). The `o=` field comes from the signed `Release` file; set it explicitly in `dists/*/Release` to `RakuenSoftware`.

Everything else (Samba, nginx, etc.) is left at Debian's priority — we explicitly *want* Debian stable for those.

## Upstream-matched versioning

Overriding packages must have version strings that Debian's apt accepts as "newer or equal" to whatever Debian ships. Convention:

```
<upstream-version>+smooth<N>~<codename>
```

Examples:

- `mesa` at upstream 25.2.3, our 2nd rebuild on trixie → `25.2.3+smooth2~trixie1`
- `linux-smoothkernel` at 6.18.22 with 1 patch series iteration → `6.18.22+smooth1~trixie1`

This keeps our version strictly greater than Debian's (`25.2.3` alone or `25.2.3-1`) while leaving room for re-releases (`+smooth2`) and codename tagging (`~trixie`) for future parallel channels.

## Promotion

v1 (now): one suite per flavor, `main` component, direct publish. Matches the existing `apt-repo` shape.

v2 (when rebase pain justifies it): introduce a `testing` suite tree mirrored from `common`/`smoothnas`/etc. CI builds land in `testing-<suite>`; soak for N days; a promotion script copies approved packages across. Keeps the producer-side simple while letting us de-risk kernel bumps.

The promotion machinery is non-trivial (needs to preserve signatures or re-sign). Defer until we're shipping to more than test boxes.

## Signing and key custody

Already addressed in `apt-repo/README.md` (Section: One-time setup). Single signing key, stored as GitHub repo secret `APT_SIGNING_KEY`. Key-id as `APT_SIGNING_KEY_ID`. Public half served as `public-key.asc` from the repo root; consumers dearmor into `/etc/apt/keyrings/smooth-archive-keyring.gpg`.

Not changing this — the existing shape is fine.

## Hosting

GitHub Pages (current). Mirrorable to any static HTTP server — `dists/` is committed, so a `git clone` into `/var/www/apt-repo` is a complete mirror. No server-side build needed.

Production will eventually want:

- A stable custom domain (`apt.rakuensoftware.com`)
- CDN in front (Cloudflare works with GitHub Pages)
- HTTPS enforced (GitHub Pages provides this)

Out of scope until we ship to real users.

## Out-of-tree modules and DKMS

DKMS modules (`zfs-dkms`, `smoothfs`-via-DKMS, NVIDIA if we mirror it) build against `linux-smoothkernel-headers` on install. They live in `common` so every flavor can pull them; flavor meta-packages declare Depends on only the modules they actually need.

- `smoothnas` depends on `zfs-dkms`, `smoothfs`
- `smoothrouter` depends on neither
- `smoothhtpc`, `smoothdesktop` may depend on NVIDIA driver packages conditionally (handled via Recommends + install-time detection)

## External apt sources

Some flavors need upstream third-party apt repos for packages we deliberately don't rebuild ourselves. `smooth-base`'s `postinst` adds them selectively on the right flavors:

| Source | Added by | Suite | Purpose |
|---|---|---|---|
| **WineHQ** (`dl.winehq.org/wine-builds/debian`) | `smooth-base` postinst when `smoothdesktop` is present | `winehq-stable` | Current upstream Wine; Debian's lags by months. See [`SMOOTHDESKTOP.md`](SMOOTHDESKTOP.md). |
| **Flathub** (`flathub.org`) | `smoothdesktop-theme` postinst | — | App availability for Discover / `flatpak install`. Not apt. |

Each added repo has its signing key dropped under `/etc/apt/keyrings/` with a corresponding `signed-by=` entry in `sources.list.d/` — never `apt-key add`, which is deprecated.

Adding a new external apt source is a design decision with a maintenance cost (we depend on the third party not breaking us). Before adding, ask whether we should instead rebuild the package into `common`. External sources win when:

- The upstream is a trustworthy first-party (WineHQ, Flathub)
- The rebuild cost would be high (Wine has a large build surface)
- The upstream already provides Debian packages for our target codename

## What `common` must not contain

Nothing flavor-specific. If a package's only consumer is one flavor, it belongs in that flavor's suite, not `common`. `common` is for cross-cutting infrastructure only; keeping it lean avoids apt update overhead on flavors that don't need the package.

## Open questions

- **Reproducibility.** Target reproducible builds for `linux-smoothkernel` and `mesa` so third parties can verify our binaries match our source. Not a v1 blocker but should be designed in.
- **EOL and kernel point-release churn.** Do we keep old kernel versions in `common` or drop immediately? Leaning drop-immediately, with a 7-day overlap for rollback.
