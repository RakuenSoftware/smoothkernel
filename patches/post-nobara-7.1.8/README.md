# post-nobara-7.1.8

Carry patches applied after `patches/nobara-picks/`.

Current `7.1.8` carry patches:

- `0001-drm-flag-non-atomic-async-page-flip-support.patch`
- `0002-drm-amd-display-drop-stale-crtc-async-flip-check.patch`
- `0003-sunrpc-bump-rpc-def-slot-table-entries-to-128.patch`

All three carried forward from the `7.0.11` lane **unchanged** — no rebase was
needed. Each still applies cleanly to a pristine kernel.org `7.1.8` tree after
the base and Nobara lanes.

Patches `0001`–`0002` are follow-on DRM / gamescope compatibility fixes. That
they still apply cleanly across the `6.19 → 7.0 → 7.1` line changes means the
upstream code they touch is unchanged and the fixes have **not** landed in 7.1
either. Removal condition is unchanged: drop each one once the equivalent
change is merged upstream. Re-check on the next bump — a clean apply that
suddenly fails usually means upstream absorbed it.

Patch `0003` raises the initial NFS/RPC in-flight window from the upstream
default of 16 to 128. Measured on a SmoothNAS 2.5 Gbps backup path: the default
of 16 caps single-connection NFSv4 on small-file workloads at ~82% of line; 128
lifts the same run to ~92%. The dynamic auto-grow path is unchanged, so this
only seeds the initial window before a runtime `sunrpc.tcp_slot_table_entries`
write has happened.

## Verification

Applied in order to a pristine kernel.org `7.1.8` tarball on top of the
`cachyos-7.1.8` and `nobara-picks` lanes. All three: applies clean, no fuzz.

The measured NFS throughput numbers above are carried over from the `7.0.11`
lane and have **not** been re-measured on `7.1.8`.
