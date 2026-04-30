# SmoothKernel Documentation

This directory documents both the current SmoothKernel repository and the
cross-repo contracts that depend on it. The root README is the user-facing entry
point; this file is the maintainer map.

## Read This First

- [BUILDING.md](BUILDING.md): how to build the kernel and OpenZFS packages.
- [KERNEL.md](KERNEL.md): why Smooth* ships one shared kernel.
- [kernel-config.md](kernel-config.md): load-bearing `.config` invariants.
- [PATCHES.md](PATCHES.md): how vendored patch lanes are organized and reviewed.
- [bumping-kernel.md](bumping-kernel.md): step-by-step kernel bump runbook.
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md): common failures and diagnostics.

## Repository Mechanics

- [BUILDING.md](BUILDING.md): build host setup, `build.env`, outputs, and local
  test installs.
- [PATCHES.md](PATCHES.md): patch custody, provenance, refresh rules, and review
  checklist.
- [DKMS.md](DKMS.md): contract for out-of-tree module consumers.
- [CI_RELEASES.md](CI_RELEASES.md): GitHub release workflow, artifacts, and
  release-versus-promotion boundaries.
- [signing.md](signing.md): Secure Boot and module-signing model.

## Platform Architecture

- [ARCHITECTURE.md](ARCHITECTURE.md): SmoothNAS, SmoothRouter, SmoothHTPC, and
  SmoothDesktop on a shared Debian base.
- [APT_REPO.md](APT_REPO.md): apt suite layout, pinning, hosting, and promotion.
- [RELEASE_MODEL.md](RELEASE_MODEL.md): versioning, cadence, soak, rollback, and
  end-of-life policy.
- [GRAPHICS.md](GRAPHICS.md): Mesa, firmware, GPU driver, and 32-bit graphics
  runtime policy.
- [INSTALLERS.md](INSTALLERS.md): shared installer extraction and flavor ISO
  contract.

## Flavor Contracts

- [SMOOTHNAS.md](SMOOTHNAS.md): NAS suite composition, packaging, tuning, and
  ZFS posture.
- [SMOOTHROUTER.md](SMOOTHROUTER.md): router stack, first-boot wizard, daemon
  responsibilities, and security posture.
- [SMOOTHHTPC.md](SMOOTHHTPC.md): HTPC kiosk/session model and `smoothtv`
  responsibilities.
- [SMOOTHDESKTOP.md](SMOOTHDESKTOP.md): KDE Plasma desktop, gaming, Wine, and
  workstation defaults.

## Current Implementation vs Product Contract

Some docs describe the desired production contract for the Smooth* platform, not
only code that exists inside this repository today. When there is a distinction,
the docs should say so explicitly.

Current repository implementation:

- Builds kernel.org source with checked-in patch lanes and config.
- Builds OpenZFS packages from an upstream OpenZFS release.
- Publishes GitHub Release artifacts from `.github/workflows/release.yml`.
- Provides templates for DKMS consumers.

Product-level contract described here:

- The Smooth* apt repository consumes and promotes release artifacts.
- Flavor repositories own their daemons, UIs, meta packages, and smoke tests.
- Signing-capable CI owns release-key custody and promotable signed artifacts.
- Installers own first-boot setup and flavor-specific source enablement.

If a doc makes a production claim that is not implemented yet, prefer language
such as "production contract", "release gate", or "planned owner" over implying
the current script already performs that work.
