# nobara-picks

Cherry-picked Nobara patches that apply after the base CachyOS-derived lane.

Current `6.19.12` picks:

- `0001-Allow-to-set-custom-USB-pollrate-for-specific-device.patch`
- `0002-ps-logitech-wheel.patch`
- `0003-xpadneo-kernel-integration.patch`

These stay narrowly scoped to controller / HID improvements that apply cleanly
to the pristine kernel.org + BORE base:

- USB interrupt-interval override for specific devices, useful for wired PS4 /
  PS5 controller pollrate tuning
- Logitech G923 PlayStation wheel support
- `xpadneo` Bluetooth Xbox controller integration
