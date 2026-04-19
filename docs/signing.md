# Module signing

Shipped Smooth* systems support Secure Boot without giving up DKMS-delivered modules such as ZFS, `smoothfs`, or NVIDIA.

The design uses two trust domains because the module sources come from two places:

- **Rakuen release key** for modules shipped inside release-built packages such as `linux-smoothkernel`
- **Per-host MOK key** for modules built on the target system by DKMS

## v1 trust model

### 1. Release-built modules

`linux-smoothkernel` release builds are produced in CI with a Rakuen-controlled module-signing key.

- Private key lives in KMS / HSM-backed CI secrets, never in git and never on developer laptops
- Public certificate is injected into the kernel build so shipped kernel modules trust the release key out of the box
- Any prebuilt out-of-tree module package we ever publish follows the same rule

This keeps centrally-built packages loadable under Secure Boot without per-machine customization.

### 2. DKMS-built modules

DKMS modules are signed on the target machine after each build.

- Installer or first-boot bootstrap generates a per-host Machine Owner Key (MOK) keypair
- Private key is stored root-only under `/var/lib/smooth-secureboot/`
- Public half is enrolled with `mokutil`
- DKMS post-build hooks sign every built `.ko` with `scripts/sign-file`

The per-host key never leaves the machine. If one host is compromised, the blast radius is one host.

### 3. Owning package

`smooth-secureboot` is the shared package that owns:

- host MOK key generation
- `mokutil` enrollment flow
- DKMS signing hooks
- status / diagnostic commands for checking signer state

Every flavor can depend on it without changing the one-kernel model.

## Boot and enrollment flow

Initial install on Secure-Boot-capable systems:

1. Installer lays down the OS and installs `smooth-secureboot`
2. `smooth-secureboot` generates the per-host MOK keypair
3. Installer queues MOK enrollment with `mokutil --import`
4. First reboot enters the standard MOK enrollment screen
5. Subsequent DKMS rebuilds sign modules automatically with the enrolled key

Headless flavors still use the same mechanism; the console flow is part of the appliance bring-up checklist.

## Kernel configuration contract

The shipped kernel posture is:

- `CONFIG_MODULE_SIG_FORCE=y`
- release builds inject the Rakuen module-signing certificate at build time
- revocation keys remain explicitly managed rather than inherited from Debian packaging defaults

The checked-in `.config` does not hard-code private material or machine-local paths.

## Build and release flow

Developer builds are allowed to use local throwaway keys for bring-up, but only CI-produced release artifacts are promotable to the apt repo.

Release build flow:

1. CI fetches signing material from KMS / HSM-backed secret storage
2. Kernel build signs packaged modules with the Rakuen release key
3. Resulting `.deb`s are published to the apt repo
4. Test boxes enrolled with `smooth-secureboot` verify that DKMS consumers (`zfs-dkms`, `smoothfs`, optional NVIDIA) rebuild and load successfully

## Verification

Minimum verification before publish:

- `modinfo -F signer` on a packaged module from `linux-smoothkernel`
- `modinfo -F signer` on a DKMS-built module such as ZFS
- successful module load on a Secure-Boot-enabled test machine
- negative test: unsigned ad-hoc module load is rejected

## Operational notes

- Release-key rotation is a product-level event and requires shipping the new public cert in a trusted kernel before rotating signing in CI
- Host MOK rotation is local maintenance; `smooth-secureboot` should support re-enroll and cleanup
- Secure-Boot-disabled development machines remain valid for day-to-day hacking, but they are not the final validation target

## Open questions

- **One Smooth* release key or one per product family?** One key keeps the shared-kernel pipeline simple; per-product keys reduce blast radius.
- **How much of the MOK flow do we automate in the installer?** Full automation is ideal on local-console installs; remote installs need a documented manual recovery path.
