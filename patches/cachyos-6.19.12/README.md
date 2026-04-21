# cachyos-6.19.12

Vendored base-lane patches applied first to a pristine kernel.org `6.19.12`
tree.

Current contents:

- `6.19/sched/0001-bore.patch`

Note: `0001-bore-cachy.patch` from the same lane does not apply cleanly to a
pristine kernel.org `6.19.12` tarball. SmoothKernel vendors the
kernel.org-applicable `bore` patch as the base scheduler lane.
