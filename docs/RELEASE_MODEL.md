# Release model

Versioning, cadence, and promotion for the Smooth* family.

## Versioning

### Overridden packages (kernel, mesa, firmware)

```
<upstream-version>+smooth<N>~<codename><R>
```

- `upstream-version` — kernel.org / Mesa upstream release, unmodified
- `smooth<N>` — our rebuild iteration for a given upstream version (1, 2, 3 as we re-spin for packaging fixes)
- `~codename` — Debian codename the build targets (`trixie`, later `forky`)
- `<R>` — revision within a codename target (1, 2, ...)

Examples:

```
linux-smoothkernel_6.18.22+smooth1~trixie1_amd64.deb
mesa-vulkan-drivers_25.2.3+smooth2~trixie1_amd64.deb
linux-firmware-smooth_20260315+smooth1~trixie1_all.deb
```

The `+smooth` marker is deliberately chosen so Debian apt sees our version as strictly greater than `6.18.22-1` (plain Debian packaging).

### Rakuen-authored packages (daemons, UIs, meta, tuning)

```
<semver>~<codename><R>
```

Example: `tierd_1.4.0~trixie1_amd64.deb`

Semver applies because we own the versioning.

### Meta and tuning packages

Lockstep version with their containing flavor's current release (e.g. `smoothnas_2026.04.1~trixie1_all.deb`). Date-based because their cadence is flavor-level, not package-level.

## Cadences

| Package set | Expected cadence | Trigger |
|---|---|---|
| `linux-smoothkernel` | per kernel point release (~weekly) | CachyOS publishes patch series |
| `mesa` | quarterly majors + point releases | Upstream Mesa tag |
| `linux-firmware-smooth` | ~monthly | Debian lags a blob we need |
| `kodi` (if we override) | yearly | Upstream major + critical points |
| Flavor meta + tuning | as needed | Composition change or tuning revision |
| Rakuen-authored (tierd, smoothrouter daemon, smoothtv) | per semver bump | Normal product cadence |

Kernel is the fastest-moving; expect a kernel PR every 1–2 weeks. Everything else is slower.

## Promotion

### v1 (now)

Single `main` component per suite. CI builds a .deb, signs it, commits to `apt-repo`, GitHub Pages publishes, users `apt upgrade` the next time they check. No staging.

Right posture for where we are — small user base, direct deployment path, rollback is "revert the commit in apt-repo."

### v2 (when pain justifies)

Introduce a `testing-<suite>` tree mirrored alongside each production suite. CI lands all builds in testing first; a promotion script copies approved package versions into the production suite after a soak period.

Triggers for moving to v2:

- We ship a broken kernel to users more than once.
- Rebase cadence exceeds our ability to hand-validate.
- External testers / beta users exist who want "bleeding" vs "stable" channels.

Not preemptive. Operational pain is the forcing function.

## Soak and rollback

Today, the soak strategy is:

1. Produce a CI-signed candidate build.
2. Install on the minimum validation matrix: one NAS target, one router target, one HTPC target, one desktop target.
3. Boot, run flavor-specific smoke tests (mount a ZFS pool for NAS; pass traffic for router; run Kodi video decode for HTPC; boot into Plasma and launch Steam for desktop).
4. If clean, commit the .deb to apt-repo.

Rollback: git revert in apt-repo, re-run publish. Users on stale versions are unaffected; users who upgraded get the old version back on next `apt upgrade` if we leave it — otherwise we need to ship a `.deb` with an epoch bump to force a downgrade, which is painful. Prefer "never publish known-broken" over "rollback fast."

Per-flavor smoke test checklists will live in each flavor's repo (`SmoothNAS/docs/OPERATIONS.md` is the model).

## End-of-life for old kernels

Default: drop old `linux-smoothkernel` versions from the pool as soon as the new one is published, with one 7-day overlap so a user who `apt upgrade`d into a bad kernel can pin back to the prior version for a week while we fix forward.

Longer retention only if we hit chronic regressions requiring users to hold at a specific version.

## Cross-flavor version alignment

We don't enforce a single "Smooth* family release number." Each package versions independently. A flavor's user experience is defined by:

- The `common` packages (kernel, mesa, firmware, smooth-base) they currently have installed
- The flavor suite's packages

When we do want to identify a coherent "this is what a fresh install looks like right now" snapshot, we tag it at the ISO level — e.g. `smoothnas-2026.04.15-amd64.iso` captures a specific combination of common + smoothnas suite package versions.

## Supported upgrade paths

- Within a Debian base (trixie → trixie): continuous via `apt upgrade`. Always supported.
- Across Debian bases (trixie → forky, eventually): major operation. Requires updating sources.list, accepting breaking package changes, possibly reinstalling some non-free bits. Same UX as plain Debian's `do-release-upgrade`-equivalent.

Not a v1 problem.

## Deprecation

When we remove a package from the repo:

1. Announce in release notes for the relevant flavor.
2. Leave the package in the pool for one more cycle so auto-updaters don't fail.
3. Then remove.

Hard deprecations (licensing, security) skip the grace cycle.

## Open questions

- **Release notes discipline.** Where do they live? Markdown files in the apt-repo itself, or per-flavor in each product repo? Leaning per-flavor for product-specific notes, cross-cutting kernel/mesa notes in `smoothkernel`.
- **Hotfix kernels.** A security issue lands mid-cycle — do we rebase out-of-band or wait for the next CachyOS series? Policy: rebase out-of-band, only with CachyOS's patch series (not self-maintained).
- **Dependency freeze for flavor suites.** Currently we assume trixie-stable deps for daemon packages (tierd etc.). When trixie point releases break source-incompatibility (rare but happens), rebuild vs. pin Debian point release. Defer until it bites.
