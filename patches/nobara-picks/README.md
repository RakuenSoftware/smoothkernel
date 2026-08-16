# nobara-picks

Cherry-picked Nobara patches that apply after the base CachyOS-derived lane.

This lane is intentionally unversioned: the picks continue to apply cleanly
across current supported kernels. All three were re-verified against a pristine
kernel.org `7.1.8` tree on top of the `cachyos-7.1.8` base lane during the
`7.0.11 → 7.1.8` bump and applied without rebase.

One caveat from that run: `0001-Allow-to-set-custom-USB-pollrate-for-specific-device.patch`
applied with **fuzz 1** on hunk 1, which is the
`Documentation/admin-guide/kernel-parameters.txt` hunk (offset 233 lines) —
documentation only, no code impact. The three code hunks in
`drivers/usb/core/` applied clean. Fuzz is the signal that upstream is drifting
underneath the pick, so re-check this one on the next bump; if the code hunks
ever start fuzzing, rebase rather than accept.

Current picks:

- `0001-Allow-to-set-custom-USB-pollrate-for-specific-device.patch`
- `0002-ps-logitech-wheel.patch`
- `0003-xpadneo-kernel-integration.patch`

These stay narrowly scoped to controller / HID improvements that apply cleanly
to the pristine kernel.org + BORE base:

- USB interrupt-interval override for specific devices, useful for wired PS4 /
  PS5 controller pollrate tuning
- Logitech G923 PlayStation wheel support
- `xpadneo` Bluetooth Xbox controller integration
