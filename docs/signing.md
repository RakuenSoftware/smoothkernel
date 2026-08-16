# Module signing

Shipped Smooth* systems support Secure Boot without giving up DKMS-delivered modules such as ZFS, `smoothfs`, or NVIDIA.

This document is the production signing contract. The repository does not store private keys. A local `make kernel` build is valid for bring-up, but an artifact is not promotable to users until the release path has satisfied the signing and verification gates below.

The design uses two trust domains because the module sources come from two places:

- **Rakuen release key** for modules shipped inside release-built packages such as `linux-smoothkernel`
- **Per-host MOK key** for modules built on the target system by DKMS

## v1 trust model

### 1. Release-built modules

`linux-smoothkernel` release builds must be produced in signing-capable CI with a Rakuen-controlled module-signing key.

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

In v1 every flavor meta-package depends on it, so Secure-Boot-capable installs get the same signing/bootstrap contract without per-flavor drift.

## Boot and enrollment flow

Initial install on Secure-Boot-capable systems:

1. Installer lays down the OS, installs the flavor meta-package, and therefore installs `smooth-secureboot`
2. `smooth-secureboot` generates the per-host MOK keypair
3. Installer queues MOK enrollment with `mokutil --import`
4. First reboot enters the standard MOK enrollment screen
5. Subsequent DKMS rebuilds sign modules automatically with the enrolled key

Headless flavors still use the same mechanism; the console flow is part of the appliance bring-up checklist.
On systems not using Secure Boot, `smooth-secureboot` remains installed but enrollment and DKMS-signing enforcement can no-op cleanly.

## Kernel configuration contract

The shipped kernel posture is:

- `CONFIG_MODULE_SIG=y` — modules are signed
- `CONFIG_MODULE_SIG_FORCE` — **target `y`, currently not set.** See "Enforcement is staged" below.
- release builds inject the Rakuen module-signing certificate at build time
- revocation keys remain explicitly managed rather than inherited from Debian packaging defaults

The checked-in `.config` does not hard-code private material or machine-local paths.

## Enforcement is staged

Signing and *enforcing* signatures are separate steps, and the second one has
prerequisites. Enforcement turned on early does not harden the system, it makes
it unbootable-into-usefulness: the per-host DKMS key is only trusted once it has
been enrolled via UEFI/MOK, so enforcing before enrollment rejects ZFS and
`smoothfs` along with genuinely untrusted modules.

Measured on a `7.1.8` test VM (see [`kernel-config.md`](kernel-config.md) for the
full table): with `lockdown=integrity` the unsigned test module was rejected —
and so was the DKMS-signed `zfs`, with `Operation not permitted`.

The required order is:

1. **Sign the kernel image** with a Secure-Boot-trusted key, in signing-capable
   CI. Until this happens the kernel does not boot on a Secure Boot machine at
   all — a locally built `7.1.8` image has no signature table and shim refuses
   it with `error: bad shim signature`.
2. **Boot under Secure Boot.**
3. **Enroll the per-host MOK** via `smooth-secureboot`, so DKMS-built modules
   are signed by a key the kernel trusts.
4. **Only then raise enforcement.**

### Where enforcement is switched on

Enforcement is `smooth-secureboot`'s responsibility, not this repository's. It
owns MOK generation, enrollment and status, so it is the only component that
knows whether step 3 actually succeeded on a given host.

The contract for `smooth-secureboot`:

- After enrollment is confirmed — the MOK is enrolled *and* a DKMS-built module
  loads — add `lockdown=integrity` to the kernel command line and leave it off
  otherwise.
- Never enable enforcement on a host where enrollment did not complete, or on a
  non-Secure-Boot host: there is no trusted keyring for the DKMS key there, so
  enforcement only breaks storage.
- Provide a status command that reports the four states distinctly: not
  Secure Boot / Secure Boot without enrollment / enrolled without enforcement /
  enrolled and enforcing.
- Make it reversible. Dropping the parameter must restore module loading, since
  this is the recovery path when a DKMS module legitimately fails to sign.

SmoothKernel deliberately does **not** set `CONFIG_MODULE_SIG_FORCE` or a forced
lockdown mode, because a kernel-config switch applies to every install
regardless of whether that host can enroll a key. Debian achieves the
Secure-Boot-only behaviour with `CONFIG_LOCK_DOWN_IN_EFI_SECURE_BOOT`, which is
a Debian downstream patch and is not available in a pristine kernel.org tree.
Adopting it would mean carrying that patch in `post-nobara-<version>/`; that is
a live option if we want in-kernel parity rather than a command-line policy.

