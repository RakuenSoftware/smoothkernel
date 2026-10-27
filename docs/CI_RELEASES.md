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

## Versions

Every build has a build number: the commit count of the built commit
(`recipes/build-number.sh`). It names the kernel and versions every package,
so each build of `main` is distinct and newer than the last:

| Package | Example (kernel 7.2.10, build 68) |
|---|---|
| `linux-image-<release>` | `linux-image-7.2.10-68-smoothkernel_7.2.10-68_amd64.deb` |
| `linux-headers-<release>` | `linux-headers-7.2.10-68-smoothkernel_7.2.10-68_amd64.deb` |
| `linux-libc-dev` | `linux-libc-dev_7.2.10-68_amd64.deb` |
| `linux-image-smoothkernel` (metapackage) | `linux-image-smoothkernel_7.2.10-68_amd64.deb` |
| `linux-headers-smoothkernel` (metapackage) | `linux-headers-smoothkernel_7.2.10-68_amd64.deb` |
| OpenZFS | `zfs_2.4.4-68_amd64.deb`, `zfs-dkms_2.4.4-68_amd64.deb`, ... |

The kernel release (`uname -r`) is `7.2.10-68-smoothkernel`, so a new build
installs alongside the running kernel rather than replacing its modules, and
the previous kernel stays bootable. Systems install the two metapackages, each
of which depends on exactly its build's package, so `apt upgrade` moves them to
every new build. Old kernels are removed by `apt autoremove`, which keeps the
running and newest ones. The versioned headers package also `Provides:
linux-headers`, for DKMS packages that depend on the generic name.

The DKMS module version of OpenZFS stays the upstream version (`2.4.4`); only
the package revision carries the build number.

## Build Steps

The workflow:

1. Checks out the repository.
2. Installs build dependencies.
3. Copies `examples/smooth.env` to `build.env`.
4. Runs `make kernel` for amd64 on `ubuntu-24.04` and arm64 on `ubuntu-24.04-arm`.
5. Runs `make zfs` for each architecture.
6. Uploads per-architecture package artifacts.
7. Merges amd64 and arm64 packages into `dist/`, skipping duplicate `_all.deb` assets.
8. Writes `dist/SHA256SUMS`.
9. Writes `dist/manifest.json` with artifact architectures and sha256 values.
10. Attests the build provenance of every `.deb` (see below).
11. Publishes a GitHub Release with `.deb`, checksum, and manifest assets.

## Provenance

Every published `.deb` carries a GitHub build-provenance attestation: a
statement signed through Sigstore and recorded in its public transparency log
that ties the package's SHA-256 to this repository, the workflow, and the
commit it was built from. Anyone can check a package, whether it came from a
GitHub Release or from the Smooth* apt repository:

```sh
gh attestation verify linux-image-7.2.10-68-smoothkernel_7.2.10-68_amd64.deb \
    --repo RakuenSoftware/smoothkernel
```

The apt repository publishes these packages byte for byte as released, so the
checksums in its indices are the attested ones. Nothing downstream rebuilds,
re-signs or re-versions a SmoothKernel package.

## Manifest

`manifest.json` exists so consumers do not need to parse filenames to discover
release contents. It records:

- Release tag.
- Kernel version.
- ZFS version.
- Build number and kernel release (`uname -r`).
- Git commit.
- Supported architectures.
- Artifact names, Debian architecture suffixes, and sha256 values.

The manifest is an artifact inventory, not a statement of provenance; that is
what the attestations are.

## GitHub Release vs Apt Promotion

A GitHub Release means "the repository built these artifacts." It does not by
itself mean "these artifacts are promoted to users."

Promotion to the Smooth* apt repository requires:

- A valid build-provenance attestation for every package, from this
  repository's release workflow. The apt repository checks it before
  ingesting a package.
- Representative flavor smoke tests.
- Apt repository indexing and signed `Release` / `InRelease` metadata.

Signing is not required: an unsigned release is promoted like a signed one and
runs only with Secure Boot off (see [signing.md](signing.md)).

The apt repository is the user-facing distribution mechanism. GitHub Releases
are useful for builders, downstream automation, and pre-promotion testing.

## Signing Boundary

This repository must not store private module-signing keys. When signing
material is provisioned, [signing.md](signing.md) has release-built modules
signed by controlled CI signing material and DKMS modules signed on-host.

Without it, CI builds unsigned kernels, marked with `UNSIGNED.txt`, which run
only with Secure Boot off. Local developer builds are for bring-up and smoke
testing only; only CI-built packages are promoted.

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
