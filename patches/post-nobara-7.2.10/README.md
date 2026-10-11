# post-nobara-7.2.10

The three carries from `post-nobara-7.1.8` still apply unchanged and without
fuzz after the current CachyOS and Nobara lanes on Linux 7.2.10:

- `0001-drm-flag-non-atomic-async-page-flip-support.patch`
- `0002-drm-amd-display-drop-stale-crtc-async-flip-check.patch`
- `0003-sunrpc-bump-rpc-def-slot-table-entries-to-128.patch`

The first two remain display/gamescope compatibility fixes. Remove them when
upstream absorbs the same changes. The last preserves the initial NFS/RPC
window of 128; its prior throughput measurements have not been repeated on
7.2.10. Kernel source SHA256: `2feaa70453e91f541be6a5c9078d8168e081af45a3d9718054850538cff2ebf3`.

See `docs/validation/7.2.10.md` for build checks and remaining runtime gates.