## Build and release flow

Developer builds are allowed to use local throwaway keys for bring-up, but only CI-produced release artifacts that satisfy this signing contract are promotable to the apt repo.

Release build flow:

1. CI fetches signing material from KMS / HSM-backed secret storage
2. Kernel build signs packaged modules with the Rakuen release key
3. Resulting `.deb`s are published to the apt repo
4. Test boxes enrolled with `smooth-secureboot` verify that DKMS consumers (`zfs-dkms`, `smoothfs`, optional NVIDIA) rebuild and load successfully

### Repository secrets

`.github/workflows/release.yml` reads three secrets. Provision them on the
repository (or its environment) before expecting a promotable artifact:

| Secret | Contents |
|---|---|
| `RAKUEN_MODULE_SIGNING_KEY` | PEM holding the module-signing **private key and its certificate**, concatenated. Signs packaged modules and is embedded in the kernel's builtin trusted keyring. |
| `RAKUEN_SECUREBOOT_SIGNING_KEY` | PEM private key used to sign the kernel **image** so shim will load it. |
| `RAKUEN_SECUREBOOT_SIGNING_CERT` | The matching certificate for the above. |

The two Secure Boot secrets must be set together; setting one alone fails the
build rather than silently producing an unsigned image.

Generating a key pair of the right shape (do this in your KMS/HSM workflow, not
on a laptop — shown here for structure only):

```sh
openssl req -new -x509 -newkey rsa:2048 -nodes -days 3650 \
  -subj "/CN=Rakuen Software module signing key/" \
  -keyout signing.key -out signing.crt
cat signing.key signing.crt > signing.pem   # -> RAKUEN_MODULE_SIGNING_KEY
```

For the kernel image to be accepted by shim without per-machine enrolment, the
certificate must be signed into the Secure Boot chain (a shim review, or a
vendor CA). Until that exists, an enrolled MOK is the practical route and the
image is trusted only on machines that enrolled it.

### Behaviour when secrets are absent

Fork pull requests do not receive secrets, and a repository that has not yet
provisioned them still needs to build. In that case the workflow:

- emits a warning that the build is unsigned,
- drops `UNSIGNED-NOT-PROMOTABLE.txt` into the artifact directory,
- and skips the signing verification gates (there is nothing to verify).

Those artifacts are valid for development and functional testing, and must not
be published to the apt repo. When secrets *are* present, the verification gates
run and a failure blocks the release rather than warning about it.

### Local builds

`recipes/build-kernel.sh` takes the same material through
`MODULE_SIGNING_KEY`, `SECUREBOOT_SIGNING_KEY` and `SECUREBOOT_SIGNING_CERT`.
Unset, it warns and builds a developer kernel: packaged modules get the
ephemeral `Build time autogenerated kernel key` and the image has no EFI
signature.

## Verification

Minimum verification before publish:

- `modinfo -F signer` on a packaged module from `linux-smoothkernel`
- `modinfo -F signer` on a DKMS-built module such as ZFS
- successful module load on a Secure-Boot-enabled test machine
- negative test: unsigned ad-hoc module load is rejected

Three of these four cannot be satisfied by a local `make kernel` build, so do
not treat a green developer run as having exercised them:

| Gate | Local dev build | Notes |
|---|---|---|
| packaged-module signer | partial | reports `Build time autogenerated kernel key`, an ephemeral per-build key — not the Rakuen release key. Only CI can satisfy this. |
| DKMS-module signer | yes | reports `DKMS module signing key`. |
| load under Secure Boot | **no** | the locally built image is unsigned, so it never boots there. |
| unsigned module rejected | **no** | requires enforcement, which requires the enrollment chain above. |

When running the negative test, first run it against a **stock distribution
kernel on the same Secure Boot machine**. A negative test that cannot fail
proves nothing, and on a kernel without enforcement it will silently "pass" by
loading the module. The stock kernel should reject it with
`Key was rejected by service`; only then is the same result on a SmoothKernel
build meaningful.

## Operational notes

- Release-key rotation is a product-level event and requires shipping the new public cert in a trusted kernel before rotating signing in CI
- Host MOK rotation is local maintenance; `smooth-secureboot` should support re-enroll and cleanup
- Secure-Boot-disabled development machines remain valid for day-to-day hacking, but they are not the final validation target

## Open questions

- **One Smooth* release key or one per product family?** One key keeps the shared-kernel pipeline simple; per-product keys reduce blast radius.
- **How much of the MOK flow do we automate in the installer?** Full automation is ideal on local-console installs; remote installs need a documented manual recovery path.
