# post-nobara-6.19.12

Carry patches applied after `patches/nobara-picks/`.

Current `6.19.12` carry patches:

- `0001-drm-flag-non-atomic-async-page-flip-support.patch`
- `0002-drm-amd-display-drop-stale-crtc-async-flip-check.patch`
- `0003-sunrpc-bump-rpc-def-slot-table-entries-to-128.patch`

Patches `0001`–`0002` are follow-on DRM / gamescope compatibility fixes
rebased for the pristine `6.19.12` tree after the base and Nobara lanes.

Patch `0003` raises the initial NFS/RPC in-flight window from the
upstream default of 16 to 128. Measured on a SmoothNAS 2.5 Gbps backup
path: the default of 16 caps single-connection NFSv4 on small-file
workloads at ~82% of line; 128 lifts the same run to ~92%. The dynamic
auto-grow path is unchanged, so this only seeds the initial window
before a runtime `sunrpc.tcp_slot_table_entries` write has happened.
