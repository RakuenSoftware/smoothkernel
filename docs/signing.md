# Module signing (placeholder)

Out-of-tree modules need to be signed when:
- The target appliance kernel has `CONFIG_MODULE_SIG_FORCE=y`
- Secure Boot is enforcing module signatures via `lockdown_lsm`

This doc is the placeholder for the cross-Smooth* signing pipeline. The plan, when we have a second Smooth* OS to validate against:

1. **Key custody.** Per-deployment signing keys, generated once, never checked into git. Stored in a secrets manager (TBD: GCP/AWS KMS, HashiCorp Vault, age-encrypted file in a private repo).
2. **MOK enrollment.** First-boot script enrolls the public key in MOK so signed modules load.
3. **Sign step.** After `make kernel` and `make zfs` complete, a separate `make sign KEY=<path-or-id>` target signs every `.ko` in the .debs and re-builds the .debs with the signatures embedded.
4. **Verification.** `modprobe --verify` (or just `insmod` with `CONFIG_MODULE_SIG_FORCE`) confirms signatures load.

Until we have a second Smooth* OS to validate the signing pipeline against, SmoothNAS uses unsigned modules with a `CONFIG_MODULE_SIG_FORCE=n` kernel. This is a Phase 0.10 blocker for SmoothNAS appliance shipping; resolution will land here as part of that work.

## Open questions

- **Single root key or per-OS keys?** Single root key is simpler ops but leaks all OSes if compromised. Per-OS keys are cleaner blast-radius but more enrollment ceremony.
- **Where do keys live?** The custody system has to outlast any single engineer's laptop. Pick something with audit logs.
- **MOK or shim?** MOK is simpler; `shim-signed` lets us chain to Microsoft's UEFI key. Pick based on whether the appliance hardware ships Secure-Boot-on-by-default.
