# CI and Releases

This repository contains a GitHub Actions release workflow at
[../.github/workflows/release.yml](../.github/workflows/release.yml). The
workflow builds kernel and OpenZFS packages, stages checksums and a manifest,
and publishes GitHub Release assets.

## Triggers

The workflow runs on:

- Pushes to `main`.
- Tags matching `v*`.
- Manual `workflow_dispatch`.

Pushes to `main` produce prerelease tags in this shape:

```text
v<kernel-version>-<short-sha>
```

Tag pushes produce stable GitHub releases at the pushed tag.

## Build Steps

The workflow:

1. Checks out the repository.
2. Installs build dependencies.
3. Copies `examples/smooth.env` to `build.env`.
4. Runs `make kernel`.
5. Runs `make zfs`.
6. Copies `out/*.deb` to `dist/`.
7. Writes `dist/SHA256SUMS`.
8. Writes `dist/manifest.json`.
9. Publishes a GitHub Release with `.deb`, checksum, and manifest assets.

## Manifest

`manifest.json` exists so consumers do not need to parse filenames to discover
release contents. It records:

- Release tag.
- Kernel version.
- ZFS version.
- Git commit.
- Artifact names and sha256 values.

Consumers should still verify package signatures and apt repository metadata
when installing from the Smooth* apt repo. The GitHub Release manifest is an
artifact inventory, not a substitute for apt trust.

## GitHub Release vs Apt Promotion

A GitHub Release means "the repository built these artifacts." It does not by
itself mean "these artifacts are promoted to users."

Promotion to the Smooth* apt repository requires:

- Release-grade provenance checks.
- Signing requirements from [signing.md](signing.md).
- Representative flavor smoke tests.
- Apt repository indexing and signed `Release` / `InRelease` metadata.

The apt repository is the user-facing distribution mechanism. GitHub Releases
are useful for builders, downstream automation, and pre-promotion testing.

## Signing Boundary

This repository must not store private module-signing keys. The production
contract in [signing.md](signing.md) requires release-built modules to be signed
by controlled CI signing material and DKMS modules to be signed on-host.

If the GitHub workflow is used for promotable artifacts, it must be wired to the
approved signing mechanism before promotion. Local developer builds and unsigned
CI builds are acceptable for bring-up and smoke testing, but they are not final
Secure-Boot release artifacts.

## Failure Handling

Common CI failures:

- Kernel tarball download or checksum failure.
- Patch no longer applies.
- New config symbol causes `olddefconfig` or build failure.
- Kernel build exceeds timeout.
- OpenZFS release does not support the selected kernel.
- Artifact glob finds fewer packages than expected.

Start with [TROUBLESHOOTING.md](TROUBLESHOOTING.md), then inspect the failed
step log. Patch and config failures are usually local to the kernel bump. ZFS
failures usually mean the selected kernel outran OpenZFS compatibility.

## Release Notes

GitHub Releases currently use generated release notes. For user-facing apt
promotion, maintainers should add explicit release notes covering:

- Kernel version.
- Patch lane changes.
- Config changes.
- ZFS version.
- Hardware fixes or regressions.
- Required validation matrix.
- Rollback notes.

Cross-cutting kernel/Mesa notes belong in SmoothKernel or the apt repo. Flavor
product notes belong in each flavor repository.
